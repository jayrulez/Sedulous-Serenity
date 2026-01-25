namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.Profiler;

/// Per-object uniform data matching forward.vert.hlsl ObjectUniforms (b1, space0).
[CRepr]
struct ObjectUniforms
{
	public Matrix WorldMatrix;
	public Matrix PrevWorldMatrix;
	public Matrix NormalMatrix;
	public uint32 ObjectID;
	public uint32 MaterialID;
	public float[2] _Padding;

	public const uint64 Size = 208; // 3 matrices (192) + 2 uint32 (8) + 2 float (8) = 208

	public static Self Identity => .()
	{
		WorldMatrix = .Identity,
		PrevWorldMatrix = .Identity,
		NormalMatrix = .Identity,
		ObjectID = 0,
		MaterialID = 0,
		_Padding = .(0, 0)
	};
}

/// Forward opaque render feature.
/// Renders all opaque geometry with full PBR shading and clustered lighting.
public class ForwardOpaqueFeature : RenderFeatureBase
{
	// Lighting system
	private LightingSystem mLighting ~ delete _;
	private ShadowRenderer mShadowRenderer ~ delete _;

	// Bind groups (per-frame for multi-buffering)
	private IBindGroupLayout mSceneBindGroupLayout ~ delete _;
	private IBindGroup[RenderConfig.FrameBufferCount] mSceneBindGroups;

