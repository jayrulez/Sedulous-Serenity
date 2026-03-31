namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.Profiler;
using Sedulous.RenderGraph;

/// Per-object uniform data matching forward.vert.hlsl ObjectUniforms (b1, space0).
[CRepr]
struct ObjectUniforms
{
	public Matrix WorldMatrix;
	public Matrix PrevWorldMatrix;
	public uint32 ObjectID;
	public uint32 MaterialID;
	public float[2] _Padding;

	public const uint64 Size = 144; // 2 matrices (128) + 2 uint32 (8) + 2 float (8) = 144

	public static Self Identity => .()
	{
		WorldMatrix = .Identity,
		PrevWorldMatrix = .Identity,
		ObjectID = 0,
		MaterialID = 0,
		_Padding = .(0, 0)
	};
}

/// Forward opaque render feature.
/// Renders all opaque geometry with full PBR shading and clustered lighting.
public class ForwardOpaqueFeature : RenderFeatureBase
{
	// Lighting system (owned by RenderSystem, accessed via Renderer.LightingSystem)
	// Shadow renderer (owned by RenderSystem, accessed via Renderer.ShadowRenderer)
	// Shadow passes active flag on Renderer.ShadowRenderer.ShadowPassesActive

	// Bind groups (per-frame, per-view for multi-buffering)
	// Scene bind group layout is shared via Renderer.SharedLayouts.SceneLayout
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroups;

	// Object uniform buffers (per-frame for multi-buffering)
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers;
	private const uint64 ObjectUniformAlignment = 256; // Vulkan minUniformBufferOffsetAlignment
	private const uint64 AlignedObjectUniformSize = ((ObjectUniforms.Size + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

	// Pipeline cache is owned by RenderSystem - access via Renderer.PipelineCache

	// Shadow depth rendering (per-frame for multi-buffering)
	private IRenderPipeline mShadowDepthPipeline;
	private IPipelineLayout mShadowPipelineLayout;
	private IBindGroupLayout mShadowBindGroupLayout;
	private IBindGroup[RenderConfig.FrameBufferCount] mShadowBindGroups;
	private IBuffer[RenderConfig.FrameBufferCount] mShadowUniformBuffers; // Per-cascade SceneUniforms for light matrices
	private IBuffer[RenderConfig.FrameBufferCount] mShadowObjectBuffers;  // Per-object transforms for shadow pass
	private SceneUniforms mShadowUniforms; // CPU-side shadow uniforms
	private uint64 mAlignedSceneUniformSize; // Aligned size for dynamic uniform offset

	// Track shadow state when bind groups were created (for runtime toggling)
	private bool[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupShadowState;

	// Track IBL generation when bind groups were created (for runtime IBL swapping)
	private uint32[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupIBLGeneration;

	// Reflection probe system
	// Reflection probe system (owned by RenderSystem, accessed via Renderer.ProbeSystem)
	private uint32[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroupProbeGeneration;

	/// Feature name.
	public override StringView Name => "ForwardOpaque";

	/// Gets the lighting system (owned by RenderSystem).
	public LightingSystem Lighting => Renderer.LightingSystem;

	/// Gets the shadow renderer (owned by RenderSystem).
	public ShadowRenderer ShadowRenderer => Renderer.ShadowRenderer;

	/// Invalidates all cached scene bind groups so they are recreated next frame.
	/// Call before destroying IBL views that scene bind groups may reference.
	public void InvalidateSceneBindGroups()
	{
		let device = Renderer.Device;
		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mSceneBindGroups[i] != null)
				device.DestroyBindGroup(ref mSceneBindGroups[i]);
		}
	}

	/// Depends on depth prepass and GPU skinning.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("GPUSkinning");
		outDependencies.Add("DepthPrepass");
	}

	protected override Result<void> OnInitialize(InitContext initCtx)
	{
		// Lighting system initialized by RenderSystem (accessed via Renderer.LightingSystem)

		// Shadow renderer initialized by RenderSystem (accessed via Renderer.ShadowRenderer)

		// Scene bind group layout now shared via Renderer.SharedLayouts

		// Create object uniform buffer
		if (CreateObjectUniformBuffer() case .Err)
			return .Err;

		// Enable instancing if pipeline cache is available
		if (Renderer.PipelineCache != null)
			mInstancingEnabled = true;

		// Create shadow depth pipeline
		if (CreateShadowPipeline() case .Err)
			return .Err;

		// Reflection probe system initialized by RenderSystem

		return .Ok;
	}

	// Instancing state (uses instance buffer from DepthPrepassFeature)
	private bool mInstancingEnabled = false;

	// Shadow instancing
	private IRenderPipeline mShadowInstancedPipeline;
	private IPipelineLayout mShadowInstancedPipelineLayout;
	private IBindGroupLayout mShadowInstancedBindGroupLayout;
	private IBindGroup[RenderConfig.FrameBufferCount] mShadowInstancedBindGroups;
	private InstanceBufferManager mShadowInstanceBufferManager ~ { if (_ != null) { _.Shutdown(); delete _; } };
	private DrawBatcher mShadowBatcher = new .() ~ delete _;
	private bool mShadowInstancingEnabled = false;

	/// Gets the appropriate pipeline for a material.
	/// Uses the pipeline cache with caller-provided vertex layouts.
	/// The vertex layout is determined by the mesh type (instanced vs non-instanced), not the material.
	/// Pipeline layouts are created dynamically by the cache from scene + material layouts.
	/// Returns null if the pipeline cannot be created.
	private IRenderPipeline GetPipelineForMaterial(MaterialInstance material, bool shadowsEnabled, bool instanced)
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

		// Build variant flags
		PipelineVariantFlags variantFlags = .None;
		if (instanced)
			variantFlags |= .Instanced;
		if (shadowsEnabled)
			variantFlags |= .ReceiveShadows;

		// Determine vertex layout based on mesh type (not material)
		// These layouts match what the shaders expect
		if (instanced)
		{
			// Instanced: full mesh attrs + instance transforms
			// Mesh attributes match VertexLayoutHelper.MeshAttributes (48 bytes)
			Sedulous.RHI.VertexAttribute[5] meshAttrs = .(
				.(VertexFormat.Float3, 0, 0),            // Position
				.(VertexFormat.Float3, 12, 1),           // Normal
				.(VertexFormat.Float2, 24, 2),           // UV
				.(VertexFormat.UByte4Normalized, 32, 3), // Color
				.(VertexFormat.Float3, 36, 4)            // Tangent
			);
			// Instance data at locations 5-8 (after mesh attributes)
			Sedulous.RHI.VertexAttribute[4] instanceAttrs = .(
				.(VertexFormat.Float4, 0, 5),   // WorldRow0
				.(VertexFormat.Float4, 16, 6),  // WorldRow1
				.(VertexFormat.Float4, 32, 7),  // WorldRow2
				.(VertexFormat.Float4, 48, 8)   // WorldRow3
			);
			VertexBufferLayout[2] vertexBuffers = .(
				.(48, meshAttrs, .Vertex),
				.(64, instanceAttrs, .Instance)
			);

			if (pipelineCache.GetPipelineForMaterial(
				material,
				vertexBuffers,
				Renderer.SharedLayouts.SceneLayout,
				materialLayout,
				.RGBA16Float,
				Renderer.DepthFormat,
				1,
				variantFlags,
				.ReadOnly,
				.LessEqual,
				null, null,
				.RGBA8Unorm) case .Ok(let pipeline))  // LessEqual for forward pass after depth prepass; RGBA8Unorm GBuffer
			{
				return pipeline;
			}

			return null;
		}
		else
		{
			// Non-instanced: full mesh vertex layout
			VertexBufferLayout[1] vertexBuffers = .(
				VertexLayoutHelper.CreateBufferLayout(.Mesh)
			);

			if (pipelineCache.GetPipelineForMaterial(
				material,
				vertexBuffers,
				Renderer.SharedLayouts.SceneLayout,
				materialLayout,
				.RGBA16Float,
				Renderer.DepthFormat,
				1,
				variantFlags,
				.ReadOnly,
				.LessEqual,
				null, null,
				.RGBA8Unorm) case .Ok(let pipeline))  // LessEqual for forward pass after depth prepass; RGBA8Unorm GBuffer
			{
				return pipeline;
			}

			return null;
		}
	}

	private Result<void> CreateShadowPipeline()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Load depth shaders for shadow rendering
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("depth", .DepthTest | .DepthWrite);
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		// Create shadow bind group layout: light VP (b0, dynamic) + object transforms (b1, dynamic)
		// Both use dynamic offset: b0 selects cascade VP, b1 selects object transforms
		BindGroupLayoutEntry[2] shadowEntries = .(
			.() { Binding = 0, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true }, // Light ViewProjectionMatrix (per cascade)
			.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true } // Object transforms
		);

