namespace RHIMSAA;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell.Input;
using SampleFramework;

/// Vertex structure with position and color
[CRepr]
struct Vertex
{
	public float[2] Position;
	public float[3] Color;

	public this(float x, float y, float r, float g, float b)
	{
		Position = .(x, y);
		Color = .(r, g, b);
	}
}

/// Uniform buffer data
[CRepr]
struct Uniforms
{
	public Matrix Transform;
}

/// MSAA sample - demonstrates multisampled rendering and ResolveTexture.
/// Renders a rotating triangle to a 4x MSAA texture, then resolves to display.
/// Press SPACE to toggle between MSAA (smooth edges) and no MSAA (aliased).
class MSAASample : RHISampleApp
{
	private const uint32 MSAA_SAMPLES = 4;

	// MSAA render targets
	private ITexture mMsaaTexture;
	private ITextureView mMsaaTextureView;
	private ITexture mResolveTexture;
	private ITextureView mResolveTextureView;

	// Rendering resources
	private IBuffer mVertexBuffer;
	private IBuffer mUniformBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mMsaaPipeline;
	private IRenderPipeline mNoMsaaPipeline;

	// Full-screen quad for displaying resolve result
	private IBuffer mQuadVertexBuffer;
	private IShaderModule mQuadVertShader;
	private IShaderModule mQuadFragShader;
	private IBindGroupLayout mQuadBindGroupLayout;
	private IBindGroup mQuadBindGroup;
	private IPipelineLayout mQuadPipelineLayout;
	private IRenderPipeline mQuadPipeline;
	private ISampler mSampler;

	private bool mUseMSAA = true;

	public this() : base(.()
		{
			Title = "RHI MSAA",
			Width = 800,
			Height = 600,
			ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateMsaaTargets())
			return false;

		if (!CreateTriangleResources())
			return false;

		if (!CreateQuadResources())
			return false;

		Console.WriteLine("Press SPACE to toggle MSAA (currently ON - smooth edges)");
		return true;
	}

	private bool CreateMsaaTargets()
	{
		// Create 4x MSAA render target
		TextureDescriptor msaaDesc = TextureDescriptor.Texture2D(
			SwapChain.Width, SwapChain.Height,
			SwapChain.Format, .RenderTarget | .CopySrc  // CopySrc needed for resolve
		);
		msaaDesc.SampleCount = MSAA_SAMPLES;

		if (Device.CreateTexture(&msaaDesc) not case .Ok(let msaaTex))
			return false;
		mMsaaTexture = msaaTex;

		TextureViewDescriptor viewDesc = .()
		{
			Format = SwapChain.Format,
			Dimension = .Texture2D,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1
		};
		if (Device.CreateTextureView(mMsaaTexture, &viewDesc) not case .Ok(let msaaView))
			return false;
		mMsaaTextureView = msaaView;

		// Create single-sample resolve target (also used as texture for display)
		TextureDescriptor resolveDesc = TextureDescriptor.Texture2D(
			SwapChain.Width, SwapChain.Height,
			SwapChain.Format, .RenderTarget | .Sampled | .CopyDst  // CopyDst needed for resolve
		);

		if (Device.CreateTexture(&resolveDesc) not case .Ok(let resolveTex))
			return false;
		mResolveTexture = resolveTex;

		if (Device.CreateTextureView(mResolveTexture, &viewDesc) not case .Ok(let resolveView))
			return false;
		mResolveTextureView = resolveView;

		Console.WriteLine(scope $"MSAA targets created: {SwapChain.Width}x{SwapChain.Height}, {MSAA_SAMPLES}x samples");
		return true;
	}

	private bool CreateTriangleResources()
	{
		// Triangle vertices
		Vertex[3] vertices = .(
			.(0.0f, -0.6f, 1.0f, 0.0f, 0.0f),   // Top - Red
			.(0.6f, 0.6f, 0.0f, 1.0f, 0.0f),    // Bottom right - Green
			.(-0.6f, 0.6f, 0.0f, 0.0f, 1.0f)    // Bottom left - Blue
		);

		BufferDescriptor vertexDesc = .()
		{
			Size = (uint64)(sizeof(Vertex) * vertices.Count),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&vertexDesc) not case .Ok(let vb))
			return false;
		mVertexBuffer = vb;
		Device.Queue.WriteBuffer(mVertexBuffer, 0, .((uint8*)&vertices, (int)vertexDesc.Size));