	// Object uniform buffers (per-frame for multi-buffering)
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers;
	private const uint64 ObjectUniformAlignment = 256; // Vulkan minUniformBufferOffsetAlignment
	private const uint64 AlignedObjectUniformSize = ((ObjectUniforms.Size + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

	// Dynamic pipeline cache for custom materials
	private RenderPipelineCache mPipelineCache ~ delete _;

	// Shadow depth rendering (per-frame for multi-buffering)
	private IRenderPipeline mShadowDepthPipeline ~ delete _;
	private IPipelineLayout mShadowPipelineLayout ~ delete _;
	private IBindGroupLayout mShadowBindGroupLayout ~ delete _;
	private IBindGroup[RenderConfig.FrameBufferCount] mShadowBindGroups;
	private IBuffer[RenderConfig.FrameBufferCount] mShadowUniformBuffers; // Per-cascade SceneUniforms for light matrices
	private IBuffer[RenderConfig.FrameBufferCount] mShadowObjectBuffers;  // Per-object transforms for shadow pass
	private SceneUniforms mShadowUniforms; // CPU-side shadow uniforms
	private uint64 mAlignedSceneUniformSize; // Aligned size for dynamic uniform offset

	// Dummy shadow map array for when shadows are disabled
	private ITexture mDummyShadowMapArray ~ delete _;
	private ITextureView mDummyShadowMapArrayView ~ delete _;

	/// Feature name.
	public override StringView Name => "ForwardOpaque";

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => Renderer.RenderFrameContext?.FrameIndex ?? 0;

	/// Gets the lighting system.
	public LightingSystem Lighting => mLighting;

	/// Gets the shadow renderer.
	public ShadowRenderer ShadowRenderer => mShadowRenderer;

	/// Depends on depth prepass and GPU skinning.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("GPUSkinning");
		outDependencies.Add("DepthPrepass");
	}

	protected override Result<void> OnInitialize()
	{
		// Initialize lighting system
		mLighting = new LightingSystem();
		if (mLighting.Initialize(Renderer.Device, .Default, Renderer.ShaderSystem) case .Err)
			return .Err;

		// Initialize shadow renderer
		mShadowRenderer = new ShadowRenderer();
		if (mShadowRenderer.Initialize(Renderer.Device) case .Err)
			return .Err;

		// Create bind group layouts
		if (CreateBindGroupLayouts() case .Err)
			return .Err;

		// Create object uniform buffer
		if (CreateObjectUniformBuffer() case .Err)
			return .Err;

		// Create forward pipelines
		if (CreateForwardPipelines() case .Err)
			return .Err;

		// Try to create instanced forward pipelines
		if (CreateInstancedForwardPipelines() case .Ok)
			mInstancingEnabled = true;

		// Create dynamic pipeline cache for custom materials
		if (Renderer.ShaderSystem != null)
			mPipelineCache = new RenderPipelineCache(Renderer.Device, Renderer.ShaderSystem);

		// Create shadow depth pipeline
		if (CreateShadowPipeline() case .Err)
			return .Err;

		// Create dummy shadow map for when shadows are disabled
		if (CreateDummyShadowMap() case .Err)
			return .Err;

		return .Ok;
	}

	private IRenderPipeline mForwardPipeline ~ delete _;          // No shadows variant
	private IRenderPipeline mForwardShadowPipeline ~ delete _;    // With shadows variant
	private IRenderPipeline mForwardInstancedPipeline ~ delete _; // Instanced variant (no shadows)
	private IRenderPipeline mForwardInstancedShadowPipeline ~ delete _; // Instanced variant (with shadows)
	private IPipelineLayout mForwardPipelineLayout ~ delete _;

	// Instancing state (uses instance buffer from DepthPrepassFeature)
	private bool mInstancingEnabled = false;

	private Result<void> CreateForwardPipelines()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Get material bind group layout from MaterialSystem
		let materialLayout = Renderer.MaterialSystem?.DefaultMaterialLayout;
		if (materialLayout == null)
			return .Ok; // MaterialSystem not initialized yet

		// Create pipeline layout (shared by both variants)
		IBindGroupLayout[2] layouts = .(mSceneBindGroupLayout, materialLayout);
		PipelineLayoutDescriptor layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(&layoutDesc))
		{
		case .Ok(let layout): mForwardPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Vertex layout - Mesh format matches Sedulous.Geometry.StaticMesh
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Color targets for HDR output
		ColorTargetState[1] colorTargets = .(
			.(.RGBA16Float)
		);

		// --- Create non-shadow pipeline variant ---
		{
			let shaderResult = Renderer.ShaderSystem.GetShaderPair("forward", .DepthTest | .DepthWrite);
			if (shaderResult case .Err)
				return .Ok; // Shaders not available yet

			let (vertShader, fragShader) = shaderResult.Value;

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Opaque Pipeline (No Shadows)",
				Layout = mForwardPipelineLayout,
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
					CullMode = .Back
				},
				DepthStencil = .() // Depth test with equal, no write
				{
					DepthTestEnabled = true,
					DepthWriteEnabled = false,
					DepthCompare = .LessEqual
				},
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mForwardPipeline = pipeline;
			case .Err: return .Err;
			}
		}

		// --- Create shadow-receiving pipeline variant ---
		{
			let shaderResult = Renderer.ShaderSystem.GetShaderPair("forward", .DefaultOpaque);
			if (shaderResult case .Err)
				return .Ok; // Shaders not available yet (will use non-shadow variant)

			let (vertShader, fragShader) = shaderResult.Value;

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Opaque Pipeline (With Shadows)",
				Layout = mForwardPipelineLayout,
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
					CullMode = .Back
				},
				DepthStencil = .() // Depth test with equal, no write
				{
					DepthTestEnabled = true,
					DepthWriteEnabled = false,
					DepthCompare = .LessEqual
				},
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mForwardShadowPipeline = pipeline;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private Result<void> CreateInstancedForwardPipelines()
	{
		// Skip if shader system or pipeline layout not initialized
		if (Renderer.ShaderSystem == null || mForwardPipelineLayout == null)
			return .Err;

		// Get material bind group layout from MaterialSystem
		let materialLayout = Renderer.MaterialSystem?.DefaultMaterialLayout;
		if (materialLayout == null)
			return .Err;

		// Vertex layout for forward instancing (without NORMAL_MAP):
		// - Mesh buffer uses stride 48 (full Mesh format) but only declares Position/Normal/UV
		// - DXC assigns locations sequentially, so instance data starts at location 3
		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2)   // UV
		);
		Sedulous.RHI.VertexAttribute[4] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),   // WorldRow0
			.(VertexFormat.Float4, 16, 4),  // WorldRow1
			.(VertexFormat.Float4, 32, 5),  // WorldRow2
			.(VertexFormat.Float4, 48, 6)   // WorldRow3
		);
		VertexBufferLayout[2] vertexBuffers = .(
			.(48, meshAttrs, .Vertex),              // Mesh buffer (stride 48, but only 3 attrs)
			.(64, instanceAttrs, .Instance)         // Instance buffer
		);

		// Color targets for HDR output
		ColorTargetState[1] colorTargets = .(
			.(.RGBA16Float)
		);

		// --- Create instanced non-shadow pipeline ---
		{
			let shaderResult = Renderer.ShaderSystem.GetShaderPair("forward", .DepthTest | .DepthWrite | .Instanced);
			if (shaderResult case .Err)
				return .Err; // Instanced shader variant not available

			let (vertShader, fragShader) = shaderResult.Value;

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Opaque Instanced Pipeline (No Shadows)",
				Layout = mForwardPipelineLayout,
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
					CullMode = .Back
				},
				DepthStencil = .()
				{
					DepthTestEnabled = true,
					DepthWriteEnabled = false,
					DepthCompare = .LessEqual
				},
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mForwardInstancedPipeline = pipeline;
			case .Err: return .Err;
			}
		}

		// --- Create instanced shadow-receiving pipeline ---
		{
			let shaderResult = Renderer.ShaderSystem.GetShaderPair("forward", .DefaultOpaque | .Instanced);
			if (shaderResult case .Err)
				return .Ok; // Shadow variant not available, but basic instancing works

			let (vertShader, fragShader) = shaderResult.Value;

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "Forward Opaque Instanced Pipeline (With Shadows)",
				Layout = mForwardPipelineLayout,
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
					CullMode = .Back
				},
				DepthStencil = .()
				{
					DepthTestEnabled = true,
					DepthWriteEnabled = false,
					DepthCompare = .LessEqual
				},
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mForwardInstancedShadowPipeline = pipeline;
			case .Err: // Shadow variant failed, but basic instancing still works
			}
		}

		return .Ok;
	}

	/// Gets the appropriate pipeline for a material.
	/// Uses the pipeline cache with caller-provided vertex layouts.
	/// The vertex layout is determined by the mesh type (instanced vs non-instanced), not the material.
	private IRenderPipeline GetPipelineForMaterial(MaterialInstance material, bool shadowsEnabled, bool instanced)
	{
		if (mPipelineCache == null || mForwardPipelineLayout == null)
			return mForwardPipeline;

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
			// Instanced: simplified mesh attrs + instance transforms
			// This matches the instanced forward shader's vertex input
			Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
				.(VertexFormat.Float3, 0, 0),   // Position
				.(VertexFormat.Float3, 12, 1),  // Normal
				.(VertexFormat.Float2, 24, 2)   // UV
			);
			Sedulous.RHI.VertexAttribute[4] instanceAttrs = .(
				.(VertexFormat.Float4, 0, 3),   // WorldRow0
				.(VertexFormat.Float4, 16, 4),  // WorldRow1
				.(VertexFormat.Float4, 32, 5),  // WorldRow2
				.(VertexFormat.Float4, 48, 6)   // WorldRow3
			);
			VertexBufferLayout[2] vertexBuffers = .(
				.(48, meshAttrs, .Vertex),
				.(64, instanceAttrs, .Instance)
			);

			if (mPipelineCache.GetPipelineForMaterial(
				material,
				vertexBuffers,
				mForwardPipelineLayout,
				.RGBA16Float,
				.Depth32Float,
				1,
				variantFlags,
				.ReadOnly,
				.LessEqual) case .Ok(let pipeline))  // LessEqual for forward pass after depth prepass
			{
				return pipeline;
			}

			// Fall back to pre-created instanced pipeline
			return (shadowsEnabled && mForwardInstancedShadowPipeline != null)
				? mForwardInstancedShadowPipeline
				: mForwardInstancedPipeline;
		}
		else
		{
			// Non-instanced: full mesh vertex layout
			VertexBufferLayout[1] vertexBuffers = .(
				VertexLayoutHelper.CreateBufferLayout(.Mesh)
			);

			if (mPipelineCache.GetPipelineForMaterial(
				material,
				vertexBuffers,
				mForwardPipelineLayout,
				.RGBA16Float,
				.Depth32Float,
				1,
				variantFlags,
				.ReadOnly,
				.LessEqual) case .Ok(let pipeline))  // LessEqual for forward pass after depth prepass
			{
				return pipeline;
			}

			// Fall back to pre-created pipeline
			return mForwardPipeline;
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

		BindGroupLayoutDescriptor shadowLayoutDesc = .()
		{
			Label = "Shadow BindGroup Layout",
			Entries = shadowEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&shadowLayoutDesc))
		{
		case .Ok(let layout): mShadowBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create shadow pipeline layout
		IBindGroupLayout[1] layouts = .(mShadowBindGroupLayout);
		PipelineLayoutDescriptor layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(&layoutDesc))
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
			BufferDescriptor uniformDesc = .()
			{
				Size = AlignedSceneUniformSize * 4, // 4 cascades
				Usage = .Uniform,
				MemoryAccess = .Upload // CPU-mappable
			};
			switch (Renderer.Device.CreateBuffer(&uniformDesc))
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
			BufferDescriptor objDesc = .()
			{
				Size = AlignedObjectUniformSize * RenderConfig.MaxOpaqueObjectsPerFrame,
				Usage = .Uniform,
				MemoryAccess = .Upload // CPU-mappable
			};
			switch (Renderer.Device.CreateBuffer(&objDesc))
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
		RenderPipelineDescriptor pipelineDesc = .()
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
				DepthBias = 2,          // Hardware depth bias to prevent shadow acne
				DepthBiasSlopeScale = 2.0f
			},
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mShadowDepthPipeline = pipeline;
		case .Err: return .Err;
		}

		// Create shadow bind group
		CreateShadowBindGroup();

		return .Ok;
	}

	private Result<void> CreateDummyShadowMap()
	{
		// Create a small 4x4 depth array texture with 4 layers for use when shadows are disabled
		// This satisfies the shader's expectation of Texture2DArray for ShadowMap
		// Using 4x4 instead of 1x1 to avoid sampling artifacts with comparison sampler
		TextureDescriptor texDesc = .()
		{
			Label = "Dummy Shadow Map Array",
			Dimension = .Texture2D,
			Width = 4,
			Height = 4,
			Depth = 1,
			Format = .Depth32Float,
			MipLevelCount = 1,
			ArrayLayerCount = 4, // Match cascade count
			SampleCount = 1,
			Usage = .DepthStencil | .Sampled
		};

		switch (Renderer.Device.CreateTexture(&texDesc))
		{
		case .Ok(let tex): mDummyShadowMapArray = tex;
		case .Err: return .Err;
		}

		// Create array view for sampling
		TextureViewDescriptor viewDesc = .()
		{
			Label = "Dummy Shadow Map Array View",
			Format = .Depth32Float,
			Dimension = .Texture2DArray,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 4,
			Aspect = .DepthOnly
		};

		switch (Renderer.Device.CreateTextureView(mDummyShadowMapArray, &viewDesc))
		{
		case .Ok(let view): mDummyShadowMapArrayView = view;
		case .Err: return .Err;
		}

		// Initialize to max depth (1.0 = fully lit, no shadow) via a clear render pass
		// This transitions the texture out of UNDEFINED layout
		ClearDummyShadowMap();

		return .Ok;
	}

	private void ClearDummyShadowMap()
	{
		if (mDummyShadowMapArray == null)
			return;

		// Create temporary views for all layers
		ITextureView[4] layerViews = .(null, null, null, null);
		defer
		{
			for (let view in layerViews)
				if (view != null)
					delete view;
		}

		for (uint32 layer = 0; layer < 4; layer++)
		{
			TextureViewDescriptor layerViewDesc = .()
			{
				Label = "Dummy Shadow Layer View",
				Format = .Depth32Float,
				Dimension = .Texture2D,
				BaseMipLevel = 0,
				MipLevelCount = 1,
				BaseArrayLayer = layer,
				ArrayLayerCount = 1,
				Aspect = .DepthOnly
			};

			if (Renderer.Device.CreateTextureView(mDummyShadowMapArray, &layerViewDesc) case .Ok(let view))
				layerViews[layer] = view;
		}

		// Use a single command encoder to clear all layers and transition
		let encoder = Renderer.Device.CreateCommandEncoder();
		if (encoder == null)
			return;
		defer delete encoder;

		// Clear each layer with a render pass
		for (uint32 layer = 0; layer < 4; layer++)
		{
			if (layerViews[layer] == null)
				continue;

			RenderPassDescriptor rpDesc = .()
			{
				Label = "Clear Dummy Shadow Layer",
				DepthStencilAttachment = .()
				{
					View = layerViews[layer],
					DepthLoadOp = .Clear,
					DepthStoreOp = .Store,
					DepthClearValue = 1.0f // Max depth = no shadow
				}
			};

			let pass = encoder.BeginRenderPass(&rpDesc);
			if (pass != null)
			{
				pass.End();
				delete pass;
			}
		}

		// Transition whole texture to ShaderReadOnly after all clears
		encoder.TextureBarrier(mDummyShadowMapArray, .DepthStencilAttachment, .ShaderReadOnly);

		let cmdBuffer = encoder.Finish();
		if (cmdBuffer != null)
		{
			Renderer.Device.Queue.Submit(cmdBuffer);
			// Wait for GPU to finish before we delete the views
			Renderer.Device.WaitIdle();
			delete cmdBuffer;
		}
	}

	protected override void OnShutdown()
	{
		// Pipeline cache is cleaned up by destructor (~ delete _)

		// Clean up per-frame resources
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mSceneBindGroups[i] != null)
			{
				delete mSceneBindGroups[i];
				mSceneBindGroups[i] = null;
			}

			if (mObjectUniformBuffers[i] != null)
			{
				delete mObjectUniformBuffers[i];
				mObjectUniformBuffers[i] = null;
			}

			if (mShadowBindGroups[i] != null)
			{
				delete mShadowBindGroups[i];
				mShadowBindGroups[i] = null;
			}

			if (mShadowUniformBuffers[i] != null)
			{
				delete mShadowUniformBuffers[i];
				mShadowUniformBuffers[i] = null;
			}

			if (mShadowObjectBuffers[i] != null)
			{
				delete mShadowObjectBuffers[i];
				mShadowObjectBuffers[i] = null;
			}
		}

		if (mLighting != null)
			mLighting.Dispose();

		if (mShadowRenderer != null)
			mShadowRenderer.Dispose();
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
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
			let colorDesc = TextureResourceDesc(view.Width, view.Height, .RGBA16Float, .RenderTarget | .Sampled);

			let colorHandle = graph.CreateTexture("SceneColor", colorDesc);

			// Capture frame index for consistent multi-buffering
			let frameIndex = FrameIndex;

			// Update lighting
			using (SProfiler.Begin("UpdateLighting"))
				UpdateLighting(world, depthFeature.Visibility, view, frameIndex);

			// Add shadow passes and get shadow map handle for automatic barrier
			RGResourceHandle shadowMapHandle = .Invalid;
			using (SProfiler.Begin("AddShadowPasses"))
				AddShadowPasses(graph, world, depthFeature.Visibility, view, frameIndex, out shadowMapHandle);

			// Create/update scene bind group for current frame (needs to be done each frame for frame-specific resources)
			CreateSceneBindGroup(frameIndex); // todo jayrulez: look into who we need this per frame.

			// Upload object uniforms BEFORE the render pass
			using (SProfiler.Begin("PrepareObjectUniforms"))
				PrepareObjectUniforms(depthFeature, frameIndex);

			// Add forward opaque pass
			// ReadTexture on shadow map triggers automatic barrier: DepthStencil -> ShaderReadOnly
			var passBuilder = graph.AddGraphicsPass("ForwardOpaque")
				.WriteColor(colorHandle, .Clear, .Store, .(0.0f, 0.0f, 0.0f, 1.0f))
				.ReadDepth(depthHandle)
				.NeverCull();

			// Add shadow map as read dependency if available (triggers automatic barrier)
			if (shadowMapHandle.IsValid)
				passBuilder.ReadTexture(shadowMapHandle);

			passBuilder.SetExecuteCallback(new (encoder) => {
				ExecuteForwardPass(encoder, world, view, depthFeature, frameIndex);
			});
		}
	}

	private void PrepareObjectUniforms(DepthPrepassFeature depthFeature, int32 frameIndex)
	{
		// Upload object transforms to the uniform buffer BEFORE the render pass
		// Use Map/Unmap to avoid command buffer creation
		let skinnedCommands = depthFeature.Batcher.SkinnedCommands;

		// Use the current frame's buffer
		let buffer = mObjectUniformBuffers[frameIndex];
		if (buffer == null)
			return;

		if (let bufferPtr = buffer.Map())
		{
			int32 objectIndex = 0;

			// Static meshes - SKIP if instancing is active (instance buffer has transforms)
			if (!depthFeature.InstancingActive)
			{
				let commands = depthFeature.Batcher.DrawCommands;
				for (let batch in depthFeature.Batcher.OpaqueBatches)
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
							NormalMatrix = cmd.NormalMatrix,
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
			for (let batch in depthFeature.Batcher.SkinnedBatches)
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
						NormalMatrix = cmd.NormalMatrix,
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

	private void UpdateLighting(RenderWorld world, VisibilityResolver visibility, RenderView view, int32 frameIndex)
	{
		// Update cluster grid
		let inverseProj = Matrix.Invert(view.ProjectionMatrix);
		mLighting.ClusterGrid.Update(view.Width, view.Height, view.NearPlane, view.FarPlane, inverseProj);

		// Calculate cluster scale/bias for shader
		let config = mLighting.ClusterGrid.Config;
		let clusterScaleX = (float)config.ClustersX / (float)view.Width;
		let clusterScaleY = (float)config.ClustersY / (float)view.Height;
		let logDepthScale = (float)config.ClustersZ / Math.Log(view.FarPlane / view.NearPlane);
		let logDepthBias = -(float)config.ClustersZ * Math.Log(view.NearPlane) / Math.Log(view.FarPlane / view.NearPlane);

		// Update light buffer cluster info
		mLighting.LightBuffer.SetClusterInfo(
			config.ClustersX, config.ClustersY, config.ClustersZ,
			.(clusterScaleX, clusterScaleY),
			.(logDepthScale, logDepthBias)
		);

		// Apply environment settings from RenderWorld
		mLighting.LightBuffer.AmbientColor = world.AmbientColor;
		mLighting.LightBuffer.AmbientIntensity = world.AmbientIntensity;
		mLighting.LightBuffer.Exposure = world.Exposure;

		// Update light buffer from visibility
		mLighting.LightBuffer.Update(world, visibility);
		mLighting.LightBuffer.UploadLightData(frameIndex);
		mLighting.LightBuffer.UploadUniforms(frameIndex);

		// Perform light culling (CPU fallback for now)
		// Pass view matrix to transform light positions to view space for cluster testing
		mLighting.ClusterGrid.CullLightsCPU(world, visibility, view.ViewMatrix, frameIndex);
	}

	private void AddShadowPasses(RenderGraph graph, RenderWorld world, VisibilityResolver visibility, RenderView view, int32 frameIndex, out RGResourceHandle outShadowMapHandle)
	{
		outShadowMapHandle = .Invalid;

		if (!mShadowRenderer.EnableShadows)
			return;

		if (!mShadowRenderer.IsInitialized)
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
		mShadowRenderer.Update(world, visibility, &camera);

		// Get shadow passes
		List<ShadowPass> shadowPasses = scope .();
		mShadowRenderer.GetShadowPasses(shadowPasses);

		if (shadowPasses.Count == 0)
			return;

		// Upload all shadow uniforms BEFORE adding passes (avoid WriteBuffer during render pass)
		PrepareShadowUniforms(world, visibility, shadowPasses, frameIndex);

		// Import the shadow map array once with a common name for barrier tracking
		// This handle will be used by the forward pass to trigger automatic barrier
		let cascadedShadowMap = mShadowRenderer.CascadedShadows?.ShadowMapArray;
		let cascadedShadowMapView = mShadowRenderer.CascadedShadows?.ShadowMapArrayView;
		if (cascadedShadowMap != null && cascadedShadowMapView != null)
		{
			outShadowMapHandle = graph.ImportTexture("ShadowMap", cascadedShadowMap, cascadedShadowMapView);
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
			ITexture shadowTexture = mShadowRenderer.CascadedShadows?.ShadowMapArray;

			if (shadowTexture == null || shadowPass.RenderTarget == null)
				continue;

			// Import shadow render target with actual texture
			let shadowTarget = graph.ImportTexture(passName, shadowTexture, shadowPass.RenderTarget);

			// Copy shadow pass for closure - use CascadeIndex from the pass itself
			ShadowPass passCopy = shadowPass;
			graph.AddGraphicsPass(passName)
				.WriteDepth(shadowTarget)
				.NeverCull() // Shadow maps are used externally by forward pass
				.SetExecuteCallback(new (encoder) => {
					ExecuteShadowPass(encoder, world, visibility, passCopy, frameIndex);
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
						NormalMatrix = proxy.NormalMatrix,
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
						NormalMatrix = proxy.NormalMatrix,
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

	private Result<void> CreateBindGroupLayouts()
	{
		// Scene bind group: camera, per-object transforms, lighting, shadows
		// Shader bindings (space0): b0=Camera, b1=ObjectUniforms, b3=LightingUniforms, b5=ShadowUniforms,
		//                           t4=Lights, t5=ClusterLightInfo, t6=LightIndices (read-only StructuredBuffers),
		//                           t7=ShadowMap, s1=ShadowSampler
		// Use HLSL register numbers - RHI applies Vulkan shifts based on Type
		BindGroupLayoutEntry[9] sceneEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer }, // b0: Camera
			.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true }, // b1: ObjectUniforms (dynamic offset per-object)
			.() { Binding = 3, Visibility = .Fragment, Type = .UniformBuffer },           // b3: Lighting uniforms
			.() { Binding = 4, Visibility = .Fragment, Type = .StorageBuffer },           // t4: Lights (StructuredBuffer)
			.() { Binding = 5, Visibility = .Fragment, Type = .StorageBuffer },           // t5: ClusterLightInfo (StructuredBuffer)
			.() { Binding = 6, Visibility = .Fragment, Type = .StorageBuffer },           // t6: LightIndices (StructuredBuffer)
			.() { Binding = 5, Visibility = .Fragment, Type = .UniformBuffer },           // b5: Shadow uniforms
			.() { Binding = 7, Visibility = .Fragment, Type = .SampledTexture },          // t7: ShadowMap
			.() { Binding = 1, Visibility = .Fragment, Type = .ComparisonSampler }        // s1: ShadowSampler
		);

		BindGroupLayoutDescriptor sceneDesc = .()
		{
			Label = "Scene BindGroup Layout",
			Entries = sceneEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&sceneDesc))
		{
		case .Ok(let layout): mSceneBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Material bind group layout is now provided by MaterialSystem
		// See Renderer.MaterialSystem.DefaultMaterialLayout

		return .Ok;
	}

	private Result<void> CreateObjectUniformBuffer()
	{
		// Create per-frame object uniform buffers large enough for RenderConfig.MaxOpaqueObjectsPerFrame with alignment
		// Use Upload memory for CPU mapping (avoids command buffer for writes)
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			var bufferDesc = BufferDescriptor()
			{
				Size = AlignedObjectUniformSize * RenderConfig.MaxOpaqueObjectsPerFrame,
				Usage = .Uniform,
				MemoryAccess = .Upload // CPU-mappable
			};

			switch (Renderer.Device.CreateBuffer(&bufferDesc))
			{
			case .Ok(let buffer): mObjectUniformBuffers[i] = buffer;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private void CreateSceneBindGroup(int32 frameIndex)
	{
		// Delete old bind group if exists
		if (mSceneBindGroups[frameIndex] != null)
		{
			delete mSceneBindGroups[frameIndex];
			mSceneBindGroups[frameIndex] = null;
		}

		// Need all resources to be valid - use frame-specific buffers
		let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
		let objectBuffer = mObjectUniformBuffers[frameIndex];
		let lightingBuffer = mLighting?.LightBuffer?.GetUniformBuffer(frameIndex);
		let lightDataBuffer = mLighting?.LightBuffer?.GetLightDataBuffer(frameIndex);
		let clusterInfoBuffer = mLighting?.ClusterGrid?.GetClusterLightInfoBuffer(frameIndex);
		let lightIndexBuffer = mLighting?.ClusterGrid?.GetLightIndexBuffer(frameIndex);

		// Check required resources
		if (cameraBuffer == null || objectBuffer == null ||
			lightingBuffer == null || lightDataBuffer == null ||
			clusterInfoBuffer == null || lightIndexBuffer == null)
		{
			return; // Can't create bind group without all resources
		}

		// Build bind group entries
		// Note: Some shadow resources may be null - provide fallbacks or skip
		BindGroupEntry[9] entries = .();

		// b0: Camera uniforms
		entries[0] = BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size);

		// b1: Object uniforms (dynamic offset - bind full buffer, use aligned size per object)
		entries[1] = BindGroupEntry.Buffer(1, objectBuffer, 0, AlignedObjectUniformSize);

		// b3: Lighting uniforms
		entries[2] = BindGroupEntry.Buffer(3, lightingBuffer, 0, (uint64)LightingUniforms.Size);

		// t4: Lights storage buffer
		entries[3] = BindGroupEntry.Buffer(4, lightDataBuffer, 0, (uint64)(mLighting.LightBuffer.MaxLights * GPULight.Size));

		// t5: ClusterLightInfo storage buffer (8 bytes per cluster: 2 uint32)
		entries[4] = BindGroupEntry.Buffer(5, clusterInfoBuffer, 0, (uint64)(mLighting.ClusterGrid.Config.TotalClusters * 8));

		// t6: LightIndices storage buffer
		entries[5] = BindGroupEntry.Buffer(6, lightIndexBuffer, 0, (uint64)(mLighting.ClusterGrid.Config.MaxLightsPerCluster * mLighting.ClusterGrid.Config.TotalClusters * 4));

		// Get shadow resources from ShadowRenderer (only use if shadows are enabled)
		let shadowsEnabled = mShadowRenderer?.EnableShadows ?? false;
		let shadowData = mShadowRenderer.GetShadowShaderData();
		let materialSystem = Renderer.MaterialSystem;

		// b5: Shadow uniforms
		if (shadowsEnabled && shadowData.CascadedShadowUniforms != null)
			entries[6] = BindGroupEntry.Buffer(5, shadowData.CascadedShadowUniforms, 0, (uint64)ShadowUniforms.Size);
		else
			entries[6] = BindGroupEntry.Buffer(5, lightingBuffer, 0, (uint64)LightingUniforms.Size); // Fallback

		// t7: Shadow map texture (cascaded shadow map array)
		// Only use shadow map if shadows are enabled - otherwise use dummy shadow map array
		if (shadowsEnabled && shadowData.CascadedShadowMapView != null)
			entries[7] = BindGroupEntry.Texture(7, shadowData.CascadedShadowMapView);
		else if (mDummyShadowMapArrayView != null)
			entries[7] = BindGroupEntry.Texture(7, mDummyShadowMapArrayView); // Dummy 4-layer array
		else
			return; // Can't create without texture

		// s1: Shadow sampler (comparison sampler for PCF)
		// Always use the shadow sampler if available (comparison sampler needed for depth comparison)
		if (shadowData.CascadedShadowSampler != null)
			entries[8] = BindGroupEntry.Sampler(1, shadowData.CascadedShadowSampler);
		else if (materialSystem?.DefaultSampler != null)
			entries[8] = BindGroupEntry.Sampler(1, materialSystem.DefaultSampler); // Fallback
		else
			return; // Can't create without sampler

		// Create bind group
		BindGroupDescriptor bgDesc = .()
		{
			Label = "Scene BindGroup",
			Layout = mSceneBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&bgDesc) case .Ok(let bg))
			mSceneBindGroups[frameIndex] = bg;
	}

	private void ExecuteForwardPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view, DepthPrepassFeature depthFeature, int32 frameIndex)
	{
		using (SProfiler.Begin("ForwardOpaque.Execute"))
		{
			// Set viewport
			encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
			encoder.SetScissorRect(0, 0, view.Width, view.Height);

			// Track object index for uniform buffer dynamic offsets
			var objectIndex = (int32)0;

			// Track current bound material to minimize rebinds
			MaterialInstance currentMaterial = null;

			// Use instanced path if available and has instance groups
			let batcher = depthFeature.Batcher;
			if (mInstancingEnabled && depthFeature.InstancingActive && mForwardInstancedPipeline != null && batcher.OpaqueInstanceGroups.Length > 0)
			{
				using (SProfiler.Begin("InstancedDraw"))
					ExecuteInstancedForwardPass(encoder, world, depthFeature, frameIndex, ref currentMaterial);
				// Instanced path doesn't use uniform buffer for static meshes,
				// skinned uniforms start at index 0 (we skipped static mesh uploads)
				objectIndex = 0;
			}
			else
			{
				// Fall back to non-instanced path
				using (SProfiler.Begin("NonInstancedDraw"))
					ExecuteNonInstancedForwardPass(encoder, world, depthFeature, frameIndex, ref objectIndex, ref currentMaterial);
			}

			// Render skinned meshes (always non-instanced)
			using (SProfiler.Begin("SkinnedMeshes"))
				RenderSkinnedMeshes(encoder, world, view, depthFeature, frameIndex, ref objectIndex, ref currentMaterial);
		}
	}

	private void ExecuteInstancedForwardPass(IRenderPassEncoder encoder, RenderWorld world, DepthPrepassFeature depthFeature, int32 frameIndex, ref MaterialInstance currentMaterial)
	{
		// Get shadow state for pipeline selection
		let shadowsEnabled = mShadowRenderer?.EnableShadows ?? false;

		// Track current pipeline to minimize state changes
		IRenderPipeline currentPipeline = null;

		// Set initial default instanced pipeline
		let defaultPipeline = (shadowsEnabled && mForwardInstancedShadowPipeline != null) ? mForwardInstancedShadowPipeline : mForwardInstancedPipeline;
		if (defaultPipeline == null)
			return;

		encoder.SetPipeline(defaultPipeline);
		currentPipeline = defaultPipeline;

		// Get instance buffer from depth feature
		let instanceBuffer = depthFeature.GetInstanceBuffer(frameIndex);
		if (instanceBuffer == null)
			return;

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Get batcher data
		let batcher = depthFeature.Batcher;

		// Bind scene bind group (no dynamic offset needed for instanced - uses instance 0)
		let sceneBindGroup = mSceneBindGroups[frameIndex];
		if (sceneBindGroup != null)
		{
			uint32[1] dynamicOffsets = .(0);
			encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
		}

		// Render opaque instance groups
		for (let group in batcher.OpaqueInstanceGroups)
		{
			if (group.InstanceCount == 0)
				continue;

			// Get material for this group (all instances in group share the same material)
			MaterialInstance material = group.Material ?? defaultMaterialInstance;

			// Get pipeline for this material (may be custom shader)
			// Note: Custom shaders need instanced variants - fall back to default if not available
			let pipeline = GetPipelineForMaterial(material, shadowsEnabled, true);
			if (pipeline != null && pipeline != currentPipeline)
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

			// Get mesh data
			if (let mesh = Renderer.ResourceManager.GetMesh(group.GPUMesh))
			{
				// Bind vertex buffers: slot 0 = mesh, slot 1 = instance data
				encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
				encoder.SetVertexBuffer(1, instanceBuffer, (uint64)(group.InstanceStart * (int32)InstanceData.Size));

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

	private void ExecuteNonInstancedForwardPass(IRenderPassEncoder encoder, RenderWorld world, DepthPrepassFeature depthFeature, int32 frameIndex, ref int32 objectIndex, ref MaterialInstance currentMaterial)
	{
		// Get shadow state for pipeline selection
		let shadowsEnabled = mShadowRenderer?.EnableShadows ?? false;

		// Track current pipeline to minimize state changes
		IRenderPipeline currentPipeline = null;

		// Set initial default pipeline
		let defaultPipeline = (shadowsEnabled && mForwardShadowPipeline != null) ? mForwardShadowPipeline : mForwardPipeline;
		if (defaultPipeline != null)
		{
			encoder.SetPipeline(defaultPipeline);
			currentPipeline = defaultPipeline;
		}

		// Get material system for binding materials
		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Get draw commands from batcher (uniforms already uploaded in PrepareObjectUniforms)
		let batcher = depthFeature.Batcher;
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

				// Get mesh proxy to access material
				MeshProxy* proxy = null;
				if (cmd.MeshHandle.IsValid)
					proxy = world.GetMesh(cmd.MeshHandle);

				// Get material instance (use default if none assigned)
				MaterialInstance material = proxy?.Material ?? defaultMaterialInstance;

				// Get pipeline for this material (may be custom shader)
				let pipeline = GetPipelineForMaterial(material, shadowsEnabled, false);
				if (pipeline != null && pipeline != currentPipeline)
				{
					encoder.SetPipeline(pipeline);
					currentPipeline = pipeline;
				}

				// Bind material if changed
				if (material != currentMaterial && material != null && materialSystem != null)
				{
					// Prepare material instance (ensures bind group is ready)
					if (materialSystem.PrepareInstance(material) case .Ok(let bindGroup))
					{
						encoder.SetBindGroup(1, bindGroup, default);
						currentMaterial = material;
					}
				}

				// Bind scene bind group with dynamic offset for this object's transforms
				let sceneBindGroup = mSceneBindGroups[frameIndex];
				if (sceneBindGroup != null)
				{
					uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
					encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
				}

				// Get mesh data
				if (let mesh = Renderer.ResourceManager.GetMesh(cmd.GPUMesh))
				{
					// Bind vertex/index buffers
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);

					if (mesh.IndexBuffer != null)
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					else
						encoder.Draw(mesh.VertexCount, 1, 0, 0);

					Renderer.Stats.DrawCalls++;
					Renderer.Stats.TriangleCount += (int32)(mesh.IndexCount / 3);
				}

				objectIndex++;
			}
		}
	}

	private void RenderSkinnedMeshes(IRenderPassEncoder encoder, RenderWorld world, RenderView view, DepthPrepassFeature depthFeature, int32 frameIndex, ref int32 objectIndex, ref MaterialInstance currentMaterial)
	{
		// Get GPU skinning feature to access skinned vertex buffers
		let skinningFeature = Renderer.GetFeature<GPUSkinningFeature>();
		if (skinningFeature == null)
			return;

		// Get shadow state for pipeline selection
		let shadowsEnabled = mShadowRenderer?.EnableShadows ?? false;

		// Track current pipeline to minimize state changes
		IRenderPipeline currentPipeline = null;

		// Set initial default pipeline for skinned meshes (non-instanced)
		let defaultPipeline = (shadowsEnabled && mForwardShadowPipeline != null) ? mForwardShadowPipeline : mForwardPipeline;
		if (defaultPipeline != null)
		{
			encoder.SetPipeline(defaultPipeline);
			currentPipeline = defaultPipeline;
		}

		let materialSystem = Renderer.MaterialSystem;
		let defaultMaterialInstance = materialSystem?.DefaultMaterialInstance;

		// Get skinned mesh commands from batcher
		let skinnedCommands = depthFeature.Batcher.SkinnedCommands;

		// Render each skinned mesh batch
		for (let batch in depthFeature.Batcher.SkinnedBatches)
		{
			if (batch.CommandCount == 0)
				continue;

			for (int32 i = 0; i < batch.CommandCount; i++)
			{
				if (objectIndex >= RenderConfig.MaxOpaqueObjectsPerFrame)
					break;

				let cmd = skinnedCommands[batch.CommandStart + i];

				// Get skinned mesh proxy for material
				SkinnedMeshProxy* proxy = null;
				if (cmd.MeshHandle.IsValid)
					proxy = world.GetSkinnedMesh(cmd.MeshHandle);

				if (proxy == null)
					continue;

				// Get material instance
				MaterialInstance material = proxy.Material ?? defaultMaterialInstance;

				// Get pipeline for this material (may be custom shader)
				let pipeline = GetPipelineForMaterial(material, shadowsEnabled, false);
				if (pipeline != null && pipeline != currentPipeline)
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

				// Upload object uniforms for this skinned mesh
				// Note: Skinned mesh uniforms should have been prepared by PrepareSkinnedObjectUniforms
				let sceneBindGroup = mSceneBindGroups[frameIndex];
				if (sceneBindGroup != null)
				{
					uint32[1] dynamicOffsets = .((uint32)(objectIndex * (int32)AlignedObjectUniformSize));
					encoder.SetBindGroup(0, sceneBindGroup, dynamicOffsets);
				}

				// Get the skinned vertex buffer from the skinning feature
				let skinnedVertexBuffer = skinningFeature.GetSkinnedVertexBuffer(cmd.MeshHandle);
				if (skinnedVertexBuffer != null)
				{
					// Bind the skinned vertex buffer (post-transform)
					encoder.SetVertexBuffer(0, skinnedVertexBuffer, 0);

					// Get mesh for index buffer (indices don't change with skinning)
					if (let mesh = Renderer.ResourceManager.GetMesh(cmd.GPUMesh))
					{
						if (mesh.IndexBuffer != null)
						{
							encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
							encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
						}
						else
						{
							encoder.Draw(mesh.VertexCount, 1, 0, 0);
						}

						Renderer.Stats.DrawCalls++;
						Renderer.Stats.TriangleCount += (int32)((mesh.IndexCount > 0 ? mesh.IndexCount : mesh.VertexCount) / 3);
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

		encoder.SetScissorRect(
			(int32)shadowPass.Viewport.X,
			(int32)shadowPass.Viewport.Y,
			(uint32)shadowPass.Viewport.Width,
			(uint32)shadowPass.Viewport.Height
		);

		// Set shadow pipeline
		encoder.SetPipeline(mShadowDepthPipeline);

		// Calculate cascade VP offset (for dynamic uniform binding 0)
		// Uses CascadeIndex from the shadow pass to select the correct VP matrix slot
		uint32 cascadeVPOffset = (uint32)((int64)cascadeIndex * (int64)mAlignedSceneUniformSize);

		// Render shadow casters (object transforms already uploaded in PrepareShadowUniforms)
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

				if (let mesh = Renderer.ResourceManager.GetMesh(proxy.MeshHandle))
				{
					// Two dynamic offsets: [0] = cascade VP, [1] = object transforms
					uint32 objectOffset = (uint32)((int64)objectIndex * (int64)AlignedObjectUniformSize);
					uint32[2] dynamicOffsets = .(cascadeVPOffset, objectOffset);
					encoder.SetBindGroup(0, shadowBindGroup, dynamicOffsets);

					// Bind vertex/index buffers and draw
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					}
					else
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
					}

					Renderer.Stats.ShadowDrawCalls++;
					objectIndex++;
				}
			}
		}

		// Skinned meshes - render using post-transform vertex buffers
		RenderSkinnedMeshesShadow(encoder, world, visibility, cascadeVPOffset, frameIndex);
	}

	private void RenderSkinnedMeshesShadow(IRenderPassEncoder encoder, RenderWorld world, VisibilityResolver visibility, uint32 cascadeVPOffset, int32 frameIndex)
	{
		// Get GPU skinning feature to access skinned vertex buffers
		let skinningFeature = Renderer.GetFeature<GPUSkinningFeature>();
		if (skinningFeature == null)
			return;

		let shadowBindGroup = mShadowBindGroups[frameIndex];
		if (shadowBindGroup == null)
			return;

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
				let skinnedVertexBuffer = skinningFeature.GetSkinnedVertexBuffer(visibleMesh.Handle);
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
					if (mesh.IndexBuffer != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					}
					else
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
					}

					Renderer.Stats.ShadowDrawCalls++;
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
				BindGroupEntry.Buffer(0, shadowUniformBuffer, 0, mAlignedSceneUniformSize), // Per-cascade VP (dynamic)
				BindGroupEntry.Buffer(1, shadowObjectBuffer, 0, AlignedObjectUniformSize)   // Per-object transforms (dynamic)
			);

			BindGroupDescriptor bgDesc = .()
			{
				Label = "Shadow BindGroup",
				Layout = mShadowBindGroupLayout,
				Entries = entries
			};

			if (Renderer.Device.CreateBindGroup(&bgDesc) case .Ok(let bg))
				mShadowBindGroups[i] = bg;
		}
	}
}
