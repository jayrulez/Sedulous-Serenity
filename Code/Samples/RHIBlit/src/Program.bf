namespace RHIBlit;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell.Input;
using RHI.SampleFramework;

/// Uniform for quad positioning
[CRepr]
struct QuadUniforms
{
	public float[4] QuadRect;  // x, y, width, height in NDC
}

/// Blit sample - demonstrates the Blit() command for texture scaling.
/// Renders a rotating pattern to a small texture, then blits it to a larger texture.
/// Shows both the original (small) and blitted (scaled up) textures side by side.
class BlitSample : RHISampleApp
{
	private const uint32 SMALL_SIZE = 64;
	private const uint32 LARGE_SIZE = 256;

	// Source render target (small)
	private ITexture mSmallTexture;
	private ITextureView mSmallTextureView;

	// Destination texture (large, after blit)
	private ITexture mLargeTexture;
	private ITextureView mLargeTextureView;

	// Pattern rendering resources
	private IBuffer mPatternVertexBuffer;
	private IBuffer mPatternUniformBuffer;
	private IShaderModule mPatternVertShader;
	private IShaderModule mPatternFragShader;
	private IBindGroupLayout mPatternBindGroupLayout;
	private IBindGroup mPatternBindGroup;
	private IPipelineLayout mPatternPipelineLayout;
	private IRenderPipeline mPatternPipeline;

	// Display quad resources
	private IBuffer mLeftQuadUniformBuffer;
	private IBuffer mRightQuadUniformBuffer;
	private ISampler mSampler;
	private IShaderModule mBlitVertShader;
	private IShaderModule mBlitFragShader;
	private IBindGroupLayout mBlitBindGroupLayout;
	private IBindGroup mSmallBindGroup;
	private IBindGroup mLargeBindGroup;
	private IPipelineLayout mBlitPipelineLayout;
	private IRenderPipeline mBlitPipeline;

	public this() : base(.()
		{
			Title = "RHI Blit",
			Width = 800,
			Height = 600,
			ClearColor = .(0.1f, 0.1f, 0.12f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateTextures())
			return false;

		if (!CreatePatternResources())
			return false;

		if (!CreateDisplayResources())
			return false;

		Console.WriteLine("Blit sample: Left = original (64x64), Right = blitted (256x256)");
		return true;
	}

	private bool CreateTextures()
	{
		// Small render target
		TextureDescriptor smallDesc = TextureDescriptor.Texture2D(
			SMALL_SIZE, SMALL_SIZE, .RGBA8Unorm, .RenderTarget | .Sampled | .CopySrc
		);
		if (Device.CreateTexture(&smallDesc) not case .Ok(let smallTex))
			return false;
		mSmallTexture = smallTex;

		TextureViewDescriptor viewDesc = .()
		{
			Format = .RGBA8Unorm,
			Dimension = .Texture2D,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1
		};
		if (Device.CreateTextureView(mSmallTexture, &viewDesc) not case .Ok(let smallView))
			return false;
		mSmallTextureView = smallView;

		// Large destination texture
		TextureDescriptor largeDesc = TextureDescriptor.Texture2D(
			LARGE_SIZE, LARGE_SIZE, .RGBA8Unorm, .Sampled | .CopyDst
		);
		if (Device.CreateTexture(&largeDesc) not case .Ok(let largeTex))
			return false;
		mLargeTexture = largeTex;

		if (Device.CreateTextureView(mLargeTexture, &viewDesc) not case .Ok(let largeView))
			return false;
		mLargeTextureView = largeView;

		Console.WriteLine(scope $"Textures created: {SMALL_SIZE}x{SMALL_SIZE} -> {LARGE_SIZE}x{LARGE_SIZE}");
		return true;
	}

	private bool CreatePatternResources()
	{
		// Triangle vertices for pattern
		float[15] vertices = .(
			 0.0f, -0.7f,   1.0f, 0.3f, 0.3f,  // Top - Red
			 0.7f,  0.7f,   0.3f, 1.0f, 0.3f,  // Bottom right - Green
			-0.7f,  0.7f,   0.3f, 0.3f, 1.0f   // Bottom left - Blue
		);

		BufferDescriptor vertexDesc = .()
		{
			Size = (uint64)(sizeof(float) * vertices.Count),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&vertexDesc) not case .Ok(let vb))
			return false;
		mPatternVertexBuffer = vb;
		Device.Queue.WriteBuffer(mPatternVertexBuffer, 0, .((uint8*)&vertices, (int)vertexDesc.Size));

		// Uniform buffer
		BufferDescriptor uniformDesc = .()
		{
			Size = 64, // Matrix4x4
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&uniformDesc) not case .Ok(let ub))
			return false;
		mPatternUniformBuffer = ub;

