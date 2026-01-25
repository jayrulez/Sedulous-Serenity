namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;

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
	private IBindGroupLayout mSceneBindGroupLayout;

	// Object uniform buffers for transparent objects (per-frame for multi-buffering)
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers;
	private IBindGroup[RenderConfig.FrameBufferCount] mSceneBindGroups;
	private bool[RenderConfig.FrameBufferCount] mSceneBindGroupShadowState; // Track shadow state for runtime toggling
	private const uint64 ObjectUniformAlignment = 256;
	private const uint64 AlignedObjectUniformSize = ((ObjectUniforms.Size + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;
	private static int32 MaxTransparentObjects => RenderConfig.MaxTransparentObjectsPerFrame;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => Renderer.RenderFrameContext?.FrameIndex ?? 0;

	protected override Result<void> OnInitialize()
	{
		// Create object uniform buffer for transparent objects
		if (CreateObjectUniformBuffer() case .Err)
			return .Err;

		// Get scene bind group layout from ForwardOpaqueFeature (used for pipeline creation)
		if (let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>())
			mSceneBindGroupLayout = opaqueFeature.[Friend]mSceneBindGroupLayout;

		return .Ok;
	}

	private Result<void> CreateObjectUniformBuffer()
	{
		// Create per-frame object uniform buffers
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDescriptor desc = .()
			{
				Label = "Transparent Object Uniforms",
				Size = AlignedObjectUniformSize * (uint64)MaxTransparentObjects,
				Usage = .Uniform,
				MemoryAccess = .Upload
			};

			switch (Renderer.Device.CreateBuffer(&desc))
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
		if (pipelineCache == null || mSceneBindGroupLayout == null || materialSystem == null)
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
			mSceneBindGroupLayout,
			materialLayout,
			.RGBA16Float,
			.Depth32Float,
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
		// Clean up per-frame resources
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mObjectUniformBuffers[i] != null)
			{
				delete mObjectUniformBuffers[i];
				mObjectUniformBuffers[i] = null;
			}

			if (mSceneBindGroups[i] != null)
			{
				delete mSceneBindGroups[i];
				mSceneBindGroups[i] = null;
			}
		}
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
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
		SortTransparentDraws(world, depthFeature, view);

		// Skip if no transparent objects
		if (mSortedDraws.Count == 0)
			return;

		// Upload transparent object uniforms and create scene bind group for current frame
		let frameIndex = FrameIndex;
		PrepareTransparentObjectUniforms(world, frameIndex);
		CreateSceneBindGroup(frameIndex);

		// Add transparent pass
		// Note: Must be NeverCull because render graph culling only preserves FirstWriter,
		// and ForwardOpaque is the first writer of SceneColor
		graph.AddGraphicsPass("ForwardTransparent")
			.WriteColor(colorHandle, .Load, .Store) // Load existing color, blend on top
			.ReadDepth(depthHandle) // Read depth, don't write
			.NeverCull() // Don't cull - we need to render on top of opaque
			.SetExecuteCallback(new (encoder) => {
				ExecuteTransparentPass(encoder, world, view, frameIndex);
			});
	}

	private void PrepareTransparentObjectUniforms(RenderWorld world, int32 frameIndex)
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

				if (let proxy = world.GetMesh(sortedDraw.ProxyHandle))
				{
					ObjectUniforms objUniforms = .()
					{
						WorldMatrix = proxy.WorldMatrix,
						PrevWorldMatrix = proxy.PrevWorldMatrix,
						NormalMatrix = proxy.NormalMatrix,
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
			}
			objectUniformBuffer.Unmap();
		}
	}

	private void CreateSceneBindGroup(int32 frameIndex)
	{
		// Get ForwardOpaqueFeature for shared resources
		let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		if (opaqueFeature == null)
			return;

		// Get shadow renderer to check current shadow state
		let shadowRenderer = opaqueFeature.[Friend]mShadowRenderer;
		let shadowsEnabled = shadowRenderer?.EnableShadows ?? false;

		// Check if bind group exists and shadow state hasn't changed
		if (mSceneBindGroups[frameIndex] != null)
		{
			if (mSceneBindGroupShadowState[frameIndex] == shadowsEnabled)
				return; // State unchanged, keep existing bind group

			// Shadow state changed - delete old bind group so we can recreate
			delete mSceneBindGroups[frameIndex];
			mSceneBindGroups[frameIndex] = null;
		}

		// Get scene bind group layout from opaque feature
		let sceneLayout = opaqueFeature.[Friend]mSceneBindGroupLayout;
		if (sceneLayout == null)
			return;

		// Get shared resources from lighting system
		let lighting = opaqueFeature.[Friend]mLighting;
		if (lighting == null)
			return;

		// Use frame-specific buffers
		let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
		let objectUniformBuffer = mObjectUniformBuffers[frameIndex];
		let lightingBuffer = lighting.LightBuffer?.GetUniformBuffer(frameIndex);
		let lightDataBuffer = lighting.LightBuffer?.GetLightDataBuffer(frameIndex);
		let clusterInfoBuffer = lighting.ClusterGrid?.GetClusterLightInfoBuffer(frameIndex);
		let lightIndexBuffer = lighting.ClusterGrid?.GetLightIndexBuffer(frameIndex);

		if (cameraBuffer == null || objectUniformBuffer == null ||
			lightingBuffer == null || lightDataBuffer == null ||
			clusterInfoBuffer == null || lightIndexBuffer == null)
			return;

		// Build bind group entries (same structure as ForwardOpaqueFeature)
		BindGroupEntry[9] entries = .();

		// b0: Camera uniforms
		entries[0] = BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size);

		// b1: Object uniforms (dynamic offset - our own buffer for transparent objects)
		entries[1] = BindGroupEntry.Buffer(1, objectUniformBuffer, 0, AlignedObjectUniformSize);

		// b3: Lighting uniforms
		entries[2] = BindGroupEntry.Buffer(3, lightingBuffer, 0, (uint64)LightingUniforms.Size);

		// t4: Lights storage buffer
		entries[3] = BindGroupEntry.Buffer(4, lightDataBuffer, 0, (uint64)(lighting.LightBuffer.MaxLights * GPULight.Size));

		// t5: ClusterLightInfo storage buffer
		entries[4] = BindGroupEntry.Buffer(5, clusterInfoBuffer, 0, (uint64)(lighting.ClusterGrid.Config.TotalClusters * 8));

		// t6: LightIndices storage buffer
		entries[5] = BindGroupEntry.Buffer(6, lightIndexBuffer, 0, (uint64)(lighting.ClusterGrid.Config.MaxLightsPerCluster * lighting.ClusterGrid.Config.TotalClusters * 4));

		// Get shadow resources (shadowsEnabled already computed at function start)
		let shadowData = shadowRenderer?.GetShadowShaderData() ?? .();
		let materialSystem = Renderer.MaterialSystem;

		// b5: Shadow uniforms
		if (shadowsEnabled && shadowData.CascadedShadowUniforms != null)
			entries[6] = BindGroupEntry.Buffer(5, shadowData.CascadedShadowUniforms, 0, (uint64)ShadowUniforms.Size);
		else
			entries[6] = BindGroupEntry.Buffer(5, lightingBuffer, 0, (uint64)LightingUniforms.Size); // Fallback

		// t7: Shadow map texture
		let dummyShadowMapView = opaqueFeature.[Friend]mDummyShadowMapArrayView;
		if (shadowsEnabled && shadowData.CascadedShadowMapView != null)
			entries[7] = BindGroupEntry.Texture(7, shadowData.CascadedShadowMapView);
		else if (dummyShadowMapView != null)
			entries[7] = BindGroupEntry.Texture(7, dummyShadowMapView);
		else
			return;

		// s1: Shadow sampler
		if (shadowData.CascadedShadowSampler != null)
			entries[8] = BindGroupEntry.Sampler(1, shadowData.CascadedShadowSampler);
		else if (materialSystem?.DefaultSampler != null)
			entries[8] = BindGroupEntry.Sampler(1, materialSystem.DefaultSampler);
		else
			return;

		// Create bind group
		BindGroupDescriptor bgDesc = .()
		{
			Label = "Transparent Scene BindGroup",
			Layout = sceneLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&bgDesc) case .Ok(let bg))
		{
			mSceneBindGroups[frameIndex] = bg;
			mSceneBindGroupShadowState[frameIndex] = shadowsEnabled; // Track state for runtime toggling
		}
	}

	private void SortTransparentDraws(RenderWorld world, DepthPrepassFeature depthFeature, RenderView view)
	{
		mSortedDraws.Clear();

		let cameraPos = view.CameraPosition;
		let batcher = depthFeature.[Friend]mBatcher;
		let commands = batcher.DrawCommands;

		// Collect transparent draws from transparent batches
		for (let batch in batcher.TransparentBatches)
		{
			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				let cmd = commands[batch.CommandStart + i];

				if (let proxy = world.GetMesh(cmd.MeshHandle))
				{
					// Calculate distance from camera to object center
					let center = (proxy.WorldBounds.Min + proxy.WorldBounds.Max) * 0.5f;
					let distSq = Vector3.DistanceSquared(cameraPos, center);

					mSortedDraws.Add(.()
					{
						ProxyHandle = cmd.MeshHandle,
						MeshHandle = proxy.MeshHandle,
						Material = proxy.Material,
						DistanceSquared = distSq
					});
				}
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

	private void ExecuteTransparentPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view, int32 frameIndex)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Check we have a valid scene bind group for current frame
		let sceneBindGroup = mSceneBindGroups[frameIndex];
		if (sceneBindGroup == null)
			return;

		// Get shadow state from opaque feature
		let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		let shadowsEnabled = opaqueFeature?.[Friend]mShadowRenderer?.EnableShadows ?? false;

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Render sorted transparent objects (back-to-front)
		// Each object is rendered twice: back faces first, then front faces
		// This ensures correct ordering within each convex transparent object
		for (let sortedDraw in mSortedDraws)
		{
			// Verify proxy still exists (mesh data stored in sortedDraw)
			if (world.GetMesh(sortedDraw.ProxyHandle) != null)
			{
				if (let mesh = Renderer.ResourceManager.GetMesh(sortedDraw.MeshHandle))
				{
					// Get material instance (use default if none assigned)
					MaterialInstance material = sortedDraw.Material ?? defaultMaterialInstance;

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

					// Bind scene bind group with dynamic offset for this object's transforms
					uint32[1] dynamicOffsets = .((uint32)(sortedDraw.ObjectIndex * (int32)AlignedObjectUniformSize));

					// Bind vertex/index buffers
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

					// Pass 1: Render back faces (interior)
					if (backPipeline != null)
					{
						encoder.SetPipeline(backPipeline);
						encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
						if (materialBindGroup != null)
							encoder.SetBindGroup(1, materialBindGroup, default);

						if (mesh.IndexBuffer != null)
							encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
						else
							encoder.Draw(mesh.VertexCount, 1, 0, 0);
					}

					// Pass 2: Render front faces (exterior)
					if (frontPipeline != null)
					{
						encoder.SetPipeline(frontPipeline);
						encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
						if (materialBindGroup != null)
							encoder.SetBindGroup(1, materialBindGroup, default);

						if (mesh.IndexBuffer != null)
							encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
						else
							encoder.Draw(mesh.VertexCount, 1, 0, 0);
					}

					Renderer.Stats.DrawCalls += 2;
					Renderer.Stats.TransparentDrawCalls += 2;
				}
			}
		}
	}

	/// Sorted draw entry.
	private struct SortedDraw
	{
		public MeshProxyHandle ProxyHandle;
		public GPUMeshHandle MeshHandle;
		public MaterialInstance Material;
		public float DistanceSquared;
		public int32 ObjectIndex; // Index into object uniform buffer for dynamic offset
	}
}