		// Uniform buffer
		BufferDescriptor uniformDesc = .()
		{
			Size = (uint64)sizeof(Uniforms),
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&uniformDesc) not case .Ok(let ub))
			return false;
		mUniformBuffer = ub;

		// Shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/msaa");
		if (shaderResult case .Err)
			return false;
		(mVertShader, mFragShader) = shaderResult.Get();

		// Bind group layout
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		// Bind group
		BindGroupEntry[1] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mBindGroup = group;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		// Vertex layout
		VertexAttribute[2] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),
			.(VertexFormat.Float3, 8, 1)
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// MSAA pipeline (4x samples)
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));
		RenderPipelineDescriptor msaaPipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(mVertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(mFragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			Multisample = .() { Count = MSAA_SAMPLES, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&msaaPipelineDesc) not case .Ok(let msaaPipeline))
			return false;
		mMsaaPipeline = msaaPipeline;

		// No-MSAA pipeline (1 sample, direct to resolve target)
		msaaPipelineDesc.Multisample.Count = 1;
		if (Device.CreateRenderPipeline(&msaaPipelineDesc) not case .Ok(let noMsaaPipeline))
			return false;
		mNoMsaaPipeline = noMsaaPipeline;

		Console.WriteLine("Triangle resources created");
		return true;
	}

	private bool CreateQuadResources()
	{
		// Full-screen quad vertices (position + uv) - 6 vertices * 4 floats = 24 floats
		float[24] quadVerts = .(
			-1.0f, -1.0f, 0.0f, 1.0f, // Bottom-left
			 1.0f, -1.0f, 1.0f, 1.0f, // Bottom-right
			 1.0f,  1.0f, 1.0f, 0.0f, // Top-right
			-1.0f, -1.0f, 0.0f, 1.0f, // Bottom-left
			 1.0f,  1.0f, 1.0f, 0.0f, // Top-right
			-1.0f,  1.0f, 0.0f, 0.0f  // Top-left
		);

		BufferDescriptor quadDesc = .()
		{
			Size = (uint64)(sizeof(float) * quadVerts.Count),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&quadDesc) not case .Ok(let qvb))
			return false;
		mQuadVertexBuffer = qvb;
		Device.Queue.WriteBuffer(mQuadVertexBuffer, 0, .((uint8*)&quadVerts, (int)quadDesc.Size));

		// Quad shaders (inline compile)
		String quadVertSrc = """
			struct VSOutput {
			    float4 position : SV_Position;
			    float2 uv : TEXCOORD0;
			};
			VSOutput main(float2 pos : POSITION, float2 uv : TEXCOORD0) {
			    VSOutput output;
			    output.position = float4(pos, 0.0, 1.0);
			    output.uv = uv;
			    return output;
			}
			""";

		String quadFragSrc = """
			Texture2D tex : register(t0);
			SamplerState samp : register(s0);
			float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target {
			    return tex.Sample(samp, uv);
			}
			""";

		if (ShaderUtils.CompileShader(Device, quadVertSrc, "main", .Vertex) not case .Ok(let qvs))
			return false;
		mQuadVertShader = qvs;

		if (ShaderUtils.CompileShader(Device, quadFragSrc, "main", .Fragment) not case .Ok(let qfs))
			return false;
		mQuadFragShader = qfs;

		// Sampler
		SamplerDescriptor samplerDesc = .();
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return false;
		mSampler = sampler;

		// Bind group layout for texture+sampler
		// Binding number = HLSL register number; RHI applies shifts automatically
		BindGroupLayoutEntry[2] quadLayoutEntries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment), // t0
			BindGroupLayoutEntry.Sampler(0, .Fragment)         // s0
		);
		BindGroupLayoutDescriptor quadLayoutDesc = .(quadLayoutEntries);
		if (Device.CreateBindGroupLayout(&quadLayoutDesc) not case .Ok(let quadLayout))
			return false;
		mQuadBindGroupLayout = quadLayout;

		// Bind group
		BindGroupEntry[2] quadBindEntries = .(
			BindGroupEntry.Texture(0, mResolveTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor quadBindDesc = .(mQuadBindGroupLayout, quadBindEntries);
		if (Device.CreateBindGroup(&quadBindDesc) not case .Ok(let quadGroup))
			return false;
		mQuadBindGroup = quadGroup;

		// Pipeline layout
		IBindGroupLayout[1] quadLayouts = .(mQuadBindGroupLayout);
		PipelineLayoutDescriptor quadPipelineLayoutDesc = .(quadLayouts);
		if (Device.CreatePipelineLayout(&quadPipelineLayoutDesc) not case .Ok(let quadPipelineLayout))
			return false;
		mQuadPipelineLayout = quadPipelineLayout;

		// Vertex layout
		VertexAttribute[2] quadAttributes = .(
			.(VertexFormat.Float2, 0, 0),  // position
			.(VertexFormat.Float2, 8, 1)   // uv
		);
		VertexBufferLayout[1] quadVertexBuffers = .(
			.((uint64)(sizeof(float) * 4), quadAttributes)
		);

		// Quad pipeline
		ColorTargetState[1] quadColorTargets = .(.(SwapChain.Format));
		RenderPipelineDescriptor quadPipelineDesc = .()
		{
			Layout = mQuadPipelineLayout,
			Vertex = .()
			{
				Shader = .(mQuadVertShader, "main"),
				Buffers = quadVertexBuffers
			},
			Fragment = .()
			{
				Shader = .(mQuadFragShader, "main"),
				Targets = quadColorTargets
			},
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&quadPipelineDesc) not case .Ok(let quadPipeline))
			return false;
		mQuadPipeline = quadPipeline;

		Console.WriteLine("Quad resources created");
		return true;
	}

	protected override void OnKeyDown(KeyCode key)
	{
		if (key == .Space)
		{
			mUseMSAA = !mUseMSAA;
			Console.WriteLine(scope $"MSAA: {mUseMSAA ? "ON (smooth edges)" : "OFF (aliased)"}");
		}
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		float rotation = TotalTime * 1.0f;
		Uniforms uniforms = .() { Transform = Matrix.CreateRotationZ(rotation) };
		Device.Queue.WriteBuffer(mUniformBuffer, 0, .((uint8*)&uniforms, sizeof(Uniforms)));
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		if (mUseMSAA)
		{
			// Render to MSAA target
			RenderPassColorAttachment[1] msaaAttachments = .(.(mMsaaTextureView)
				{
					LoadOp = .Clear,
					StoreOp = .Store,
					ClearValue = .(0.1f, 0.1f, 0.15f, 1.0f)
				});
			RenderPassDescriptor msaaPassDesc = .(msaaAttachments);

			let msaaPass = encoder.BeginRenderPass(&msaaPassDesc);
			if (msaaPass != null)
			{
				msaaPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
				msaaPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);
				msaaPass.SetPipeline(mMsaaPipeline);
				msaaPass.SetBindGroup(0, mBindGroup);
				msaaPass.SetVertexBuffer(0, mVertexBuffer, 0);
				msaaPass.Draw(3, 1, 0, 0);
				msaaPass.End();
				delete msaaPass;
			}

			// Resolve MSAA to single-sample texture
			encoder.ResolveTexture(mMsaaTexture, mResolveTexture);
		}
		else
		{
			// Render directly to resolve target (no MSAA)
			RenderPassColorAttachment[1] noMsaaAttachments = .(.(mResolveTextureView)
				{
					LoadOp = .Clear,
					StoreOp = .Store,
					ClearValue = .(0.1f, 0.1f, 0.15f, 1.0f)
				});
			RenderPassDescriptor noMsaaPassDesc = .(noMsaaAttachments);

			let noMsaaPass = encoder.BeginRenderPass(&noMsaaPassDesc);
			if (noMsaaPass != null)
			{
				noMsaaPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
				noMsaaPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);
				noMsaaPass.SetPipeline(mNoMsaaPipeline);
				noMsaaPass.SetBindGroup(0, mBindGroup);
				noMsaaPass.SetVertexBuffer(0, mVertexBuffer, 0);
				noMsaaPass.Draw(3, 1, 0, 0);
				noMsaaPass.End();
				delete noMsaaPass;
			}

			// Transition resolve texture to shader read
			encoder.TextureBarrier(mResolveTexture, .ColorAttachment, .ShaderReadOnly);
		}

		// Draw resolved texture to swap chain
		let swapTextureView = SwapChain.CurrentTextureView;
		RenderPassColorAttachment[1] finalAttachments = .(.(swapTextureView)
			{
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = .(0.0f, 0.0f, 0.0f, 1.0f)
			});
		RenderPassDescriptor finalPassDesc = .(finalAttachments);

		let finalPass = encoder.BeginRenderPass(&finalPassDesc);
		if (finalPass != null)
		{
			finalPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
			finalPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);
			finalPass.SetPipeline(mQuadPipeline);
			finalPass.SetBindGroup(0, mQuadBindGroup);
			finalPass.SetVertexBuffer(0, mQuadVertexBuffer, 0);
			finalPass.Draw(6, 1, 0, 0);
			finalPass.End();
			delete finalPass;
		}

		return true; // Skip default render pass
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we use OnRenderCustom for full control
	}

	protected override void OnCleanup()
	{
		if (mQuadPipeline != null) delete mQuadPipeline;
		if (mQuadPipelineLayout != null) delete mQuadPipelineLayout;
		if (mQuadBindGroup != null) delete mQuadBindGroup;
		if (mQuadBindGroupLayout != null) delete mQuadBindGroupLayout;
		if (mQuadFragShader != null) delete mQuadFragShader;
		if (mQuadVertShader != null) delete mQuadVertShader;
		if (mQuadVertexBuffer != null) delete mQuadVertexBuffer;
		if (mSampler != null) delete mSampler;

		if (mNoMsaaPipeline != null) delete mNoMsaaPipeline;
		if (mMsaaPipeline != null) delete mMsaaPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroup != null) delete mBindGroup;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mUniformBuffer != null) delete mUniformBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;

		if (mResolveTextureView != null) delete mResolveTextureView;
		if (mResolveTexture != null) delete mResolveTexture;
		if (mMsaaTextureView != null) delete mMsaaTextureView;
		if (mMsaaTexture != null) delete mMsaaTexture;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope MSAASample();
		return app.Run();
	}
}
