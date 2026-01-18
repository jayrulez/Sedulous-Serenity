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

	/// Depends on forward opaque (uses same color/depth buffers).
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
	}

	// Transparent render pipelines for different blend modes
	private IRenderPipeline mAlphaBlendPipeline ~ delete _;
	private IRenderPipeline mAdditivePipeline ~ delete _;
	private IRenderPipeline mMultiplyPipeline ~ delete _;
	// Pipeline layout is borrowed from ForwardOpaqueFeature - don't delete
	private IPipelineLayout mTransparentPipelineLayout;

	// Object uniform buffer for transparent objects (with dynamic offset)
	private IBuffer mObjectUniformBuffer ~ delete _;
	private IBindGroup mSceneBindGroup ~ delete _;
	private const int MaxTransparentObjects = 256;
	private const uint64 ObjectUniformAlignment = 256;
	private const uint64 AlignedObjectUniformSize = ((ObjectUniforms.Size + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

	protected override Result<void> OnInitialize()
	{
		// Create object uniform buffer for transparent objects
		if (CreateObjectUniformBuffer() case .Err)
			return .Err;

		// Create transparent pipelines for different blend modes
		// Note: This may return Ok even if pipelines aren't created yet
		// (if ForwardOpaqueFeature hasn't initialized). Pipelines will be
		// created lazily on first use.
		if (CreateTransparentPipelines() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateObjectUniformBuffer()
	{
		BufferDescriptor desc = .()
		{
			Label = "Transparent Object Uniforms",
			Size = AlignedObjectUniformSize * MaxTransparentObjects,
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		switch (Renderer.Device.CreateBuffer(&desc))
		{
		case .Ok(let buf): mObjectUniformBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateTransparentPipelines()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Load forward shaders with transparent flags
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("forward", .NormalMap | .DefaultTransparent);
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		// Get ForwardOpaqueFeature to reuse its pipeline layout
		// The transparent feature uses the same scene bind group as opaque
		let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		if (opaqueFeature == null)
			return .Ok; // ForwardOpaqueFeature not initialized yet

		// Get the forward pipeline layout from opaque feature (reuse same layout)
		let forwardLayout = opaqueFeature.[Friend]mForwardPipelineLayout;
		if (forwardLayout == null)
			return .Ok; // Pipeline layout not created yet

		// Use the same pipeline layout as ForwardOpaqueFeature
		// (scene bind group + material bind group, same bindings)
		mTransparentPipelineLayout = forwardLayout;

		// Vertex layout from material system (default to Mesh layout)
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Create alpha blend pipeline (standard transparency)
		{
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, .AlphaBlend)
			);

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Transparent Alpha Blend Pipeline",
				Layout = mTransparentPipelineLayout,
				Vertex = .()
				{
					Shader = .(vertShader.Module, "main"),
					Buffers = vertexBuffers
				},
				Fragment = .()
				{
					Shader = .(fragShader.Module, "main"),
					Targets = colorTargets
				},
				Primitive = .()
				{
					Topology = .TriangleList,
					FrontFace = .CCW,
					CullMode = .None // Render both sides for transparent objects
				},
				DepthStencil = .Transparent,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mAlphaBlendPipeline = pipeline;
			case .Err: return .Err;
			}
		}

		// Create additive blend pipeline
		{
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, .Additive)
			);

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Transparent Additive Pipeline",
				Layout = mTransparentPipelineLayout,
				Vertex = .()
				{
					Shader = .(vertShader.Module, "main"),
					Buffers = vertexBuffers
				},
				Fragment = .()
				{
					Shader = .(fragShader.Module, "main"),
					Targets = colorTargets
				},
				Primitive = .()
				{
					Topology = .TriangleList,
					FrontFace = .CCW,
					CullMode = .None
				},
				DepthStencil = .Transparent,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mAdditivePipeline = pipeline;
			case .Err: return .Err;
			}
		}

		// Create multiply blend pipeline
		{
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, .Multiply)
			);

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Transparent Multiply Pipeline",
				Layout = mTransparentPipelineLayout,
				Vertex = .()
				{
					Shader = .(vertShader.Module, "main"),
					Buffers = vertexBuffers
				},
				Fragment = .()
				{
					Shader = .(fragShader.Module, "main"),
					Targets = colorTargets
				},
				Primitive = .()
				{
					Topology = .TriangleList,
					FrontFace = .CCW,
					CullMode = .None
				},
				DepthStencil = .Transparent,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mMultiplyPipeline = pipeline;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
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

		// Upload transparent object uniforms and create scene bind group
		PrepareTransparentObjectUniforms(world);
		CreateSceneBindGroup();

		// Add transparent pass
		// Note: Must be NeverCull because render graph culling only preserves FirstWriter,
		// and ForwardOpaque is the first writer of SceneColor
		graph.AddGraphicsPass("ForwardTransparent")
			.WriteColor(colorHandle, .Load, .Store) // Load existing color, blend on top
			.ReadDepth(depthHandle) // Read depth, don't write
			.NeverCull() // Don't cull - we need to render on top of opaque
			.SetExecuteCallback(new (encoder) => {
				ExecuteTransparentPass(encoder, world, view);
			});
	}

	private void PrepareTransparentObjectUniforms(RenderWorld world)
	{
		if (mObjectUniformBuffer == null || mSortedDraws.Count == 0)
			return;

		if (let bufferPtr = mObjectUniformBuffer.Map())
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
			mObjectUniformBuffer.Unmap();
		}
	}

	private void CreateSceneBindGroup()
	{
		// Delete old bind group if exists
		if (mSceneBindGroup != null)
		{
			delete mSceneBindGroup;
			mSceneBindGroup = null;
		}

		// Get ForwardOpaqueFeature for shared resources
		let opaqueFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		if (opaqueFeature == null)
			return;

		// Get scene bind group layout from opaque feature
		let sceneLayout = opaqueFeature.[Friend]mSceneBindGroupLayout;
		if (sceneLayout == null)
			return;

		// Get shared resources from lighting system and shadow renderer
		let lighting = opaqueFeature.[Friend]mLighting;
		let shadowRenderer = opaqueFeature.[Friend]mShadowRenderer;
		if (lighting == null)
			return;

		let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
		let lightingBuffer = lighting.LightBuffer?.UniformBuffer;
		let lightDataBuffer = lighting.LightBuffer?.LightDataBuffer;
		let clusterInfoBuffer = lighting.ClusterGrid?.ClusterLightInfoBuffer;
		let lightIndexBuffer = lighting.ClusterGrid?.LightIndexBuffer;

		if (cameraBuffer == null || mObjectUniformBuffer == null ||
			lightingBuffer == null || lightDataBuffer == null ||
			clusterInfoBuffer == null || lightIndexBuffer == null)
			return;

		// Build bind group entries (same structure as ForwardOpaqueFeature)
		BindGroupEntry[9] entries = .();

		// b0: Camera uniforms
		entries[0] = BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size);

		// b1: Object uniforms (dynamic offset - our own buffer for transparent objects)
		entries[1] = BindGroupEntry.Buffer(1, mObjectUniformBuffer, 0, AlignedObjectUniformSize);

		// b3: Lighting uniforms
		entries[2] = BindGroupEntry.Buffer(3, lightingBuffer, 0, (uint64)LightingUniforms.Size);

		// t4: Lights storage buffer
		entries[3] = BindGroupEntry.Buffer(4, lightDataBuffer, 0, (uint64)(lighting.LightBuffer.MaxLights * GPULight.Size));

		// t5: ClusterLightInfo storage buffer
		entries[4] = BindGroupEntry.Buffer(5, clusterInfoBuffer, 0, (uint64)(lighting.ClusterGrid.Config.TotalClusters * 8));

		// t6: LightIndices storage buffer
		entries[5] = BindGroupEntry.Buffer(6, lightIndexBuffer, 0, (uint64)(lighting.ClusterGrid.Config.MaxLightsPerCluster * lighting.ClusterGrid.Config.TotalClusters * 4));

		// Get shadow resources
		let shadowsEnabled = shadowRenderer?.EnableShadows ?? false;
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
			mSceneBindGroup = bg;
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

	private void ExecuteTransparentPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Check we have a valid scene bind group
		if (mSceneBindGroup == null)
			return;

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Track current pipeline and material to minimize state changes
		IRenderPipeline currentPipeline = null;
		MaterialInstance currentMaterial = null;

		// Render sorted transparent objects (back-to-front)
		for (let sortedDraw in mSortedDraws)
		{
			// Verify proxy still exists (mesh data stored in sortedDraw)
			if (world.GetMesh(sortedDraw.ProxyHandle) != null)
			{
				if (let mesh = Renderer.ResourceManager.GetMesh(sortedDraw.MeshHandle))
				{
					// Get material instance (use default if none assigned)
					MaterialInstance material = sortedDraw.Material ?? defaultMaterialInstance;

					// Select pipeline based on material blend mode
					IRenderPipeline targetPipeline = mAlphaBlendPipeline;
					if (material != null)
					{
						switch (material.BlendMode)
						{
						case .Additive:
							targetPipeline = mAdditivePipeline;
						case .Multiply:
							targetPipeline = mMultiplyPipeline;
						default:
							targetPipeline = mAlphaBlendPipeline;
						}
					}

					// Set pipeline if changed
					if (targetPipeline != currentPipeline && targetPipeline != null)
					{
						encoder.SetPipeline(targetPipeline);
						currentPipeline = targetPipeline;
					}

					// Bind material if changed
					if (material != currentMaterial && material != null && materialSystem != null)
					{
						if (materialSystem.PrepareInstance(material) case .Ok(let bindGroup))
						{
							encoder.SetBindGroup(1, bindGroup, default);
							currentMaterial = material;
						}
					}

					// Bind scene bind group with dynamic offset for this object's transforms
					uint32[1] dynamicOffsets = .((uint32)(sortedDraw.ObjectIndex * (int32)AlignedObjectUniformSize));
					encoder.SetBindGroup(0, mSceneBindGroup, dynamicOffsets);

					// Bind vertex/index buffers
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

					// Draw
					if (mesh.IndexBuffer != null)
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					else
						encoder.Draw(mesh.VertexCount, 1, 0, 0);

					Renderer.Stats.DrawCalls++;
					Renderer.Stats.TransparentDrawCalls++;
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
