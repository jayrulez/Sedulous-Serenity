namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// Uniform data for a single decal (256-byte aligned for dynamic uniform offset).
[CRepr]
struct DecalUniforms
{
	public Matrix WorldMatrix;       // 64 bytes
	public Matrix InvWorldMatrix;    // 64 bytes
	public Vector4 DecalColor;       // 16 bytes
	public float AngleFadeStart;     // 4 bytes
	public float AngleFadeEnd;       // 4 bytes
	public float _Pad0;              // 4 bytes
	public float _Pad1;              // 4 bytes
	// Total: 160 bytes, padded to 256 by alignment

	public const uint32 Size = sizeof(Self);

	private static void AssertSize()
	{
		Compiler.Assert(sizeof(Self) == 160);
	}
}

/// Uniform data for a curve decal (matches curve_decal shaders).
[CRepr]
struct CurveDecalUniforms
{
	public Vector4 Color;            // 16 bytes
	public float ProjectionDepth;    // 4 bytes
	public float[3] _Pad;           // 12 bytes
	// Total: 32 bytes

	public const uint32 Size = sizeof(Self);

	private static void AssertSize()
	{
		Compiler.Assert(sizeof(Self) == 32);
	}
}

/// Screen-space projected decal render feature.
/// Renders oriented bounding boxes that project textures onto opaque geometry
/// using the depth buffer.
public class DecalFeature : RenderFeatureBase
{
	// Per-blend-mode render pipelines
	private IRenderPipeline mPipelineAlpha ~ delete _;
	private IRenderPipeline mPipelineAdditive ~ delete _;
	private IRenderPipeline mPipelineMultiply ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;

	// Bind group layouts
	private IBindGroupLayout mSceneBindGroupLayout ~ delete _;  // Set 0: camera + depth
	private IBindGroupLayout mDecalBindGroupLayout ~ delete _;  // Set 1: decal uniforms + albedo

	// Unit cube geometry
	private IBuffer mCubeVertexBuffer ~ delete _;
	private IBuffer mCubeIndexBuffer ~ delete _;

	// Dynamic uniform buffers for per-decal uniforms (one per frame-in-flight)
	private const uint64 DecalUniformAlignment = 256;
	private const int32 MaxDecals = 128;
	private IBuffer[RenderConfig.FrameBufferCount] mDecalUniformBuffers ~ { for (let b in _) delete b; };

	// Default resources
	private ITexture mDefaultTexture ~ delete _;
	private ITextureView mDefaultTextureView ~ delete _;
	private ISampler mLinearClampSampler ~ delete _;
	private ISampler mDepthSampler ~ delete _;

	// Per-frame/view bind groups
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroups ~ { for (let bg in _) delete bg; };

	// Per-frame/view per-decal bind groups (cached to avoid destroying while GPU references them)
	private List<IBindGroup>[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mDecalBindGroups;

	// Per-frame active decal list (sorted)
	private List<DecalSortEntry> mActiveDecals = new .() ~ delete _;

	// Curve decal support
	private IRenderPipeline mCurvePipelineAlpha ~ delete _;
	private IRenderPipeline mCurvePipelineAdditive ~ delete _;
	private IRenderPipeline mCurvePipelineMultiply ~ delete _;
	private IPipelineLayout mCurvePipelineLayout ~ delete _;
	private IBindGroupLayout mCurveDecalBindGroupLayout ~ delete _;
	private CurveDecalMeshBuilder mCurveMeshBuilder = new .() ~ delete _;
	private IBuffer[RenderConfig.FrameBufferCount] mCurveVertexBuffers ~ { for (let b in _) delete b; };
	private IBuffer[RenderConfig.FrameBufferCount] mCurveIndexBuffers ~ { for (let b in _) delete b; };
	private IBuffer[RenderConfig.FrameBufferCount] mCurveUniformBuffers ~ { for (let b in _) delete b; };
	private const int32 MaxCurveDecals = 64;
	private const uint64 CurveDecalUniformAlignment = 256;
	private List<CurveDecalSortEntry> mActiveCurveDecals = new .() ~ delete _;
	private List<IBindGroup>[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mCurveDecalBindGroups;

	// Per-frame view dimensions
	private uint32 mViewWidth;
	private uint32 mViewHeight;
	private RGResourceHandle mDepthHandle;

	private int32 GetBindGroupIndex(int32 frameIndex) => frameIndex * RenderConfig.MaxViews + (Renderer.RenderFrameContext?.ActiveViewIndex ?? 0);

	/// Feature name.
	public override StringView Name => "Decals";

	/// Decals render after ForwardOpaque.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
	}

	protected override Result<void> OnInitialize()
	{
		if (CreateDefaultResources() case .Err)
			return .Err;

		if (CreateCubeGeometry() case .Err)
			return .Err;

		if (CreateBindGroupLayouts() case .Err)
			return .Err;

		if (CreatePipelines() case .Err)
			return .Err;

		for (int i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			mDecalBindGroups[i] = new List<IBindGroup>();
			mCurveDecalBindGroups[i] = new List<IBindGroup>();
		}

		// Create curve decal resources
		CreateCurveDecalResources();

		return .Ok;
	}

	protected override void OnShutdown()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mSceneBindGroups[i] != null)
			{
				delete mSceneBindGroups[i];
				mSceneBindGroups[i] = null;
			}

