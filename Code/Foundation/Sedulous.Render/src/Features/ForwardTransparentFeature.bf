namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.RenderGraph;

/// Forward transparent render feature.
/// Renders all transparent geometry with back-to-front sorting.
public class ForwardTransparentFeature : RenderFeatureBase
{
	// Sorted transparent draws
	private List<SortedDraw> mSortedDraws = new .() ~ delete _;

	/// Feature name.
	public override StringView Name => "ForwardTransparent";

	/// Depends on forward opaque and sky (transparent renders on top of sky).
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
		outDependencies.Add("Sky");
	}

	// Scene bind group layout borrowed from ForwardOpaqueFeature - don't delete

	// Object uniform buffers for transparent objects (per-frame for multi-buffering)
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers;
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroups;
	private bool[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupShadowState; // Track shadow state for runtime toggling
	private bool[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupIBLState;
	private uint32[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupProbeGeneration;
	private const uint64 ObjectUniformAlignment = 256;
	private const uint64 AlignedObjectUniformSize = ((ObjectUniforms.Size + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;
	private static int32 MaxTransparentObjects => RenderConfig.MaxTransparentObjectsPerFrame;

	protected override Result<void> OnInitialize(InitContext initCtx)
	{
		// Create object uniform buffer for transparent objects
		if (CreateObjectUniformBuffer() case .Err)
			return .Err;


		return .Ok;
	}

	private Result<void> CreateObjectUniformBuffer()
	{
		// Create per-frame object uniform buffers
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc desc = .()
			{
				Label = "Transparent Object Uniforms",
				Size = AlignedObjectUniformSize * (uint64)MaxTransparentObjects,
				Usage = .Uniform,
				Memory = .CpuToGpu
			};

			switch (Renderer.Device.CreateBuffer(desc))
			{
			case .Ok(let buf): mObjectUniformBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	/// Depth bias for transparent geometry to avoid z-fighting with coplanar surfaces.
	/// Negative value pushes fragments slightly further from camera.
	private const int16 TransparentDepthBias = -1;
	private const float TransparentDepthBiasSlopeScale = -1.0f;

	/// Gets a pipeline for a transparent material with the specified cull mode.
	/// Uses the pipeline cache for dynamic pipeline creation.
	/// Pipeline layouts are created dynamically by the cache from scene + material layouts.
	private IRenderPipeline GetPipelineForMaterial(MaterialInstance material, bool shadowsEnabled, bool backFaces)
	{
		let pipelineCache = Renderer.PipelineCache;
		let materialSystem = Renderer.MaterialSystem;
		if (pipelineCache == null || Renderer.SharedLayouts.SceneLayout == null || materialSystem == null)
			return null;

		// Get or create the material's bind group layout
		let baseMaterial = material?.Material;
		if (baseMaterial == null)
			return null;

		IBindGroupLayout materialLayout = null;
		if (materialSystem.GetOrCreateLayout(baseMaterial) case .Ok(let layout))
			materialLayout = layout;
		else
			return null;

		// Build variant flags for cull mode
		PipelineVariantFlags variantFlags = backFaces ? .FrontFaceCull : .BackFaceCull;
		if (shadowsEnabled)
			variantFlags |= .ReceiveShadows;

		// Vertex layout for transparent meshes
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Get pipeline from cache with transparent depth mode (read-only)
		// Apply depth bias to avoid z-fighting with coplanar opaque geometry
		if (pipelineCache.GetPipelineForMaterial(
			material,
			vertexBuffers,
			Renderer.SharedLayouts.SceneLayout,
			materialLayout,
			.RGBA16Float,
			Renderer.DepthFormat,
			1,
			variantFlags,
			.ReadOnly,      // Transparent objects don't write depth
			.LessEqual,
			TransparentDepthBias,
			TransparentDepthBiasSlopeScale) case .Ok(let pipeline))
		{
			return pipeline;
		}

		return null;
	}

	protected override void OnShutdown()
	{
		let device = Renderer.Device;

		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mObjectUniformBuffers[i] != null)
				device.DestroyBuffer(ref mObjectUniformBuffers[i]);
		}

		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mSceneBindGroups[i] != null)
				device.DestroyBindGroup(ref mSceneBindGroups[i]);
		}
	}

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderableList renderables)
	{
		// Get depth prepass feature for visibility data
		let depthFeature = Renderer.GetFeature<DepthPrepassFeature>();
		if (depthFeature == null)
			return;

		// Get existing resources
		let depthHandle = graph.GetResource("SceneDepth");
		let colorHandle = graph.GetResource("SceneColor");

		if (!depthHandle.IsValid || !colorHandle.IsValid)
			return;

		// Sort transparent objects back-to-front
		SortTransparentDraws(renderables, depthFeature, view);

		// Skip if no transparent objects
		if (mSortedDraws.Count == 0)
			return;

		// Upload transparent object uniforms and create scene bind group for current frame
		let frameIndex = view.FrameIndex;
		let bgIndex = view.GetBindGroupIndex();
		PrepareTransparentObjectUniforms(frameIndex);
		CreateSceneBindGroup(frameIndex, bgIndex);

		// Add transparent pass
		// Note: Must be NeverCull because render graph culling only preserves FirstWriter,
		// and ForwardOpaque is the first writer of SceneColor
		RenderableList renderablesRef = renderables;
		graph.AddRenderPass("ForwardTransparent", scope (builder) => {
				builder.SetColorTarget(0, colorHandle, .Load, .Store); // Load existing color, blend on top
				builder.ReadDepth(depthHandle); // Read depth, don't write
				builder.NeverCull(); // Don't cull - we need to render on top of opaque
				builder.SetExecute(new /*[&, =frameIndex, =bgIndex]*/(encoder) => {
					ExecuteTransparentPass(encoder, renderablesRef, view, frameIndex, bgIndex);
				});
			});
	}

	private void PrepareTransparentObjectUniforms(int32 frameIndex)
	{
		// Use current frame's buffer
		let objectUniformBuffer = mObjectUniformBuffers[frameIndex];
		if (objectUniformBuffer == null || mSortedDraws.Count == 0)
			return;

		if (let bufferPtr = objectUniformBuffer.Map())
		{
			int32 objectIndex = 0;
			for (var sortedDraw in ref mSortedDraws)
			{
				if (objectIndex >= MaxTransparentObjects)
					break;

				ObjectUniforms objUniforms = .()
				{
					WorldMatrix = sortedDraw.WorldMatrix,
					PrevWorldMatrix = sortedDraw.PrevWorldMatrix,

					ObjectID = (uint32)objectIndex,
					MaterialID = 0,
					_Padding = .(0, 0)
				};

				let bufferOffset = (uint64)objectIndex * AlignedObjectUniformSize;
				Internal.MemCpy((uint8*)bufferPtr + bufferOffset, &objUniforms, ObjectUniforms.Size);

				// Store the object index for dynamic offset during rendering
				sortedDraw.ObjectIndex = objectIndex;
				objectIndex++;
			}
			objectUniformBuffer.Unmap();
		}
	}

	private void CreateSceneBindGroup(int32 frameIndex, int32 bgIndex)
	{
		// Get ForwardOpaqueFeature for shared resources
		let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		if (opaqueFeature == null)
			return;

		// Use shadow passes active state (not just EnableShadows) to avoid binding
		// an uninitialized shadow map when shadow passes haven't run yet
		let shadowsEnabled = Renderer.ShadowRenderer.ShadowPassesActive;

		// Check IBL state
		let skyFeature = Renderer.GetFeature<SkyFeature>();
		let hasRealIBL = skyFeature?.IrradianceMapView != null;

		// Check probe state
		let probeSystem = Renderer.ProbeSystem;
		let probeGeneration = probeSystem?.Generation ?? 0;

		let bindGroupIndex = bgIndex;

		// Check if bind group exists and state hasn't changed
		if (mSceneBindGroups[bindGroupIndex] != null)
		{
			if (mSceneBindGroupShadowState[bindGroupIndex] == shadowsEnabled &&
				mSceneBindGroupIBLState[bindGroupIndex] == hasRealIBL &&
				mSceneBindGroupProbeGeneration[bindGroupIndex] == probeGeneration)
				return; // State unchanged, keep existing bind group

			// State changed - destroy old bind group so we can recreate
			Renderer.Device.DestroyBindGroup(ref mSceneBindGroups[bindGroupIndex]);
		}

		// Create via shared helper (uses shared layout, RenderSystem subsystems)
		let bg = Renderer.SharedLayouts.CreateSceneBindGroup(frameIndex, mObjectUniformBuffers[frameIndex], probeSystem);
		if (bg != null)
		{
			mSceneBindGroups[bindGroupIndex] = bg;
			mSceneBindGroupShadowState[bindGroupIndex] = shadowsEnabled;
			mSceneBindGroupIBLState[bindGroupIndex] = hasRealIBL;
			mSceneBindGroupProbeGeneration[bindGroupIndex] = probeGeneration;
		}
	}

	private void SortTransparentDraws(RenderableList renderables, DepthPrepassFeature depthFeature, ViewContext view)
	{
		mSortedDraws.Clear();

		let cameraPos = view.CameraPosition;
		let batcher = Renderer.Batcher;
		let commands = batcher.DrawCommands;

		// Collect transparent draws from transparent batches
		for (let batch in batcher.TransparentBatches)
		{
			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				let cmd = commands[batch.CommandStart + i];

				if (cmd.RenderableIndex < 0 || cmd.RenderableIndex >= renderables.OpaqueMeshes.Count)
					continue;

				let mesh = ref renderables.OpaqueMeshes[cmd.RenderableIndex];

				// Calculate distance from camera to object center
				let center = (mesh.WorldBounds.Min + mesh.WorldBounds.Max) * 0.5f;
				let distSq = Vector3.DistanceSquared(cameraPos, center);

				mSortedDraws.Add(.()
				{
					RenderHandle = cmd.MeshHandle,
					RenderableIndex = cmd.RenderableIndex,
					MeshHandle = mesh.MeshHandle,
					Material = mesh.Materials[0],
					WorldMatrix = mesh.WorldMatrix,
					PrevWorldMatrix = mesh.PrevWorldMatrix,
					DistanceSquared = distSq
				});
			}
		}

		// Sort back-to-front (furthest first)
		mSortedDraws.Sort(scope (a, b) => {
			if (a.DistanceSquared > b.DistanceSquared)
				return -1;
			if (a.DistanceSquared < b.DistanceSquared)
				return 1;
			return 0;
		});
	}

	private void ExecuteTransparentPass(IRenderPassEncoder encoder, RenderableList renderables, ViewContext view, int32 frameIndex, int32 bgIndex)
	{
		// Set viewport — render to per-view SceneColor texture at (0,0), not swapchain offset
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, view.Width, view.Height);

		// Check we have a valid scene bind group for current frame
		let sceneBindGroup = mSceneBindGroups[bgIndex];
		if (sceneBindGroup == null)
			return;

		// Get shadow state (use active state, not just enabled)
		let shadowsEnabled = Renderer.ShadowRenderer?.ShadowPassesActive ?? false;

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Render sorted transparent objects (back-to-front)
		// Each object is rendered twice: back faces first, then front faces
		// This ensures correct ordering within each convex transparent object
		for (let sortedDraw in mSortedDraws)
		{
			// The renderable index was captured at sort time; it's stable for this frame.
			if (sortedDraw.RenderableIndex >= 0 && sortedDraw.RenderableIndex < renderables.OpaqueMeshes.Count)
			{
				let renderable = ref renderables.OpaqueMeshes[sortedDraw.RenderableIndex];
				if (let mesh = Renderer.ResourceManager.GetMesh(sortedDraw.MeshHandle))
				{
					// Bind scene bind group with dynamic offset for this object's transforms
					uint32[1] dynamicOffsets = .((uint32)(sortedDraw.ObjectIndex * (int32)AlignedObjectUniformSize));

					// Bind vertex/index buffers (shared across submeshes)
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

					if (mesh.SubMeshes != null)
					{
						for (let sub in mesh.SubMeshes)
						{
							// Resolve material for this submesh's material slot
							let matSlot = (int32)sub.MaterialSlot;
							MaterialInstance material = null;
							if (matSlot >= 0 && matSlot < renderable.MaterialCount)
								material = renderable.Materials[matSlot];
							if (material == null && matSlot >= 0 && renderable.MaterialCount > 0)
								material = renderable.Materials[0];
							if (material == null)
								material = defaultMaterialInstance;

							// Get pipelines from cache for this material
							let backPipeline = GetPipelineForMaterial(material, shadowsEnabled, true);
							let frontPipeline = GetPipelineForMaterial(material, shadowsEnabled, false);

							// Get material bind group
							IBindGroup materialBindGroup = null;
							if (material != null && materialSystem != null)
							{
								if (materialSystem.PrepareInstance(material) case .Ok(let bindGroup))
									materialBindGroup = bindGroup;
							}

							// Pass 1: Render back faces (interior)
							if (backPipeline != null)
							{
								encoder.SetPipeline(backPipeline);
								encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
								if (materialBindGroup != null)
									encoder.SetBindGroup(1, materialBindGroup, default);

								encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);
							}

							// Pass 2: Render front faces (exterior)
							if (frontPipeline != null)
							{
								encoder.SetPipeline(frontPipeline);
								encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
								if (materialBindGroup != null)
									encoder.SetBindGroup(1, materialBindGroup, default);

								encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);
							}

							Renderer.Stats.DrawCalls += 2;
							Renderer.Stats.TransparentDrawCalls += 2;
						}
					}
				}
			}
		}
	}

	/// Sorted draw entry.
	private struct SortedDraw
	{
		public MeshRenderHandle RenderHandle;
		public int32 RenderableIndex;
		public GPUMeshHandle MeshHandle;
		public MaterialInstance Material;
		public Matrix WorldMatrix;
		public Matrix PrevWorldMatrix;
		public float DistanceSquared;
		public int32 ObjectIndex; // Index into object uniform buffer for dynamic offset
	}
}