		// Compile pattern shaders inline
		String patternVertSrc = """
			struct VSOutput { float4 position : SV_Position; float3 color : COLOR0; };
			cbuffer Uniforms : register(b0) { float4x4 transform; };
			VSOutput main(float2 pos : POSITION, float3 color : COLOR0) {
			    VSOutput o;
			    o.position = mul(transform, float4(pos, 0, 1));
			    o.color = color;
			    return o;
			}
			""";

		String patternFragSrc = """
			float4 main(float4 pos : SV_Position, float3 color : COLOR0) : SV_Target {
			    return float4(color, 1.0);
			}
			""";

		if (ShaderUtils.CompileShader(Device, patternVertSrc, "main", .Vertex) not case .Ok(let pvs))
			return false;
		mPatternVertShader = pvs;

		if (ShaderUtils.CompileShader(Device, patternFragSrc, "main", .Fragment) not case .Ok(let pfs))
			return false;
		mPatternFragShader = pfs;

		// Bind group layout
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor layoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&layoutDesc) not case .Ok(let layout))
			return false;
		mPatternBindGroupLayout = layout;

		// Bind group
		BindGroupEntry[1] bindEntries = .(
			BindGroupEntry.Buffer(0, mPatternUniformBuffer)
		);
		BindGroupDescriptor bindDesc = .(mPatternBindGroupLayout, bindEntries);
		if (Device.CreateBindGroup(&bindDesc) not case .Ok(let bg))
			return false;
		mPatternBindGroup = bg;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mPatternBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPatternPipelineLayout = pipelineLayout;

		// Pipeline
		VertexAttribute[2] vertexAttrs = .(
			.(VertexFormat.Float2, 0, 0),
			.(VertexFormat.Float3, 8, 1)
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)(sizeof(float) * 5), vertexAttrs)
		);

		ColorTargetState[1] colorTargets = .(.(.RGBA8Unorm));
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPatternPipelineLayout,
			Vertex = .()
			{
				Shader = .(mPatternVertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(mPatternFragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mPatternPipeline = pipeline;

		Console.WriteLine("Pattern resources created");
		return true;
	}

	private bool CreateDisplayResources()
	{
		// Uniform buffers for quad positioning (one per quad to avoid write conflicts)
		BufferDescriptor uniformDesc = .()
		{
			Size = (uint64)sizeof(QuadUniforms),
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&uniformDesc) not case .Ok(let leftUb))
			return false;
		mLeftQuadUniformBuffer = leftUb;

		if (Device.CreateBuffer(&uniformDesc) not case .Ok(let rightUb))
			return false;
		mRightQuadUniformBuffer = rightUb;

		// Initialize quad positions (these don't change)
		QuadUniforms leftQuad = .() { QuadRect = .(-0.9f, -0.4f, 0.4f, 0.8f) };
		QuadUniforms rightQuad = .() { QuadRect = .(0.1f, -0.4f, 0.8f, 0.8f) };
		Device.Queue.WriteBuffer(mLeftQuadUniformBuffer, 0, .((uint8*)&leftQuad, sizeof(QuadUniforms)));
		Device.Queue.WriteBuffer(mRightQuadUniformBuffer, 0, .((uint8*)&rightQuad, sizeof(QuadUniforms)));

		// Sampler
		SamplerDescriptor samplerDesc = .()
		{
			MinFilter = .Linear,
			MagFilter = .Linear
		};
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return false;
		mSampler = sampler;

		// Shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/blit");
		if (shaderResult case .Err)
			return false;
		(mBlitVertShader, mBlitFragShader) = shaderResult.Get();

		// Bind group layout
		// Binding number = HLSL register number; RHI applies shifts automatically
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),    // b0
			BindGroupLayoutEntry.SampledTexture(0, .Fragment), // t0
			BindGroupLayoutEntry.Sampler(0, .Fragment)         // s0
		);
		BindGroupLayoutDescriptor layoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&layoutDesc) not case .Ok(let layout))
			return false;
		mBlitBindGroupLayout = layout;

		// Bind groups for each texture (each with its own uniform buffer)
		BindGroupEntry[3] smallEntries = .(
			BindGroupEntry.Buffer(0, mLeftQuadUniformBuffer),
			BindGroupEntry.Texture(0, mSmallTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor smallBindDesc = .(mBlitBindGroupLayout, smallEntries);
		if (Device.CreateBindGroup(&smallBindDesc) not case .Ok(let smallBg))
			return false;
		mSmallBindGroup = smallBg;

		BindGroupEntry[3] largeEntries = .(
			BindGroupEntry.Buffer(0, mRightQuadUniformBuffer),
			BindGroupEntry.Texture(0, mLargeTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor largeBindDesc = .(mBlitBindGroupLayout, largeEntries);
		if (Device.CreateBindGroup(&largeBindDesc) not case .Ok(let largeBg))
			return false;
		mLargeBindGroup = largeBg;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBlitBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mBlitPipelineLayout = pipelineLayout;

		// Pipeline (no vertex buffer, uses SV_VertexID)
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mBlitPipelineLayout,
			Vertex = .()
			{
				Shader = .(mBlitVertShader, "main"),
				Buffers = .()
			},
			Fragment = .()
			{
				Shader = .(mBlitFragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mBlitPipeline = pipeline;

		Console.WriteLine("Display resources created");
		return true;
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Update pattern transform
		float rotation = TotalTime * 2.0f;
		Matrix transform = Matrix.CreateRotationZ(rotation);
		Device.Queue.WriteBuffer(mPatternUniformBuffer, 0, .((uint8*)&transform, sizeof(Matrix)));

		// Render pattern to small texture
		RenderPassColorAttachment[1] patternAttachments = .(.(mSmallTextureView)
			{
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = .(0.15f, 0.15f, 0.2f, 1.0f)
			});
		RenderPassDescriptor patternPassDesc = .(patternAttachments);

		let patternPass = encoder.BeginRenderPass(&patternPassDesc);
		if (patternPass != null)
		{
			patternPass.SetViewport(0, 0, SMALL_SIZE, SMALL_SIZE, 0, 1);
			patternPass.SetScissorRect(0, 0, SMALL_SIZE, SMALL_SIZE);
			patternPass.SetPipeline(mPatternPipeline);
			patternPass.SetBindGroup(0, mPatternBindGroup);
			patternPass.SetVertexBuffer(0, mPatternVertexBuffer, 0);
			patternPass.Draw(3, 1, 0, 0);
			patternPass.End();
			delete patternPass;
		}

		// Blit small texture to large texture (with scaling and filtering)
		encoder.Blit(mSmallTexture, mLargeTexture);

		// Render both textures to swap chain for comparison
		let swapTextureView = SwapChain.CurrentTextureView;
		RenderPassColorAttachment[1] displayAttachments = .(.(swapTextureView)
			{
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = .(0.1f, 0.1f, 0.12f, 1.0f)
			});
		RenderPassDescriptor displayPassDesc = .(displayAttachments);

		let displayPass = encoder.BeginRenderPass(&displayPassDesc);
		if (displayPass != null)
		{
			displayPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
			displayPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);
			displayPass.SetPipeline(mBlitPipeline);

			// Draw small texture on left (original)
			displayPass.SetBindGroup(0, mSmallBindGroup);
			displayPass.Draw(6, 1, 0, 0);

			// Draw large texture on right (after blit)
			displayPass.SetBindGroup(0, mLargeBindGroup);
			displayPass.Draw(6, 1, 0, 0);

			displayPass.End();
			delete displayPass;
		}

		return true; // Skip default render pass
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we use OnRenderCustom
	}

	protected override void OnCleanup()
	{
		if (mBlitPipeline != null) delete mBlitPipeline;
		if (mBlitPipelineLayout != null) delete mBlitPipelineLayout;
		if (mLargeBindGroup != null) delete mLargeBindGroup;
		if (mSmallBindGroup != null) delete mSmallBindGroup;
		if (mBlitBindGroupLayout != null) delete mBlitBindGroupLayout;
		if (mBlitFragShader != null) delete mBlitFragShader;
		if (mBlitVertShader != null) delete mBlitVertShader;
		if (mSampler != null) delete mSampler;
		if (mRightQuadUniformBuffer != null) delete mRightQuadUniformBuffer;
		if (mLeftQuadUniformBuffer != null) delete mLeftQuadUniformBuffer;

		if (mPatternPipeline != null) delete mPatternPipeline;
		if (mPatternPipelineLayout != null) delete mPatternPipelineLayout;
		if (mPatternBindGroup != null) delete mPatternBindGroup;
		if (mPatternBindGroupLayout != null) delete mPatternBindGroupLayout;
		if (mPatternFragShader != null) delete mPatternFragShader;
		if (mPatternVertShader != null) delete mPatternVertShader;
		if (mPatternUniformBuffer != null) delete mPatternUniformBuffer;
		if (mPatternVertexBuffer != null) delete mPatternVertexBuffer;

		if (mLargeTextureView != null) delete mLargeTextureView;
		if (mLargeTexture != null) delete mLargeTexture;
		if (mSmallTextureView != null) delete mSmallTextureView;
		if (mSmallTexture != null) delete mSmallTexture;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope BlitSample();
		return app.Run();
	}
}