			if (mDecalBindGroups[i] != null)
			{
				for (let bg in mDecalBindGroups[i])
					delete bg;
				delete mDecalBindGroups[i];
				mDecalBindGroups[i] = null;
			}

			if (mCurveDecalBindGroups[i] != null)
			{
				for (let bg in mCurveDecalBindGroups[i])
					delete bg;
				delete mCurveDecalBindGroups[i];
				mCurveDecalBindGroups[i] = null;
			}
		}
	}

	private Result<void> CreateDefaultResources()
	{
		// Create default white 4x4 texture
		const int32 TexSize = 4;
		const int32 TexBytes = TexSize * TexSize * 4;

		TextureDesc texDesc = .()
		{
			Label = "Default Decal Texture",
			Width = TexSize,
			Height = TexSize,
			Depth = 1,
			Format = .RGBA8Unorm,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (Renderer.Device.CreateTexture(texDesc))
		{
		case .Ok(let tex): mDefaultTexture = tex;
		case .Err: return .Err;
		}

		uint8[TexBytes] pixels = default;
		for (int32 i = 0; i < TexBytes; i++)
			pixels[i] = 255;

		var layout = TextureDataLayout() { BytesPerRow = TexSize * 4, RowsPerImage = TexSize };
		var writeSize = Extent3D(TexSize, TexSize, 1);
		UploadTexture(mDefaultTexture, Span<uint8>(&pixels[0], TexBytes), &layout, &writeSize);

		TextureViewDesc viewDesc = .()
		{
			Label = "Default Decal Texture View",
			Dimension = .Texture2D
		};

		switch (Renderer.Device.CreateTextureView(mDefaultTexture, viewDesc))
		{
		case .Ok(let view): mDefaultTextureView = view;
		case .Err: return .Err;
		}

		// Linear clamp sampler for albedo textures
		SamplerDesc linearSamplerDesc = .()
		{
			Label = "Decal Linear Sampler",
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear
		};

		switch (Renderer.Device.CreateSampler(linearSamplerDesc))
		{
		case .Ok(let sampler): mLinearClampSampler = sampler;
		case .Err: return .Err;
		}

		// Point clamp sampler for depth texture
		SamplerDesc depthSamplerDesc = .()
		{
			Label = "Decal Depth Sampler",
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			MinFilter = .Nearest,
			MagFilter = .Nearest,
			MipmapFilter = .Nearest
		};

		switch (Renderer.Device.CreateSampler(depthSamplerDesc))
		{
		case .Ok(let sampler): mDepthSampler = sampler;
		case .Err: return .Err;
		}

		// Dynamic uniform buffers for per-decal data (one per frame-in-flight)
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc uniformDesc = .()
			{
				Label = "Decal Uniforms (Dynamic UBO)",
				Size = DecalUniformAlignment * MaxDecals,
				Usage = .Uniform,
				MemoryAccess = .CpuToGpu
			};

			switch (Renderer.Device.CreateBuffer(uniformDesc))
			{
			case .Ok(let buf): mDecalUniformBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private Result<void> CreateCubeGeometry()
	{
		// Unit cube centered at origin: 8 vertices, 36 indices (12 triangles)
		float[24] vertices = .(
			-0.5f, -0.5f, -0.5f,  // 0: left-bottom-near
			 0.5f, -0.5f, -0.5f,  // 1: right-bottom-near
			 0.5f,  0.5f, -0.5f,  // 2: right-top-near
			-0.5f,  0.5f, -0.5f,  // 3: left-top-near
			-0.5f, -0.5f,  0.5f,  // 4: left-bottom-far
			 0.5f, -0.5f,  0.5f,  // 5: right-bottom-far
			 0.5f,  0.5f,  0.5f,  // 6: right-top-far
			-0.5f,  0.5f,  0.5f   // 7: left-top-far
		);

		uint16[36] indices = .(
			// Front face (near, -Z)
			0, 2, 1,  0, 3, 2,
			// Back face (far, +Z)
			4, 5, 6,  4, 6, 7,
			// Left face (-X)
			0, 4, 7,  0, 7, 3,
			// Right face (+X)
			1, 2, 6,  1, 6, 5,
			// Bottom face (-Y)
			0, 1, 5,  0, 5, 4,
			// Top face (+Y)
			3, 7, 6,  3, 6, 2
		);

		BufferDesc vbDesc = .()
		{
			Label = "Decal Cube VB",
			Size = (uint64)(vertices.Count * sizeof(float)),
			Usage = .Vertex | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(vbDesc))
		{
		case .Ok(let buf): mCubeVertexBuffer = buf;
		case .Err: return .Err;
		}

		UploadBuffer(mCubeVertexBuffer, 0,
			Span<uint8>((uint8*)&vertices[0], vertices.Count * sizeof(float)));

		BufferDesc ibDesc = .()
		{
			Label = "Decal Cube IB",
			Size = (uint64)(indices.Count * sizeof(uint16)),
			Usage = .Index | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(ibDesc))
		{
		case .Ok(let buf): mCubeIndexBuffer = buf;
		case .Err: return .Err;
		}

		UploadBuffer(mCubeIndexBuffer, 0,
			Span<uint8>((uint8*)&indices[0], indices.Count * sizeof(uint16)));

		return .Ok;
	}

	private Result<void> CreateBindGroupLayouts()
	{
		// Set 0: Scene (camera uniforms + depth texture)
		BindGroupLayoutEntry[3] sceneEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer },   // CameraUniforms (b0)
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },             // DepthTexture (t0)
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }                     // DepthSampler (s0)
		);

		BindGroupLayoutDesc sceneLayoutDesc = .()
		{
			Label = "Decal Scene BindGroup Layout",
			Entries = sceneEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(sceneLayoutDesc))
		{
		case .Ok(let layout): mSceneBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Set 1: Per-decal (decal uniforms + albedo texture)
		BindGroupLayoutEntry[3] decalEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer, HasDynamicOffset = true },  // DecalUniforms (b0, dynamic)
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },  // AlbedoTexture (t0)
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }          // AlbedoSampler (s0)
		);

		BindGroupLayoutDesc decalLayoutDesc = .()
		{
			Label = "Decal Per-Decal BindGroup Layout",
			Entries = decalEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(decalLayoutDesc))
		{
		case .Ok(let layout): mDecalBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreatePipelines()
	{
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Pipeline layout: 2 bind groups
		IBindGroupLayout[2] layouts = .(mSceneBindGroupLayout, mDecalBindGroupLayout);
		PipelineLayoutDesc pipelineLayoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(pipelineLayoutDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		let shaderResult = Renderer.ShaderSystem.GetShaderPair("decal");
		if (shaderResult case .Err)
			return .Ok; // Non-fatal: shaders may not be compiled yet

		let shaders = shaderResult.Get();

		// Vertex layout: position only (Float3)
		VertexBufferLayout[1] vertexBuffers = .(
			.()
			{
				Stride = 12, // 3 floats
				StepMode = .Vertex,
				Attributes = VertexAttribute[1](
					.() { Format = .Float3, Offset = 0, ShaderLocation = 0 }
				)
			}
		);

		// Depth stencil: depth test enabled, write disabled, GreaterEqual compare
		// Back faces of the cube that are behind existing geometry pass the depth test
		DepthStencilState decalDepthState = .()
		{
			DepthTestEnabled = true,
			DepthWriteEnabled = false,
			DepthCompare = .GreaterEqual
		};

		// Create a pipeline per blend mode
		delegate void(BlendState, StringView, ref IRenderPipeline) createPipeline = scope (blendState, label, pipeline) => {
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, blendState)
			);

			RenderPipelineDesc renderDesc = .()
			{
				Label = scope :: $"Decal Pipeline ({label})",
				Layout = mPipelineLayout,
				Vertex = .()
				{
					Shader = .(shaders.vert.Module, "main"),
					Buffers = vertexBuffers
				},
				Fragment = .()
				{
					Shader = .(shaders.frag.Module, "main"),
					Targets = colorTargets
				},
				Primitive = .()
				{
					Topology = .TriangleList,
					FrontFace = .CCW,
					CullMode = .Front
				},
				DepthStencil = decalDepthState,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(renderDesc))
			{
			case .Ok(let createdPipeline): pipeline = createdPipeline;
			case .Err: // Non-fatal
			}
		};

		createPipeline(.AlphaBlend, "Alpha", ref mPipelineAlpha);
		createPipeline(.Additive, "Additive", ref mPipelineAdditive);
		createPipeline(.Multiply, "Multiply", ref mPipelineMultiply);

		return .Ok;
	}

	private void CreateCurveDecalResources()
	{
		if (Renderer.ShaderSystem == null || mSceneBindGroupLayout == null)
			return;

		let shaderResult = Renderer.ShaderSystem.GetShaderPair("curve_decal");
		if (shaderResult case .Err)
			return;

		let shaders = shaderResult.Get();

		// Curve decal per-decal bind group layout (same structure as box decal)
		BindGroupLayoutEntry[3] curveEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer, HasDynamicOffset = true },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDesc curveLayoutDesc = .()
		{
			Label = "Curve Decal BindGroup Layout",
			Entries = curveEntries
		};

		if (Renderer.Device.CreateBindGroupLayout(curveLayoutDesc) case .Ok(let bgLayout))
			mCurveDecalBindGroupLayout = bgLayout;
		else
			return;

		// Pipeline layout
		IBindGroupLayout[2] layouts = .(mSceneBindGroupLayout, mCurveDecalBindGroupLayout);
		PipelineLayoutDesc pipelineLayoutDesc = .(layouts);
		if (Renderer.Device.CreatePipelineLayout(pipelineLayoutDesc) case .Ok(let plLayout))
			mCurvePipelineLayout = plLayout;
		else
			return;

		// Vertex layout: Position (Float3) + TexCoord (Float2) + Normal (Float3) = 32 bytes
		VertexBufferLayout[1] vertexBuffers = .(
			.()
			{
				Stride = CurveDecalVertex.Stride,
				StepMode = .Vertex,
				Attributes = VertexAttribute[3](
					.() { Format = .Float3, Offset = 0, ShaderLocation = 0 },   // Position
					.() { Format = .Float2, Offset = 12, ShaderLocation = 1 },  // TexCoord
					.() { Format = .Float3, Offset = 20, ShaderLocation = 2 }   // Normal
				)
			}
		);

		DepthStencilState depthState = .()
		{
			DepthTestEnabled = true,
			DepthWriteEnabled = false,
			DepthCompare = .LessEqual
		};

		delegate void(BlendState, StringView, ref IRenderPipeline) createPipeline = scope (blendState, label, pipeline) => {
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, blendState)
			);

			RenderPipelineDesc renderDesc = .()
			{
				Label = scope :: $"Curve Decal Pipeline ({label})",
				Layout = mCurvePipelineLayout,
				Vertex = .()
				{
					Shader = .(shaders.vert.Module, "main"),
					Buffers = vertexBuffers
				},
				Fragment = .()
				{
					Shader = .(shaders.frag.Module, "main"),
					Targets = colorTargets
				},
				Primitive = .()
				{
					Topology = .TriangleList,
					FrontFace = .CCW,
					CullMode = .None // Double-sided for curve strips
				},
				DepthStencil = depthState,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			if (Renderer.Device.CreateRenderPipeline(renderDesc) case .Ok(let createdPipeline))
				pipeline = createdPipeline;
		};

		createPipeline(.AlphaBlend, "Alpha", ref mCurvePipelineAlpha);
		createPipeline(.Additive, "Additive", ref mCurvePipelineAdditive);
		createPipeline(.Multiply, "Multiply", ref mCurvePipelineMultiply);

		// Uniform buffers for curve decals
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc uniformDesc = .()
			{
				Label = "Curve Decal Uniforms",
				Size = CurveDecalUniformAlignment * MaxCurveDecals,
				Usage = .Uniform,
				MemoryAccess = .CpuToGpu
			};

			if (Renderer.Device.CreateBuffer(uniformDesc) case .Ok(let buf))
				mCurveUniformBuffers[i] = buf;
		}
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		bool hasBoxDecalPipeline = mPipelineAlpha != null || mPipelineAdditive != null || mPipelineMultiply != null;
		bool hasCurvePipeline = mCurvePipelineAlpha != null || mCurvePipelineAdditive != null || mCurvePipelineMultiply != null;

		if (!hasBoxDecalPipeline && !hasCurvePipeline)
			return;

		// Collect active box decals
		mActiveDecals.Clear();
		int32 decalIndex = 0;
		world.ForEachDecal(scope [&] (handle, proxy) =>
		{
			if (!proxy.IsActive || decalIndex >= MaxDecals)
				return;

			mActiveDecals.Add(.()
			{
				Handle = DecalProxyHandle() { Handle = handle },
				SortOrder = proxy.SortOrder,
				BlendMode = proxy.BlendMode,
				Index = decalIndex
			});

			decalIndex++;
		});

		// Collect active curve decals
		mActiveCurveDecals.Clear();
		mCurveMeshBuilder.Clear();
		int32 curveIndex = 0;
		world.ForEachCurveDecal(scope [&] (handle, proxy) =>
		{
			if (!proxy.IsActive || proxy.PointCount < 2 || curveIndex >= MaxCurveDecals)
				return;

			mCurveMeshBuilder.BuildStrip(&proxy);

			mActiveCurveDecals.Add(.()
			{
				Handle = CurveDecalProxyHandle() { Handle = handle },
				SortOrder = proxy.SortOrder,
				BlendMode = proxy.BlendMode,
				Index = curveIndex,
				MeshRange = (int32)mCurveMeshBuilder.Ranges.Length - 1
			});

			curveIndex++;
		});

		if (mActiveDecals.Count == 0 && mActiveCurveDecals.Count == 0)
			return;

		// Sort by SortOrder, then BlendMode for batching
		if (mActiveDecals.Count > 0)
			SortDecals();

		// Invalidate bind groups for this frame (depth texture may have changed)
		let frameIndex = Renderer.RenderFrameContext?.FrameIndex ?? 0;
		InvalidateBindGroups(frameIndex);

		// Upload per-decal uniforms to this frame's buffer
		if (mActiveDecals.Count > 0)
			UploadDecalUniforms(world, frameIndex);

		// Upload curve decal uniforms and geometry
		if (mActiveCurveDecals.Count > 0)
		{
			UploadCurveDecalUniforms(world, frameIndex);
			UploadCurveDecalGeometry(frameIndex);
		}

		let colorHandle = graph.GetResource("SceneColor");
		let depthHandle = graph.GetResource("SceneDepth");

		if (!colorHandle.IsValid || !depthHandle.IsValid)
			return;

		mDepthHandle = depthHandle;
		mViewWidth = view.Width;
		mViewHeight = view.Height;

		graph.AddGraphicsPass("DecalRender")
			.WriteColor(colorHandle, .Load, .Store)
			.ReadDepth(depthHandle)
			.NeverCull()
			.SetExecuteCallback(new [&] (encoder) => {
				ExecuteRenderPass(encoder);
			});
	}

	private void UploadDecalUniforms(RenderWorld world, int32 frameIndex)
	{
		let buffer = mDecalUniformBuffers[frameIndex];
		if (buffer == null)
			return;

		for (let entry in mActiveDecals)
		{
			let proxy = world.GetDecal(entry.Handle);
			if (proxy == null)
				continue;

			DecalUniforms uniforms = default;
			uniforms.WorldMatrix = proxy.GetWorldMatrix();
			uniforms.InvWorldMatrix = proxy.GetInvWorldMatrix();
			uniforms.DecalColor = proxy.Color;
			uniforms.AngleFadeStart = proxy.AngleFadeStart;
			uniforms.AngleFadeEnd = proxy.AngleFadeEnd;

			let offset = (uint64)entry.Index * DecalUniformAlignment;
			Renderer.Device.Queue.WriteMappedBuffer(
				buffer, offset,
				Span<uint8>((uint8*)&uniforms, DecalUniforms.Size)
			);
		}
	}

	private void UploadCurveDecalUniforms(RenderWorld world, int32 frameIndex)
	{
		let buffer = mCurveUniformBuffers[frameIndex];
		if (buffer == null)
			return;

		for (let entry in mActiveCurveDecals)
		{
			let proxy = world.GetCurveDecal(entry.Handle);
			if (proxy == null)
				continue;

			CurveDecalUniforms uniforms = .()
			{
				Color = proxy.Color,
				ProjectionDepth = proxy.ProjectionDepth,
				_Pad = default
			};

			let offset = (uint64)entry.Index * CurveDecalUniformAlignment;
			Renderer.Device.Queue.WriteMappedBuffer(
				buffer, offset,
				Span<uint8>((uint8*)&uniforms, CurveDecalUniforms.Size)
			);
		}
	}

	private void UploadCurveDecalGeometry(int32 frameIndex)
	{
		if (mCurveMeshBuilder.TotalVertexCount == 0)
			return;

		let vertexDataSize = (uint64)(mCurveMeshBuilder.TotalVertexCount * CurveDecalVertex.Stride);
		let indexDataSize = (uint64)(mCurveMeshBuilder.TotalIndexCount * sizeof(uint16));

		// Recreate buffers if too small
		if (mCurveVertexBuffers[frameIndex] == null || mCurveVertexBuffers[frameIndex].Size < vertexDataSize)
		{
			if (mCurveVertexBuffers[frameIndex] != null)
				delete mCurveVertexBuffers[frameIndex];

			BufferDesc vbDesc = .()
			{
				Label = "Curve Decal VB",
				Size = vertexDataSize,
				Usage = .Vertex,
				MemoryAccess = .CpuToGpu
			};

			if (Renderer.Device.CreateBuffer(vbDesc) case .Ok(let buf))
				mCurveVertexBuffers[frameIndex] = buf;
			else
				return;
		}

		if (mCurveIndexBuffers[frameIndex] == null || mCurveIndexBuffers[frameIndex].Size < indexDataSize)
		{
			if (mCurveIndexBuffers[frameIndex] != null)
				delete mCurveIndexBuffers[frameIndex];

			BufferDesc ibDesc = .()
			{
				Label = "Curve Decal IB",
				Size = indexDataSize,
				Usage = .Index,
				MemoryAccess = .CpuToGpu
			};

			if (Renderer.Device.CreateBuffer(ibDesc) case .Ok(let buf))
				mCurveIndexBuffers[frameIndex] = buf;
			else
				return;
		}

		// Upload vertex data
		let vb = mCurveVertexBuffers[frameIndex];
		if (vb != null)
		{
			let vertices = mCurveMeshBuilder.Vertices;
			Renderer.Device.Queue.WriteMappedBuffer(
				vb, 0,
				Span<uint8>((uint8*)vertices.Ptr, (int)vertexDataSize)
			);
		}

		// Upload index data
		let ib = mCurveIndexBuffers[frameIndex];
		if (ib != null)
		{
			let indices = mCurveMeshBuilder.Indices;
			Renderer.Device.Queue.WriteMappedBuffer(
				ib, 0,
				Span<uint8>((uint8*)indices.Ptr, (int)indexDataSize)
			);
		}
	}

	private void ExecuteRenderPass(IRenderPassEncoder encoder)
	{
		if (mViewWidth == 0 || mViewHeight == 0)
			return;

		encoder.SetViewport(0, 0, (float)mViewWidth, (float)mViewHeight, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, mViewWidth, mViewHeight);

		// Bind cube geometry
		encoder.SetVertexBuffer(0, mCubeVertexBuffer, 0);
		encoder.SetIndexBuffer(mCubeIndexBuffer, .UInt16, 0);

		// Get depth-only texture view for sampling
		let depthView = Renderer.RenderGraph?.GetDepthOnlyTextureView(mDepthHandle);
		if (depthView == null)
			return;

		// Get or create scene bind group
		let frameIndex = Renderer.RenderFrameContext?.FrameIndex ?? 0;
		let sceneBindGroup = GetOrCreateSceneBindGroup(frameIndex, depthView);
		if (sceneBindGroup == null)
			return;

		// Get decal bind group cache for this frame/view
		let bindGroupIndex = GetBindGroupIndex(frameIndex);
		let bindGroupCache = mDecalBindGroups[bindGroupIndex];

		// Render each decal
		for (let entry in mActiveDecals)
		{
			let proxy = Renderer.ActiveWorld?.GetDecal(entry.Handle);
			if (proxy == null)
				continue;

			// Select pipeline by blend mode
			IRenderPipeline pipeline = null;
			switch (entry.BlendMode)
			{
			case .Alpha: pipeline = mPipelineAlpha;
			case .Additive: pipeline = mPipelineAdditive;
			case .Multiply: pipeline = mPipelineMultiply;
			}

			if (pipeline == null)
				continue;

			encoder.SetPipeline(pipeline);

			// Set scene bind group (set 0)
			encoder.SetBindGroup(0, sceneBindGroup, default);

			// Create per-decal bind group (set 1), cached until next frame
			let decalBindGroup = CreateDecalBindGroup(proxy, entry.Index, frameIndex);
			if (decalBindGroup == null)
				continue;
			bindGroupCache.Add(decalBindGroup);

			uint32[1] dynamicOffsets = .((uint32)((int64)entry.Index * (int64)DecalUniformAlignment));
			encoder.SetBindGroup(1, decalBindGroup, dynamicOffsets);

			encoder.DrawIndexed(36, 1, 0, 0, 0);
			Renderer.Stats.DrawCalls++;
		}

		// Render curve decals
		if (mActiveCurveDecals.Count > 0 && mCurveVertexBuffers[frameIndex] != null && mCurveIndexBuffers[frameIndex] != null)
		{
			encoder.SetVertexBuffer(0, mCurveVertexBuffers[frameIndex], 0);
			encoder.SetIndexBuffer(mCurveIndexBuffers[frameIndex], .UInt16, 0);

			let curveBindGroupCache = mCurveDecalBindGroups[bindGroupIndex];

			for (let entry in mActiveCurveDecals)
			{
				let proxy = Renderer.ActiveWorld?.GetCurveDecal(entry.Handle);
				if (proxy == null)
					continue;

				if (entry.MeshRange < 0 || entry.MeshRange >= mCurveMeshBuilder.Ranges.Length)
					continue;

				let range = mCurveMeshBuilder.Ranges[entry.MeshRange];
				if (range.IndexCount == 0)
					continue;

				// Select curve decal pipeline by blend mode
				IRenderPipeline curvePipeline = null;
				switch (entry.BlendMode)
				{
				case .Alpha: curvePipeline = mCurvePipelineAlpha;
				case .Additive: curvePipeline = mCurvePipelineAdditive;
				case .Multiply: curvePipeline = mCurvePipelineMultiply;
				}

				if (curvePipeline == null)
					continue;

				encoder.SetPipeline(curvePipeline);
				encoder.SetBindGroup(0, sceneBindGroup, default);

				let curveBindGroup = CreateCurveDecalBindGroup(proxy, entry.Index, frameIndex);
				if (curveBindGroup == null)
					continue;
				curveBindGroupCache.Add(curveBindGroup);

				uint32[1] dynamicOffsets = .((uint32)((int64)entry.Index * (int64)CurveDecalUniformAlignment));
				encoder.SetBindGroup(1, curveBindGroup, dynamicOffsets);

				encoder.DrawIndexed((uint32)range.IndexCount, 1, (uint32)range.IndexStart, range.VertexStart, 0);
				Renderer.Stats.DrawCalls++;
			}
		}
	}

	private IBindGroup CreateCurveDecalBindGroup(CurveDecalProxy* proxy, int32 index, int32 frameIndex)
	{
		let buffer = mCurveUniformBuffers[frameIndex];
		if (mCurveDecalBindGroupLayout == null || buffer == null)
			return null;

		ITextureView textureView;
		if (proxy.AlbedoTexture != null)
			textureView = proxy.AlbedoTexture;
		else
			textureView = mDefaultTextureView;

		ISampler sampler;
		if (proxy.Sampler != null)
			sampler = proxy.Sampler;
		else
			sampler = mLinearClampSampler;

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, buffer, 0, CurveDecalUniformAlignment),
			BindGroupEntry.Texture(0, textureView),
			BindGroupEntry.Sampler(0, sampler)
		);

		BindGroupDesc bgDesc = .()
		{
			Label = "Curve Decal BindGroup",
			Layout = mCurveDecalBindGroupLayout,
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): return bg;
		case .Err: return null;
		}
	}

	private IBindGroup GetOrCreateSceneBindGroup(int32 frameIndex, ITextureView depthView)
	{
		let bindGroupIndex = GetBindGroupIndex(frameIndex);

		if (mSceneBindGroups[bindGroupIndex] != null)
			return mSceneBindGroups[bindGroupIndex];

		let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
		if (cameraBuffer == null || mSceneBindGroupLayout == null || mDepthSampler == null)
			return null;

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Texture(0, depthView, .DepthStencilReadOnly),
			BindGroupEntry.Sampler(0, mDepthSampler)
		);

		BindGroupDesc bgDesc = .()
		{
			Label = "Decal Scene BindGroup",
			Layout = mSceneBindGroupLayout,
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg):
			mSceneBindGroups[bindGroupIndex] = bg;
			return bg;
		case .Err:
			return null;
		}
	}

	private IBindGroup CreateDecalBindGroup(DecalProxy* proxy, int32 index, int32 frameIndex)
	{
		let buffer = mDecalUniformBuffers[frameIndex];
		if (mDecalBindGroupLayout == null || buffer == null)
			return null;

		ITextureView textureView;
		if (proxy.AlbedoTexture != null)
			textureView = proxy.AlbedoTexture;
		else
			textureView = mDefaultTextureView;

		ISampler sampler;
		if (proxy.Sampler != null)
			sampler = proxy.Sampler;
		else
			sampler = mLinearClampSampler;

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, buffer, 0, DecalUniformAlignment),
			BindGroupEntry.Texture(0, textureView),
			BindGroupEntry.Sampler(0, sampler)
		);

		BindGroupDesc bgDesc = .()
		{
			Label = "Decal Per-Decal BindGroup",
			Layout = mDecalBindGroupLayout,
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): return bg;
		case .Err: return null;
		}
	}

	private void InvalidateBindGroups(int32 frameIndex)
	{
		for (int32 viewIdx = 0; viewIdx < RenderConfig.MaxViews; viewIdx++)
		{
			let bindGroupIndex = frameIndex * RenderConfig.MaxViews + viewIdx;
			if (mSceneBindGroups[bindGroupIndex] != null)
			{
				delete mSceneBindGroups[bindGroupIndex];
				mSceneBindGroups[bindGroupIndex] = null;
			}

			if (mDecalBindGroups[bindGroupIndex] != null)
			{
				for (let bg in mDecalBindGroups[bindGroupIndex])
					delete bg;
				mDecalBindGroups[bindGroupIndex].Clear();
			}

			if (mCurveDecalBindGroups[bindGroupIndex] != null)
			{
				for (let bg in mCurveDecalBindGroups[bindGroupIndex])
					delete bg;
				mCurveDecalBindGroups[bindGroupIndex].Clear();
			}
		}
	}

	private void SortDecals()
	{
		// Insertion sort (stable, good for small counts)
		for (int i = 1; i < mActiveDecals.Count; i++)
		{
			let key = mActiveDecals[i];
			var j = i - 1;
			while (j >= 0 && CompareDecals(mActiveDecals[j], key) > 0)
			{
				mActiveDecals[j + 1] = mActiveDecals[j];
				j--;
			}
			mActiveDecals[j + 1] = key;
		}
	}

	private int CompareDecals(DecalSortEntry a, DecalSortEntry b)
	{
		if (a.SortOrder != b.SortOrder)
			return a.SortOrder < b.SortOrder ? -1 : 1;
		return (int)a.BlendMode - (int)b.BlendMode;
	}

	struct DecalSortEntry
	{
		public DecalProxyHandle Handle;
		public int32 SortOrder;
		public DecalBlendMode BlendMode;
		public int32 Index;
	}

	struct CurveDecalSortEntry
	{
		public CurveDecalProxyHandle Handle;
		public int32 SortOrder;
		public DecalBlendMode BlendMode;
		public int32 Index;       // Index in active curve decals (for uniforms)
		public int32 MeshRange;   // Index in mesh builder ranges
	}
}