		BindGroupLayoutDesc shadowLayoutDesc = .()
		{
			Label = "Shadow BindGroup Layout",
			Entries = shadowEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(shadowLayoutDesc))
		{
		case .Ok(let layout): mShadowBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create shadow pipeline layout
		IBindGroupLayout[1] layouts = .(mShadowBindGroupLayout);
		PipelineLayoutDesc layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(layoutDesc))
		{
		case .Ok(let layout): mShadowPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Create per-frame shadow uniform buffers large enough for 4 cascades with alignment
		// Each cascade needs SceneUniforms aligned to 256 bytes
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		const uint64 AlignedSceneUniformSize = ((SceneUniforms.Size + 255) / 256) * 256; // 256-byte aligned
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc uniformDesc = .()
			{
				Label = "Shadow Scene Uniforms",
				Size = AlignedSceneUniformSize * 4, // 4 cascades
				Usage = .Uniform,
				Memory = .CpuToGpu // CPU-mappable
			};
			switch (Renderer.Device.CreateBuffer(uniformDesc))
			{
			case .Ok(let buf): mShadowUniformBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		// Initialize shadow uniforms
		mShadowUniforms = .Identity;
		mAlignedSceneUniformSize = AlignedSceneUniformSize;

		// Create per-frame shadow object buffers with Upload memory for CPU mapping
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc objDesc = .()
			{
				Label = "Shadow Object Uniforms",
				Size = AlignedObjectUniformSize * RenderConfig.MaxOpaqueObjectsPerFrame,
				Usage = .Uniform,
				Memory = .CpuToGpu // CPU-mappable
			};
			switch (Renderer.Device.CreateBuffer(objDesc))
			{
			case .Ok(let buf): mShadowObjectBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		// Vertex layout
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Shadow depth pipeline - depth only output
		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "Shadow Depth Pipeline",
			Layout = mShadowPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = default // No color targets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = .()
			{
				DepthTestEnabled = true,
				DepthWriteEnabled = true,
				DepthCompare = .Less,
				Format = .Depth32Float, // Match shadow map format
				DepthBias = 2,          // Hardware depth bias (supplemented by receiver-side normal offset)
				DepthBiasSlopeScale = 3.0f
			},
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(pipelineDesc))
		{
		case .Ok(let pipeline): mShadowDepthPipeline = pipeline;
		case .Err: return .Err;
		}

		// Create shadow bind group
		CreateShadowBindGroup();

		// Try to create instanced shadow pipeline
		CreateShadowInstancedPipeline();

		return .Ok;
	}

	private void CreateShadowInstancedPipeline()
	{
		if (Renderer.ShaderSystem == null)
			return;

		// Load depth shader with INSTANCED variant
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("depth", .DepthTest | .DepthWrite | .Instanced);
		if (shaderResult case .Err)
			return;

		let (vertShader, fragShader) = shaderResult.Value;

		// Shadow instanced bind group: only cascade VP (dynamic), no per-object transforms
		BindGroupLayoutEntry[1] entries = .(
			.() { Binding = 0, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true }
		);

		BindGroupLayoutDesc layoutDesc = .()
		{
			Label = "Shadow Instanced BindGroup Layout",
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroupLayout(layoutDesc) case .Ok(let bgLayout))
			mShadowInstancedBindGroupLayout = bgLayout;
		else
			return;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mShadowInstancedBindGroupLayout);
		PipelineLayoutDesc plDesc = .(layouts);
		if (Renderer.Device.CreatePipelineLayout(plDesc) case .Ok(let plLayout))
			mShadowInstancedPipelineLayout = plLayout;
		else
			return;

		// Vertex layout: mesh + instance data
		Sedulous.RHI.VertexAttribute[5] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),            // Position
			.(VertexFormat.Float3, 12, 1),           // Normal
			.(VertexFormat.Float2, 24, 2),           // UV
			.(VertexFormat.UByte4Normalized, 32, 3), // Color
			.(VertexFormat.Float3, 36, 4)            // Tangent
		);
		Sedulous.RHI.VertexAttribute[4] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 5),   // WorldRow0
			.(VertexFormat.Float4, 16, 6),  // WorldRow1
			.(VertexFormat.Float4, 32, 7),  // WorldRow2
			.(VertexFormat.Float4, 48, 8)   // WorldRow3
		);
		VertexBufferLayout[2] vertexBuffers = .(
			.(48, meshAttrs, .Vertex),
			.(64, instanceAttrs, .Instance)
		);

		// Shadow instanced pipeline - same depth format as shadow map
		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "Shadow Instanced Pipeline",
			Layout = mShadowInstancedPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = default
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = .()
			{
				DepthTestEnabled = true,
				DepthWriteEnabled = true,
				DepthCompare = .Less,
				Format = .Depth32Float,
				DepthBias = 2,
				DepthBiasSlopeScale = 3.0f
			},
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (Renderer.Device.CreateRenderPipeline(pipelineDesc) case .Ok(let pipeline))
		{
			mShadowInstancedPipeline = pipeline;

			// Initialize shadow instance buffer manager
			mShadowInstanceBufferManager = new InstanceBufferManager();
			if (mShadowInstanceBufferManager.Initialize(Renderer.Device) case .Ok)
			{
				mShadowInstancingEnabled = true;
				CreateShadowInstancedBindGroups();
			}
		}
	}

	private void CreateShadowInstancedBindGroups()
	{
		if (mShadowInstancedBindGroupLayout == null)
			return;

		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mShadowInstancedBindGroups[i] != null)
				continue;

			let shadowUniformBuffer = mShadowUniformBuffers[i];
			if (shadowUniformBuffer == null)
				continue;

			BindGroupEntry[1] entries = .(
				BindGroupEntry.Buffer(/*0,*/shadowUniformBuffer, 0, mAlignedSceneUniformSize)
			);

			BindGroupDesc bgDesc = .()
			{
				Label = "Shadow Instanced BindGroup",
				Layout = mShadowInstancedBindGroupLayout,
				Entries = entries
			};

			if (Renderer.Device.CreateBindGroup(bgDesc) case .Ok(let bg))
				mShadowInstancedBindGroups[i] = bg;
		}
	}

	protected override void OnShutdown()
	{
		let device = Renderer.Device;

		// Clean up per-frame, per-view bind groups
		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mSceneBindGroups[i] != null)
				device.DestroyBindGroup(ref mSceneBindGroups[i]);
		}

		// Clean up per-frame resources (not per-view)
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mObjectUniformBuffers[i] != null)
				device.DestroyBuffer(ref mObjectUniformBuffers[i]);

			if (mShadowBindGroups[i] != null)
				device.DestroyBindGroup(ref mShadowBindGroups[i]);

			if (mShadowUniformBuffers[i] != null)
				device.DestroyBuffer(ref mShadowUniformBuffers[i]);

			if (mShadowObjectBuffers[i] != null)
				device.DestroyBuffer(ref mShadowObjectBuffers[i]);

			if (mShadowInstancedBindGroups[i] != null)
				device.DestroyBindGroup(ref mShadowInstancedBindGroups[i]);
		}

		// Lighting system disposed by RenderSystem

		// Shadow renderer disposed by RenderSystem

		// Probe system disposed by RenderSystem

		// Destroy RHI resources
		// Scene bind group layout owned by SharedBindGroupLayouts
		device.DestroyRenderPipeline(ref mShadowDepthPipeline);
		device.DestroyPipelineLayout(ref mShadowPipelineLayout);
		device.DestroyBindGroupLayout(ref mShadowBindGroupLayout);
		device.DestroyRenderPipeline(ref mShadowInstancedPipeline);
		device.DestroyPipelineLayout(ref mShadowInstancedPipelineLayout);
		device.DestroyBindGroupLayout(ref mShadowInstancedBindGroupLayout);
	}

	/// Prepares shared frame data: lighting, shadows, object uniforms.
	/// Called once per frame before per-view AddPasses calls.
	public override void PrepareFrame(Span<RenderView> views, RenderWorld world, int32 frameIndex)
	{
		using (SProfiler.Begin("ForwardOpaque.PrepareFrame"))
		{
			let depthFeature = Renderer.GetFeature<DepthPrepassFeature>();
			if (depthFeature == null)
				return;

			// Update lighting shared data from main view (cluster grid, light data, uniforms)
			using (SProfiler.Begin("UpdateLighting"))
				UpdateLighting(world, Renderer.Visibility, Renderer.ViewContext, frameIndex);

			// Cull lights per-view (each view needs its own cluster assignments
			// because light positions in view space differ per camera)
			using (SProfiler.Begin("CullLightsPerView"))
			{
				for (int32 i = 0; i < (int32)views.Length; i++)
					Lighting.ClusterGrid.CullLightsCPU(world, Renderer.Visibility, views[i].ViewMatrix, frameIndex, i);
			}

			// Upload object uniforms (shared across views)
			using (SProfiler.Begin("PrepareObjectUniforms"))
				PrepareObjectUniforms(depthFeature, frameIndex);

			// Update reflection probe uniforms (bakes dirty probes + uploads data)
			if (Renderer.ProbeSystem != null)
				Renderer.ProbeSystem.UpdateProbeUniforms(world, frameIndex);
		}
	}

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderWorld world)
	{
		using (SProfiler.Begin("ForwardOpaque.AddPasses"))
		{
			// Get depth prepass feature for visibility data
			let depthFeature = Renderer.GetFeature<DepthPrepassFeature>();
			if (depthFeature == null)
				return;

			// Get existing depth buffer
			let depthHandle = graph.GetResource("SceneDepth");
			if (!depthHandle.IsValid)
				return;

			// Create HDR color buffer
			let colorDesc = RGTextureDesc(.RGBA16Float, view.Width, view.Height) { Usage = .RenderTarget | .Sampled };
			let colorHandle = graph.CreateTransient("SceneColor", colorDesc);

			// Create normal-roughness GBuffer (octahedral normal RG, roughness B, metallic A)
			let gbufferDesc = RGTextureDesc(.RGBA8Unorm, view.Width, view.Height) { Usage = .RenderTarget | .Sampled };
			let gbufferHandle = graph.CreateTransient("SceneNormalRoughness", gbufferDesc);

			let frameIndex = view.FrameIndex;
			let bgIndex = view.GetBindGroupIndex();

			// Single-view path: do lighting/uniforms here if PrepareFrame wasn't called
			if (view.ViewCount <= 1)
			{
				using (SProfiler.Begin("UpdateLighting"))
					UpdateLighting(world, Renderer.Visibility, view, frameIndex);

				// Cull lights for this single view
				Lighting.ClusterGrid.CullLightsCPU(world, Renderer.Visibility, view.ViewMatrix, frameIndex);

				using (SProfiler.Begin("PrepareObjectUniforms"))
					PrepareObjectUniforms(depthFeature, frameIndex);

				// Update reflection probes
				if (Renderer.ProbeSystem != null)
					Renderer.ProbeSystem.UpdateProbeUniforms(world, frameIndex);
			}

			// Shadow passes: only for first view (shadow maps shared across views)
			RGHandle shadowMapHandle = .Invalid;
			if (view.ViewIndex == 0)
			{
				using (SProfiler.Begin("AddShadowPasses"))
					AddShadowPasses(graph, world, Renderer.Visibility, view, frameIndex, out shadowMapHandle);
			}
			else if (Renderer.ShadowRenderer.ShadowPassesActive)
			{
				// Import already-rendered shadow map for barrier tracking
				let cascadedShadowMap = ShadowRenderer.CascadedShadows?.ShadowMapArray;
				let cascadedShadowMapView = ShadowRenderer.CascadedShadows?.ShadowMapArrayView;
				if (cascadedShadowMap != null && cascadedShadowMapView != null)
					shadowMapHandle = graph.ImportTarget("ShadowMap", cascadedShadowMap, cascadedShadowMapView);
			}

			// Create/update scene bind group for current frame+view
			CreateSceneBindGroup(frameIndex, bgIndex);

			// Add forward opaque pass
			let shadowMapRef = shadowMapHandle;
			graph.AddRenderPass("ForwardOpaque", scope (builder) => {
				builder.SetColorTarget(0, colorHandle, .Clear, .Store, ClearColor(0.0f, 0.0f, 0.0f, 1.0f));
				builder.SetColorTarget(1, gbufferHandle, .Clear, .Store, ClearColor(0.5f, 0.5f, 0.0f, 0.0f));
				builder.ReadDepth(depthHandle);
				builder.NeverCull();

				// Add shadow map as read dependency if available
				if (shadowMapRef.IsValid)
					builder.ReadTexture(shadowMapRef);

				builder.SetExecute(new /*[&, =frameIndex, =bgIndex]*/(encoder) => {
					ExecuteForwardPass(encoder, world, view, depthFeature, frameIndex, bgIndex);
				});
			});
		}
	}

	private void PrepareObjectUniforms(DepthPrepassFeature depthFeature, int32 frameIndex)
	{
		// Upload object transforms to the uniform buffer BEFORE the render pass
		// Use Map/Unmap to avoid command buffer creation
		let skinnedCommands = Renderer.Batcher.SkinnedCommands;

		// Use the current frame's buffer
		let buffer = mObjectUniformBuffers[frameIndex];
		if (buffer == null)
			return;

		if (let bufferPtr = buffer.Map())
		{
			int32 objectIndex = 0;

			// Static meshes - SKIP if instancing is active (instance buffer has transforms)
			if (!Renderer.GetFeature<DepthPrepassFeature>().InstancingActive)
			{
				let commands = Renderer.Batcher.DrawCommands;
				for (let batch in Renderer.Batcher.OpaqueBatches)
				{
					if (batch.CommandCount == 0)
						continue;

					for (int32 i = 0; i < batch.CommandCount; i++)
					{
						if (objectIndex >= RenderConfig.MaxOpaqueObjectsPerFrame)
							break;

						let cmd = commands[batch.CommandStart + i];

						// Build object uniforms from draw command
						ObjectUniforms objUniforms = .()
						{
							WorldMatrix = cmd.WorldMatrix,
							PrevWorldMatrix = cmd.PrevWorldMatrix,

							ObjectID = (uint32)objectIndex,
							MaterialID = 0,
							_Padding = .(0, 0)
						};

						// Copy to mapped buffer at aligned offset
						let bufferOffset = (uint64)objectIndex * AlignedObjectUniformSize;
						Runtime.Assert(bufferOffset + ObjectUniforms.Size <= buffer.Size, scope $"Object uniform write (offset {bufferOffset} + size {ObjectUniforms.Size}) exceeds buffer size ({buffer.Size})");
						Internal.MemCpy((uint8*)bufferPtr + bufferOffset, &objUniforms, ObjectUniforms.Size);

						objectIndex++;
					}
				}
			}

			// Skinned meshes - always need uniforms (not instanced)
			for (let batch in Renderer.Batcher.SkinnedBatches)
			{
				if (batch.CommandCount == 0)
					continue;

				for (int32 i = 0; i < batch.CommandCount; i++)
				{
					if (objectIndex >= RenderConfig.MaxOpaqueObjectsPerFrame)
						break;

					let cmd = skinnedCommands[batch.CommandStart + i];

					// Build object uniforms from skinned draw command
					ObjectUniforms objUniforms = .()
					{
						WorldMatrix = cmd.WorldMatrix,
						PrevWorldMatrix = cmd.PrevWorldMatrix,

						ObjectID = (uint32)objectIndex,
						MaterialID = 0,
						_Padding = .(0, 0)
					};

					// Copy to mapped buffer at aligned offset
					let bufferOffset = (uint64)objectIndex * AlignedObjectUniformSize;
					Runtime.Assert(bufferOffset + ObjectUniforms.Size <= buffer.Size, scope $"Object uniform write (offset {bufferOffset} + size {ObjectUniforms.Size}) exceeds buffer size ({buffer.Size})");
					Internal.MemCpy((uint8*)bufferPtr + bufferOffset, &objUniforms, ObjectUniforms.Size);

					objectIndex++;
				}
			}

			buffer.Unmap();
		}
	}

	private void UpdateLighting(RenderWorld world, VisibilityResolver visibility, ViewContext view, int32 frameIndex)
	{
		// Update cluster grid
		let inverseProj = Matrix.Invert(view.ProjectionMatrix);
		Lighting.ClusterGrid.Update(view.Width, view.Height, view.NearPlane, view.FarPlane, inverseProj);

		// Calculate cluster scale/bias for shader
		let config = Lighting.ClusterGrid.Config;
		let clusterScaleX = (float)config.ClustersX / (float)view.Width;
		let clusterScaleY = (float)config.ClustersY / (float)view.Height;
		let logDepthScale = (float)config.ClustersZ / Math.Log(view.FarPlane / view.NearPlane);
		let logDepthBias = -(float)config.ClustersZ * Math.Log(view.NearPlane) / Math.Log(view.FarPlane / view.NearPlane);

		// Update light buffer cluster info
		Lighting.LightBuffer.SetClusterInfo(
			config.ClustersX, config.ClustersY, config.ClustersZ,
			.(clusterScaleX, clusterScaleY),
			.(logDepthScale, logDepthBias)
		);

		// Apply environment settings from RenderWorld
		Lighting.LightBuffer.AmbientColor = world.AmbientColor;
		Lighting.LightBuffer.AmbientIntensity = world.AmbientIntensity;
		Lighting.LightBuffer.Exposure = world.Exposure;

		// Update light buffer from visibility
		Lighting.LightBuffer.Update(world, visibility);
		Lighting.LightBuffer.UploadLightData(frameIndex);
		Lighting.LightBuffer.UploadUniforms(frameIndex);

		// Note: CullLightsCPU is called separately per-view (in PrepareFrame or AddPasses)
		// because cluster light assignments depend on each view's camera matrix.
	}

	private void AddShadowPasses(RenderGraph graph, RenderWorld world, VisibilityResolver visibility, ViewContext view, int32 frameIndex, out RGHandle outShadowMapHandle)
	{
		outShadowMapHandle = .Invalid;
		Renderer.ShadowRenderer.ShadowPassesActive = false;

		if (!ShadowRenderer.EnableShadows)
			return;

		if (!ShadowRenderer.IsInitialized)
			return;

		// Create camera proxy from RenderView for CSM calculations
		let target = view.CameraPosition + view.CameraForward;
		var camera = CameraProxy.CreatePerspective(
			view.CameraPosition,
			target,
			view.CameraUp,
			view.FieldOfView,
			view.AspectRatio,
			view.NearPlane,
			view.FarPlane
		);

		// Update shadow renderer
		ShadowRenderer.Update(world, visibility, &camera);

		// Get shadow passes
		List<ShadowPass> shadowPasses = scope .();
		ShadowRenderer.GetShadowPasses(shadowPasses);

		if (shadowPasses.Count == 0)
			return;

		Renderer.ShadowRenderer.ShadowPassesActive = true;

		// Upload all shadow uniforms BEFORE adding passes (avoid WriteBuffer during render pass)
		PrepareShadowUniforms(world, visibility, shadowPasses, frameIndex);

		// Build shadow batcher and upload instance data for instanced shadow rendering
		if (mShadowInstancingEnabled && world.InstancingEnabled)
		{
			mShadowBatcher.BuildShadowCasters(world, visibility);
			if (mShadowInstanceBufferManager != null && mShadowBatcher.OpaqueInstanceGroups.Length > 0)
				mShadowInstanceBufferManager.UploadInstanceData(frameIndex, mShadowBatcher);
		}

		// Import the shadow map array once with a common name for barrier tracking
		// This handle will be used by the forward pass to trigger automatic barrier
		let cascadedShadowMap = ShadowRenderer.CascadedShadows?.ShadowMapArray;
		let cascadedShadowMapView = ShadowRenderer.CascadedShadows?.ShadowMapArrayView;
		if (cascadedShadowMap != null && cascadedShadowMapView != null)
		{
			outShadowMapHandle = graph.ImportTarget("ShadowMap", cascadedShadowMap, cascadedShadowMapView);
		}

		// Add each shadow pass
		for (let shadowPass in shadowPasses)
		{
			// Currently only cascade passes are fully supported
			// Atlas/point light passes need additional uniform buffer handling
			if (shadowPass.Type != .Cascade)
			{
				// TODO: Implement atlas/point light shadow pass support
				// These require separate VP matrix handling since they don't use cascade slots
				continue;
			}

			// Validate cascade index is within bounds
			if (shadowPass.CascadeIndex >= 4)
			{
				Console.WriteLine("[Shadow] ERROR: Cascade index {} out of bounds (max 3)", shadowPass.CascadeIndex);
				continue;
			}

			String passName = scope $"Shadow_{shadowPass.Type}_{shadowPass.CascadeIndex}";

			// Get the actual texture based on pass type
			ITexture shadowTexture = ShadowRenderer.CascadedShadows?.ShadowMapArray;

			if (shadowTexture == null || shadowPass.RenderTarget == null)
				continue;

			// Import shadow render target with actual texture
			let shadowTarget = graph.ImportTarget(passName, shadowTexture, shadowPass.RenderTarget);

			// Copy shadow pass for closure - use CascadeIndex from the pass itself
			ShadowPass passCopy = shadowPass;
			graph.AddRenderPass(passName, scope (builder) => {
				builder.SetDepthTarget(shadowTarget, .Clear, .Store);
				builder.NeverCull();
				builder.SetExecute(new (encoder) => {
					ExecuteShadowPass(encoder, world, visibility, passCopy, frameIndex);
				});
			});
		}
	}

	// Store shadow passes for VP lookup during execution
	private List<ShadowPass> mCurrentShadowPasses = new .() ~ delete _;
	private int32 mShadowSkinnedMeshStartIndex = 0;

	private void PrepareShadowUniforms(RenderWorld world, VisibilityResolver visibility, List<ShadowPass> shadowPasses, int32 frameIndex)
	{
		// Store shadow passes for VP lookup during cascade rendering
		mCurrentShadowPasses.Clear();
		for (let pass in shadowPasses)
			mCurrentShadowPasses.Add(pass);

		// Use current frame's buffers
		let shadowUniformBuffer = mShadowUniformBuffers[frameIndex];
		let shadowObjectBuffer = mShadowObjectBuffers[frameIndex];

		if (shadowUniformBuffer == null || shadowObjectBuffer == null)
			return;

		// Map shadow uniform buffer and write cascade VPs directly (no command buffers needed)
		// Use the CascadeIndex from each pass to determine the correct buffer slot
		if (let uniformPtr = shadowUniformBuffer.Map())
		{
			for (let pass in shadowPasses)
			{
				// Only cascade passes use this uniform buffer
				if (pass.Type != .Cascade)
					continue;

				// Validate cascade index is within bounds (0-3)
				let cascadeIdx = (int32)pass.CascadeIndex;
				if (cascadeIdx < 0 || cascadeIdx >= 4)
				{
					Console.WriteLine("[Shadow] ERROR: Invalid cascade index {} in PrepareShadowUniforms", cascadeIdx);
					continue;
				}

				mShadowUniforms.ViewProjectionMatrix = pass.ViewProjection;
				let offset = (uint64)cascadeIdx * mAlignedSceneUniformSize;

				// Bounds check against actual buffer size
				Runtime.Assert(offset + SceneUniforms.Size <= shadowUniformBuffer.Size, scope $"Shadow uniform write (offset {offset} + size {SceneUniforms.Size}) exceeds buffer size ({shadowUniformBuffer.Size})");
				Internal.MemCpy((uint8*)uniformPtr + offset, &mShadowUniforms, SceneUniforms.Size);
			}
			shadowUniformBuffer.Unmap();
		}

		// Map shadow object buffer and write transforms directly
		if (let objectPtr = shadowObjectBuffer.Map())
		{
			int32 objectIndex = 0;

			// Static meshes
			for (let visibleMesh in visibility.VisibleMeshes)
			{
				if (objectIndex >= RenderConfig.MaxOpaqueObjectsPerFrame)
					break;

				if (let proxy = world.GetMesh(visibleMesh.Handle))
				{
					if (!proxy.CastsShadows)
						continue;

					ObjectUniforms objUniforms = .()
					{
						WorldMatrix = proxy.WorldMatrix,
						PrevWorldMatrix = proxy.PrevWorldMatrix,

						ObjectID = (uint32)objectIndex,
						MaterialID = 0,
						_Padding = default
					};

					let offset = (uint64)objectIndex * AlignedObjectUniformSize;
					// Bounds check against actual buffer size
					Runtime.Assert(offset + ObjectUniforms.Size <= shadowObjectBuffer.Size, scope $"Shadow object uniform write (offset {offset} + size {ObjectUniforms.Size}) exceeds buffer size ({shadowObjectBuffer.Size})");
					Internal.MemCpy((uint8*)objectPtr + offset, &objUniforms, ObjectUniforms.Size);

					objectIndex++;
				}
			}

			// Store where skinned meshes start for ExecuteShadowPass
			mShadowSkinnedMeshStartIndex = objectIndex;

			// Skinned meshes
			for (let visibleMesh in visibility.VisibleSkinnedMeshes)
			{
				if (objectIndex >= RenderConfig.MaxOpaqueObjectsPerFrame)
					break;

				if (let proxy = world.GetSkinnedMesh(visibleMesh.Handle))
				{
					if (!proxy.CastsShadows)
						continue;

					ObjectUniforms objUniforms = .()
					{
						WorldMatrix = proxy.WorldMatrix,
						PrevWorldMatrix = proxy.PrevWorldMatrix,

						ObjectID = (uint32)objectIndex,
						MaterialID = 0,
						_Padding = default
					};

					let offset = (uint64)objectIndex * AlignedObjectUniformSize;
					Runtime.Assert(offset + ObjectUniforms.Size <= shadowObjectBuffer.Size, scope $"Shadow skinned object uniform write (offset {offset} + size {ObjectUniforms.Size}) exceeds buffer size ({shadowObjectBuffer.Size})");
					Internal.MemCpy((uint8*)objectPtr + offset, &objUniforms, ObjectUniforms.Size);

					objectIndex++;
				}
			}

			shadowObjectBuffer.Unmap();
		}
	}

	// Scene bind group layout creation moved to SharedBindGroupLayouts

	private Result<void> CreateObjectUniformBuffer()
	{
		// Create per-frame object uniform buffers large enough for RenderConfig.MaxOpaqueObjectsPerFrame with alignment
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			var bufferDesc = BufferDesc()
			{
				Label = "ForwardOpaque Object Uniforms",
				Size = AlignedObjectUniformSize * RenderConfig.MaxOpaqueObjectsPerFrame,
				Usage = .Uniform,
				Memory = .CpuToGpu // CPU-mappable
			};

			switch (Renderer.Device.CreateBuffer(bufferDesc))
			{
			case .Ok(let buffer): mObjectUniformBuffers[i] = buffer;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private void CreateSceneBindGroup(int32 frameIndex, int32 bgIndex)
	{

		// Use shadow map only when shadow passes actually ran this frame
		let shadowsEnabled = Renderer.ShadowRenderer.ShadowPassesActive;

		// Check IBL state (generation counter detects view replacements, not just null transitions)
		let skyFeature = Renderer.GetFeature<SkyFeature>();
		let iblGeneration = skyFeature?.IBLGeneration ?? 0;

		// Check probe state
		let probeGeneration = Renderer.ProbeSystem?.Generation ?? 0;

		// Check if bind group exists and state hasn't changed
		if (mSceneBindGroups[bgIndex] != null)
		{
			if (mSceneBindGroupShadowState[bgIndex] == shadowsEnabled &&
				mSceneBindGroupIBLGeneration[bgIndex] == iblGeneration &&
				mSceneBindGroupProbeGeneration[bgIndex] == probeGeneration)
				return;

			Renderer.Device.DestroyBindGroup(ref mSceneBindGroups[bgIndex]);
		}

		// Create via shared helper (uses shared layout, RenderSystem subsystems)
		let bg = Renderer.SharedLayouts.CreateSceneBindGroup(frameIndex, mObjectUniformBuffers[frameIndex], Renderer.ProbeSystem);
		if (bg != null)
		{
			mSceneBindGroups[bgIndex] = bg;
			mSceneBindGroupShadowState[bgIndex] = shadowsEnabled;
			mSceneBindGroupIBLGeneration[bgIndex] = iblGeneration;
			mSceneBindGroupProbeGeneration[bgIndex] = probeGeneration;
		}
	}

	private void ExecuteForwardPass(IRenderPassEncoder encoder, RenderWorld world, ViewContext view, DepthPrepassFeature depthFeature, int32 frameIndex, int32 bgIndex)
	{
		using (SProfiler.Begin("ForwardOpaque.Execute"))
		{
			// Set viewport — render to per-view SceneColor texture at (0,0), not swapchain offset
			encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
			encoder.SetScissor(0, 0, view.Width, view.Height);

			// Track object index for uniform buffer dynamic offsets
			var objectIndex = (int32)0;

			// Track current bound material to minimize rebinds
			MaterialInstance currentMaterial = null;

			// Use instanced path if available and has instance groups
			let batcher = Renderer.Batcher;
			if (mInstancingEnabled && Renderer.GetFeature<DepthPrepassFeature>().InstancingActive && batcher.OpaqueInstanceGroups.Length > 0)
			{
				using (SProfiler.Begin("InstancedDraw"))
					ExecuteInstancedForwardPass(encoder, world, depthFeature, frameIndex, bgIndex, ref currentMaterial);
				// Instanced path doesn't use uniform buffer for static meshes,
				// skinned uniforms start at index 0 (we skipped static mesh uploads)
				objectIndex = 0;
			}
			else
			{
				// Fall back to non-instanced path
				using (SProfiler.Begin("NonInstancedDraw"))
					ExecuteNonInstancedForwardPass(encoder, world, depthFeature, frameIndex, bgIndex, ref objectIndex, ref currentMaterial);
			}

			// Render skinned meshes (always non-instanced)
			using (SProfiler.Begin("SkinnedMeshes"))
				RenderSkinnedMeshes(encoder, world, view, depthFeature, frameIndex, bgIndex, ref objectIndex, ref currentMaterial);
		}
	}

	private void ExecuteInstancedForwardPass(IRenderPassEncoder encoder, RenderWorld world, DepthPrepassFeature depthFeature, int32 frameIndex, int32 bgIndex, ref MaterialInstance currentMaterial)
	{
		// Get shadow state for pipeline selection
		let shadowsEnabled = Renderer.ShadowRenderer.ShadowPassesActive;

		// Track current pipeline to minimize state changes
		IRenderPipeline currentPipeline = null;

		// Get instance buffer from depth feature
		let instanceBuffer = Renderer.GetFeature<DepthPrepassFeature>().GetInstanceBuffer(frameIndex);
		if (instanceBuffer == null)
			return;

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Get batcher data
		let batcher = Renderer.Batcher;
		let commands = batcher.DrawCommands;

		// Get scene bind group for later binding (after pipeline is set)
		let sceneBindGroup = mSceneBindGroups[bgIndex];

		// Render opaque instance groups
		for (let group in batcher.OpaqueInstanceGroups)
		{
			if (group.InstanceCount == 0)
				continue;

			// Get mesh data
			if (let mesh = Renderer.ResourceManager.GetMesh(group.GPUMesh))
			{
				// Bind vertex buffers: slot 0 = mesh, slot 1 = instance data
				encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
				encoder.SetVertexBuffer(1, instanceBuffer, (uint64)(group.InstanceStart * (int32)InstanceData.Size));

				// Get the mesh proxy for per-submesh material lookup
				MeshProxy* proxy = null;
				if (group.CommandStart < commands.Length)
				{
					let cmd = commands[group.CommandStart];
					if (cmd.MeshHandle.IsValid)
						proxy = world.GetMesh(cmd.MeshHandle);
				}

				if (mesh.IndexBuffer != null && mesh.SubMeshes != null && mesh.SubMeshes.Count > 1)
				{
					// Per-submesh rendering: each submesh may have a different material
					encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

					// Resolve LOD submesh range
					uint32 subStart = 0;
					uint32 subCount = (uint32)mesh.SubMeshes.Count;
					if (mesh.LODLevels != null && group.LODLevel < mesh.LODCount)
					{
						subStart = mesh.LODLevels[group.LODLevel].SubMeshStart;
						subCount = mesh.LODLevels[group.LODLevel].SubMeshCount;
					}

					for (uint32 si = subStart; si < subStart + subCount && si < (uint32)mesh.SubMeshes.Count; si++)
					{
						let sub = mesh.SubMeshes[si];

						// Resolve material for this submesh's material slot
						let matSlot = (int32)sub.MaterialSlot;
						MaterialInstance material = null;
						if (proxy != null && matSlot >= 0 && matSlot < proxy.MaterialCount)
							material = proxy.Materials[matSlot];
						if (material == null && proxy != null && proxy.MaterialCount > 0)
							material = proxy.Materials[0];
						if (material == null)
							material = defaultMaterialInstance;

						// Get pipeline for this material
						let pipeline = GetPipelineForMaterial(material, shadowsEnabled, true);
						if (pipeline == null)
							continue;

						if (pipeline != currentPipeline)
						{
							encoder.SetPipeline(pipeline);
							currentPipeline = pipeline;

							if (sceneBindGroup != null)
							{
								uint32[1] dynamicOffsets = .(0);
								encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
							}
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

						encoder.DrawIndexed(sub.IndexCount, (uint32)group.InstanceCount, sub.IndexStart, sub.BaseVertex, 0);

						Renderer.Stats.DrawCalls++;
						Renderer.Stats.InstanceCount += group.InstanceCount;
						Renderer.Stats.TriangleCount += (int32)(sub.IndexCount / 3) * group.InstanceCount;
					}
				}
				else
				{
					// Single submesh or no submeshes: draw entire mesh with group material
					MaterialInstance material = group.Material ?? defaultMaterialInstance;

					let pipeline = GetPipelineForMaterial(material, shadowsEnabled, true);
					if (pipeline == null)
						continue;

					if (pipeline != currentPipeline)
					{
						encoder.SetPipeline(pipeline);
						currentPipeline = pipeline;

						if (sceneBindGroup != null)
						{
							uint32[1] dynamicOffsets = .(0);
							encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
						}
					}

					if (material != currentMaterial && material != null && materialSystem != null)
					{
						if (materialSystem.PrepareInstance(material) case .Ok(let bindGroup))
						{
							encoder.SetBindGroup(1, bindGroup, default);
							currentMaterial = material;
						}
					}

					if (mesh.IndexBuffer != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
						encoder.DrawIndexed(mesh.IndexCount, (uint32)group.InstanceCount, 0, 0, 0);
					}
					else
					{
						encoder.Draw(mesh.VertexCount, (uint32)group.InstanceCount, 0, 0);
					}

					Renderer.Stats.DrawCalls++;
					Renderer.Stats.InstanceCount += group.InstanceCount;
					Renderer.Stats.TriangleCount += (int32)(mesh.IndexCount / 3) * group.InstanceCount;
				}
			}
		}
	}

	private void ExecuteNonInstancedForwardPass(IRenderPassEncoder encoder, RenderWorld world, DepthPrepassFeature depthFeature, int32 frameIndex, int32 bgIndex, ref int32 objectIndex, ref MaterialInstance currentMaterial)
	{
		// Get shadow state for pipeline selection
		let shadowsEnabled = Renderer.ShadowRenderer.ShadowPassesActive;

		// Track current pipeline to minimize state changes
		IRenderPipeline currentPipeline = null;

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Get draw commands from batcher (uniforms already uploaded in PrepareObjectUniforms)
		let batcher = Renderer.Batcher;
		let commands = batcher.DrawCommands;

		// Render with dynamic offsets
		for (let batch in batcher.OpaqueBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			// Draw each command in this batch
			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= RenderConfig.MaxOpaqueObjectsPerFrame)
					break;

				let cmd = commands[batch.CommandStart + i];

				// Get mesh proxy to access materials
				MeshProxy* proxy = null;
				if (cmd.MeshHandle.IsValid)
					proxy = world.GetMesh(cmd.MeshHandle);

				// Bind scene bind group with dynamic offset for this object's transforms
				let sceneBindGroup = mSceneBindGroups[bgIndex];

				// Get mesh data and draw per-submesh
				if (let mesh = Renderer.ResourceManager.GetMesh(cmd.GPUMesh))
				{
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);

					if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

						// Resolve LOD submesh range
						uint32 subStart = 0;
						uint32 subCount = (uint32)mesh.SubMeshes.Count;
						if (mesh.LODLevels != null && cmd.LODLevel < mesh.LODCount)
						{
							subStart = mesh.LODLevels[cmd.LODLevel].SubMeshStart;
							subCount = mesh.LODLevels[cmd.LODLevel].SubMeshCount;
						}

						for (uint32 si = subStart; si < subStart + subCount && si < (uint32)mesh.SubMeshes.Count; si++)
						{
							let sub = mesh.SubMeshes[si];

							// Resolve material for this submesh's material slot
							let matSlot = (int32)sub.MaterialSlot;
							MaterialInstance material = null;
							if (proxy != null && matSlot >= 0 && matSlot < proxy.MaterialCount)
								material = proxy.Materials[matSlot];
							if (material == null && matSlot >= 0 && proxy != null && proxy.MaterialCount > 0)
								material = proxy.Materials[0];
							if (material == null)
								material = defaultMaterialInstance;

							// Get pipeline for this material from cache
							let pipeline = GetPipelineForMaterial(material, shadowsEnabled, false);
							if (pipeline == null)
								continue;

							if (pipeline != currentPipeline)
							{
								encoder.SetPipeline(pipeline);
								currentPipeline = pipeline;
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

							// Bind scene bind group with dynamic offset
							if (sceneBindGroup != null)
							{
								uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
								encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
							}

							encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);

							Renderer.Stats.DrawCalls++;
							Renderer.Stats.TriangleCount += (int32)(sub.IndexCount / 3);
						}
					}
					else if (mesh.IndexBuffer == null)
					{
						// Non-indexed mesh — use first material slot
						MaterialInstance material = null;
						if (proxy != null && proxy.MaterialCount > 0)
							material = proxy.Materials[0];
						if (material == null)
							material = defaultMaterialInstance;

						let pipeline = GetPipelineForMaterial(material, shadowsEnabled, false);
						if (pipeline != null)
						{
							if (pipeline != currentPipeline)
							{
								encoder.SetPipeline(pipeline);
								currentPipeline = pipeline;
							}

							if (material != currentMaterial && material != null && materialSystem != null)
							{
								if (materialSystem.PrepareInstance(material) case .Ok(let bindGroup))
								{
									encoder.SetBindGroup(1, bindGroup, default);
									currentMaterial = material;
								}
							}

							if (sceneBindGroup != null)
							{
								uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
								encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
							}

							encoder.Draw(mesh.VertexCount, 1, 0, 0);

							Renderer.Stats.DrawCalls++;
							Renderer.Stats.TriangleCount += (int32)(mesh.VertexCount / 3);
						}
					}
				}

				objectIndex++;
			}
		}
	}

	private void RenderSkinnedMeshes(IRenderPassEncoder encoder, RenderWorld world, ViewContext view, DepthPrepassFeature depthFeature, int32 frameIndex, int32 bgIndex, ref int32 objectIndex, ref MaterialInstance currentMaterial)
	{
		// Get skinning system to access skinned vertex buffers
		let skinningSystem = Renderer.SkinningSystem;
		if (skinningSystem == null)
			return;

		// Get shadow state for pipeline selection
		let shadowsEnabled = Renderer.ShadowRenderer.ShadowPassesActive;

		// Track current pipeline to minimize state changes
		IRenderPipeline currentPipeline = null;

		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Get skinned mesh commands from batcher
		let skinnedCommands = Renderer.Batcher.SkinnedCommands;

		// Render each skinned mesh batch
		for (let batch in Renderer.Batcher.SkinnedBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= RenderConfig.MaxOpaqueObjectsPerFrame)
					break;

				let cmd = skinnedCommands[batch.CommandStart + i];

				// Get skinned mesh proxy for materials
				SkinnedMeshProxy* proxy = null;
				if (cmd.MeshHandle.IsValid)
					proxy = world.GetSkinnedMesh(cmd.MeshHandle);

				if (proxy == null)
					continue;

				// Bind scene bind group with dynamic offset
				let sceneBindGroup = mSceneBindGroups[bgIndex];

				// Get the skinned vertex buffer from the skinning feature
				let skinnedVertexBuffer = skinningSystem.GetSkinnedVertexBuffer(world, cmd.MeshHandle);
				if (skinnedVertexBuffer != null)
				{
					// Bind the skinned vertex buffer (post-transform)
					encoder.SetVertexBuffer(0, skinnedVertexBuffer, 0);

					// Get mesh for index buffer and submeshes (indices don't change with skinning)
					if (let mesh = Renderer.ResourceManager.GetMesh(cmd.GPUMesh))
					{
						if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
						{
							encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

							for (let sub in mesh.SubMeshes)
							{
								// Resolve material for this submesh's material slot
								let matSlot = (int32)sub.MaterialSlot;
								MaterialInstance material = null;
								if (matSlot >= 0 && matSlot < proxy.MaterialCount)
									material = proxy.Materials[matSlot];
								if (material == null && matSlot >= 0 && proxy.MaterialCount > 0)
									material = proxy.Materials[0];
								if (material == null)
									material = defaultMaterialInstance;

								let pipeline = GetPipelineForMaterial(material, shadowsEnabled, false);
								if (pipeline == null)
									continue;

								if (pipeline != currentPipeline)
								{
									encoder.SetPipeline(pipeline);
									currentPipeline = pipeline;
								}

								if (material != currentMaterial && material != null && materialSystem != null)
								{
									if (materialSystem.PrepareInstance(material) case .Ok(let bindGroup))
									{
										encoder.SetBindGroup(1, bindGroup, default);
										currentMaterial = material;
									}
								}

								if (sceneBindGroup != null)
								{
									uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
									encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
								}

								encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);

								Renderer.Stats.DrawCalls++;
								Renderer.Stats.TriangleCount += (int32)(sub.IndexCount / 3);
							}
						}
						else if (mesh.IndexBuffer == null)
						{
							// Non-indexed skinned mesh — use first material slot
							MaterialInstance material = null;
							if (proxy.MaterialCount > 0)
								material = proxy.Materials[0];
							if (material == null)
								material = defaultMaterialInstance;

							let pipeline = GetPipelineForMaterial(material, shadowsEnabled, false);
							if (pipeline != null)
							{
								if (pipeline != currentPipeline)
								{
									encoder.SetPipeline(pipeline);
									currentPipeline = pipeline;
								}

								if (material != currentMaterial && material != null && materialSystem != null)
								{
									if (materialSystem.PrepareInstance(material) case .Ok(let bindGroup))
									{
										encoder.SetBindGroup(1, bindGroup, default);
										currentMaterial = material;
									}
								}

								if (sceneBindGroup != null)
								{
									uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
									encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
								}

								encoder.Draw(mesh.VertexCount, 1, 0, 0);

								Renderer.Stats.DrawCalls++;
								Renderer.Stats.TriangleCount += (int32)(mesh.VertexCount / 3);
							}
						}
					}
				}

				objectIndex++;
			}
		}
	}

	private void ExecuteShadowPass(IRenderPassEncoder encoder, RenderWorld world, VisibilityResolver visibility, ShadowPass shadowPass, int32 frameIndex)
	{
		// Skip if no pipeline or bind group
		let shadowBindGroup = mShadowBindGroups[frameIndex];
		if (mShadowDepthPipeline == null || shadowBindGroup == null)
			return;

		// Only cascade passes are currently supported
		if (shadowPass.Type != .Cascade)
			return;

		// Validate cascade index (must be 0-3)
		let cascadeIndex = (int32)shadowPass.CascadeIndex;
		if (cascadeIndex < 0 || cascadeIndex >= 4)
			return;

		// Set viewport for shadow map tile
		encoder.SetViewport(
			(float)shadowPass.Viewport.X,
			(float)shadowPass.Viewport.Y,
			(float)shadowPass.Viewport.Width,
			(float)shadowPass.Viewport.Height,
			0.0f, 1.0f
		);

		encoder.SetScissor(
			(int32)shadowPass.Viewport.X,
			(int32)shadowPass.Viewport.Y,
			(uint32)shadowPass.Viewport.Width,
			(uint32)shadowPass.Viewport.Height
		);

		// Calculate cascade VP offset (for dynamic uniform binding 0)
		// Uses CascadeIndex from the shadow pass to select the correct VP matrix slot
		uint32 cascadeVPOffset = (uint32)((int64)cascadeIndex * (int64)mAlignedSceneUniformSize);

		// Try instanced path for static meshes
		bool usedInstanced = false;
		if (mShadowInstancingEnabled && world.InstancingEnabled &&
			mShadowInstancedPipeline != null && mShadowInstancedBindGroups[frameIndex] != null &&
			mShadowBatcher.OpaqueInstanceGroups.Length > 0)
		{
			let instanceBuffer = mShadowInstanceBufferManager?.GetBuffer(frameIndex);
			if (instanceBuffer != null)
			{
				encoder.SetPipeline(mShadowInstancedPipeline);

				for (let group in mShadowBatcher.OpaqueInstanceGroups)
				{
					if (let mesh = Renderer.ResourceManager.GetMesh(group.GPUMesh))
					{
						if (mesh.IndexBuffer == null || mesh.SubMeshes == null)
							continue;

						// Bind cascade VP (single dynamic offset)
						uint32[1] dynamicOffsets = .(cascadeVPOffset);
						encoder.SetBindGroup(0, mShadowInstancedBindGroups[frameIndex], dynamicOffsets);

						encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
						encoder.SetVertexBuffer(1, instanceBuffer, (uint64)group.InstanceStart * 64);
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

						// Resolve LOD submesh range
						uint32 subStart = 0;
						uint32 subCount = (uint32)mesh.SubMeshes.Count;
						if (mesh.LODLevels != null && group.LODLevel < mesh.LODCount)
						{
							subStart = mesh.LODLevels[group.LODLevel].SubMeshStart;
							subCount = mesh.LODLevels[group.LODLevel].SubMeshCount;
						}
						for (uint32 si = subStart; si < subStart + subCount && si < (uint32)mesh.SubMeshes.Count; si++)
						{
							let sub = mesh.SubMeshes[si];
							encoder.DrawIndexed(sub.IndexCount, (uint32)group.InstanceCount, sub.IndexStart, sub.BaseVertex, 0);
							Renderer.Stats.ShadowDrawCalls++;
						}
					}
				}
				usedInstanced = true;
			}
		}

		// Non-instanced fallback for static meshes
		if (!usedInstanced)
		{
			encoder.SetPipeline(mShadowDepthPipeline);

			int32 objectIndex = 0;
			for (let visibleMesh in visibility.VisibleMeshes)
			{
				if (objectIndex >= RenderConfig.MaxOpaqueObjectsPerFrame)
					break;

				if (let proxy = world.GetMesh(visibleMesh.Handle))
				{
					if (!proxy.CastsShadows)
						continue;

					if (let mesh = Renderer.ResourceManager.GetMesh(proxy.MeshHandle))
					{
						uint32 objectOffset = (uint32)((int64)objectIndex * (int64)AlignedObjectUniformSize);
						uint32[2] dynamicOffsets = .(cascadeVPOffset, objectOffset);
						encoder.SetBindGroup(0, shadowBindGroup, dynamicOffsets);

						encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
						if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
						{
							encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

							// Resolve LOD submesh range
							uint32 subStart = 0;
							uint32 subCount = (uint32)mesh.SubMeshes.Count;
							if (mesh.LODLevels != null && visibleMesh.LODLevel < mesh.LODCount)
							{
								subStart = mesh.LODLevels[visibleMesh.LODLevel].SubMeshStart;
								subCount = mesh.LODLevels[visibleMesh.LODLevel].SubMeshCount;
							}
							for (uint32 si = subStart; si < subStart + subCount && si < (uint32)mesh.SubMeshes.Count; si++)
							{
								let sub = mesh.SubMeshes[si];
								encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);
								Renderer.Stats.ShadowDrawCalls++;
							}
						}
						else if (mesh.IndexBuffer == null)
						{
							encoder.Draw(mesh.VertexCount, 1, 0, 0);
							Renderer.Stats.ShadowDrawCalls++;
						}

						objectIndex++;
					}
				}
			}
		}

		// Skinned meshes - render using post-transform vertex buffers (always non-instanced)
		RenderSkinnedMeshesShadow(encoder, world, visibility, cascadeVPOffset, frameIndex);
	}

	private void RenderSkinnedMeshesShadow(IRenderPassEncoder encoder, RenderWorld world, VisibilityResolver visibility, uint32 cascadeVPOffset, int32 frameIndex)
	{
		// Get skinning system to access skinned vertex buffers
		let skinningSystem = Renderer.SkinningSystem;
		if (skinningSystem == null)
			return;

		let shadowBindGroup = mShadowBindGroups[frameIndex];
		if (shadowBindGroup == null)
			return;

		// Skinned meshes always use the non-instanced shadow pipeline.
		// Must set it explicitly because the instanced path may have left
		// mShadowInstancedPipeline active (different bind group layout).
		encoder.SetPipeline(mShadowDepthPipeline);

		int32 objectIndex = mShadowSkinnedMeshStartIndex;

		for (let visibleMesh in visibility.VisibleSkinnedMeshes)
		{
			if (objectIndex >= RenderConfig.MaxOpaqueObjectsPerFrame)
				break;

			if (let proxy = world.GetSkinnedMesh(visibleMesh.Handle))
			{
				if (!proxy.CastsShadows)
					continue;

				// Get the skinned vertex buffer
				let skinnedVertexBuffer = skinningSystem.GetSkinnedVertexBuffer(world, visibleMesh.Handle);
				if (skinnedVertexBuffer == null)
					continue;

				// Two dynamic offsets: [0] = cascade VP, [1] = object transforms
				uint32 objectOffset = (uint32)((int64)objectIndex * (int64)AlignedObjectUniformSize);
				uint32[2] dynamicOffsets = .(cascadeVPOffset, objectOffset);
				encoder.SetBindGroup(0, shadowBindGroup, dynamicOffsets);

				// Bind the skinned vertex buffer
				encoder.SetVertexBuffer(0, skinnedVertexBuffer, 0);

				// Get original mesh for index buffer
				if (let mesh = Renderer.ResourceManager.GetMesh(proxy.MeshHandle))
				{
					if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

						// Resolve LOD submesh range
						uint32 subStart = 0;
						uint32 subCount = (uint32)mesh.SubMeshes.Count;
						if (mesh.LODLevels != null && visibleMesh.LODLevel < mesh.LODCount)
						{
							subStart = mesh.LODLevels[visibleMesh.LODLevel].SubMeshStart;
							subCount = mesh.LODLevels[visibleMesh.LODLevel].SubMeshCount;
						}
						for (uint32 si = subStart; si < subStart + subCount && si < (uint32)mesh.SubMeshes.Count; si++)
						{
							let sub = mesh.SubMeshes[si];
							encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);
							Renderer.Stats.ShadowDrawCalls++;
						}
					}
					else if (mesh.IndexBuffer == null)
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
						Renderer.Stats.ShadowDrawCalls++;
					}
				}

				objectIndex++;
			}
		}
	}

	private void CreateShadowBindGroup()
	{
		if (mShadowBindGroupLayout == null)
			return;

		// Create per-frame shadow bind groups
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// Skip if already created
			if (mShadowBindGroups[i] != null)
				continue;

			let shadowUniformBuffer = mShadowUniformBuffers[i];
			let shadowObjectBuffer = mShadowObjectBuffers[i];

			if (shadowUniformBuffer == null || shadowObjectBuffer == null)
				continue;

			// Create bind group entries
			// For dynamic uniform buffers, size is the per-element size that dynamic offset selects
			BindGroupEntry[2] entries = .(
				BindGroupEntry.Buffer(/*0,*/shadowUniformBuffer, 0, mAlignedSceneUniformSize), // Per-cascade VP (dynamic)
				BindGroupEntry.Buffer(/*1,*/shadowObjectBuffer, 0, AlignedObjectUniformSize)   // Per-object transforms (dynamic)
			);

			BindGroupDesc bgDesc = .()
			{
				Label = "Shadow BindGroup",
				Layout = mShadowBindGroupLayout,
				Entries = entries
			};

			if (Renderer.Device.CreateBindGroup(bgDesc) case .Ok(let bg))
				mShadowBindGroups[i] = bg;
		}
	}
}
