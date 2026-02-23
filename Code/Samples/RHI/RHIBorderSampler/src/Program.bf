namespace RHIBorderSampler;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell.Input;
using SampleFramework;

/// Border sampler sample - demonstrates SamplerBorderColor with ClampToBorder.
/// Shows a checkerboard texture with extended UV coordinates.
/// Press 1-3 to switch between border colors: TransparentBlack, OpaqueBlack, OpaqueWhite.
class BorderSamplerSample : RHISampleApp
{
	private IBuffer mVertexBuffer;
	private ITexture mTexture;
	private ITextureView mTextureView;
	private ISampler mSamplerTransparent;
	private ISampler mSamplerBlack;
	private ISampler mSamplerWhite;
	private ISampler mCurrentSampler;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroupTransparent;
	private IBindGroup mBindGroupBlack;
	private IBindGroup mBindGroupWhite;
	private IBindGroup mCurrentBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;
	private SamplerBorderColor mCurrentBorderColor = .TransparentBlack;

	public this() : base(.()
		{
			Title = "RHI Border Sampler",
			Width = 800,
			Height = 600,
			ClearColor = .(0.2f, 0.2f, 0.3f, 1.0f)  // Visible background to see transparency
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateTexture())
			return false;

		if (!CreateSamplers())
			return false;

		if (!CreateResources())
			return false;

		Console.WriteLine("Press 1: TransparentBlack border (shows background)");
		Console.WriteLine("Press 2: OpaqueBlack border");
		Console.WriteLine("Press 3: OpaqueWhite border");
		return true;
	}

	private bool CreateTexture()
	{
		// Create a small checkerboard texture (8x8)
		const uint32 SIZE = 8;
		uint32[SIZE * SIZE] pixels = .();

		for (uint32 y = 0; y < SIZE; y++)
		{
			for (uint32 x = 0; x < SIZE; x++)
			{
				bool isWhite = ((x + y) % 2) == 0;
				pixels[y * SIZE + x] = isWhite ? 0xFFFFFFFF : 0xFF00AAFF;  // White or Orange
			}
		}

		TextureDescriptor texDesc = TextureDescriptor.Texture2D(SIZE, SIZE, .RGBA8Unorm, .Sampled | .CopyDst);
		if (Device.CreateTexture(&texDesc) not case .Ok(let tex))
			return false;
		mTexture = tex;

		TextureViewDescriptor viewDesc = .()
		{
			Format = .RGBA8Unorm,
			Dimension = .Texture2D,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1
		};
		if (Device.CreateTextureView(mTexture, &viewDesc) not case .Ok(let view))
			return false;
		mTextureView = view;

		// Upload texture data
		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = SIZE * sizeof(uint32),
			RowsPerImage = SIZE
		};
		Extent3D writeSize = .(SIZE, SIZE, 1);
		Device.Queue.WriteTexture(mTexture, .((uint8*)&pixels, sizeof(uint32) * SIZE * SIZE), &dataLayout, &writeSize);

		Console.WriteLine("Checkerboard texture created");
		return true;
	}

	private bool CreateSamplers()
	{
		// Create sampler with TransparentBlack border
		SamplerDescriptor samplerDesc = .()
		{
			MinFilter = .Nearest,
			MagFilter = .Nearest,
			MipmapFilter = .Nearest,
			AddressModeU = .ClampToBorder,
			AddressModeV = .ClampToBorder,
			AddressModeW = .ClampToBorder,
			BorderColor = .TransparentBlack
		};

		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampTrans))
			return false;
		mSamplerTransparent = sampTrans;

		// Create sampler with OpaqueBlack border
		samplerDesc.BorderColor = .OpaqueBlack;
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampBlack))
			return false;
		mSamplerBlack = sampBlack;

		// Create sampler with OpaqueWhite border
		samplerDesc.BorderColor = .OpaqueWhite;
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampWhite))
			return false;
		mSamplerWhite = sampWhite;

		mCurrentSampler = mSamplerTransparent;
		Console.WriteLine("Samplers with border colors created");
		return true;
	}

	private bool CreateResources()
	{
		// Quad with extended UVs (from -0.5 to 1.5 to show border areas)
		float[24] vertices = .(
			// Position      UV (extended beyond 0-1)
			-0.8f, -0.8f,   -0.5f, 1.5f,   // Bottom-left
			 0.8f, -0.8f,    1.5f, 1.5f,   // Bottom-right
			 0.8f,  0.8f,    1.5f, -0.5f,  // Top-right
			-0.8f, -0.8f,   -0.5f, 1.5f,   // Bottom-left
			 0.8f,  0.8f,    1.5f, -0.5f,  // Top-right
			-0.8f,  0.8f,   -0.5f, -0.5f   // Top-left
		);

		BufferDescriptor vertexDesc = .()
		{
			Size = (uint64)(sizeof(float) * vertices.Count),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&vertexDesc) not case .Ok(let vb))
			return false;
		mVertexBuffer = vb;
		Device.Queue.WriteBuffer(mVertexBuffer, 0, .((uint8*)&vertices, (int)vertexDesc.Size));

		// Shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/border");
		if (shaderResult case .Err)
			return false;
		(mVertShader, mFragShader) = shaderResult.Get();

		// Bind group layout
		// Binding number = HLSL register number; RHI applies shifts automatically
		BindGroupLayoutEntry[2] layoutEntries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment), // t0
			BindGroupLayoutEntry.Sampler(0, .Fragment)         // s0
		);
		BindGroupLayoutDescriptor layoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&layoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		// Create bind groups for each sampler
		BindGroupEntry[2] entriesTransparent = .(
			BindGroupEntry.Texture(0, mTextureView),
			BindGroupEntry.Sampler(0, mSamplerTransparent)
		);
		BindGroupDescriptor bindDescTrans = .(mBindGroupLayout, entriesTransparent);
		if (Device.CreateBindGroup(&bindDescTrans) not case .Ok(let bgTrans))
			return false;
		mBindGroupTransparent = bgTrans;

		BindGroupEntry[2] entriesBlack = .(
			BindGroupEntry.Texture(0, mTextureView),
			BindGroupEntry.Sampler(0, mSamplerBlack)
		);
		BindGroupDescriptor bindDescBlack = .(mBindGroupLayout, entriesBlack);
		if (Device.CreateBindGroup(&bindDescBlack) not case .Ok(let bgBlack))
			return false;
		mBindGroupBlack = bgBlack;

		BindGroupEntry[2] entriesWhite = .(
			BindGroupEntry.Texture(0, mTextureView),
			BindGroupEntry.Sampler(0, mSamplerWhite)
		);
		BindGroupDescriptor bindDescWhite = .(mBindGroupLayout, entriesWhite);
		if (Device.CreateBindGroup(&bindDescWhite) not case .Ok(let bgWhite))
			return false;
		mBindGroupWhite = bgWhite;

		mCurrentBindGroup = mBindGroupTransparent;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		// Vertex layout
		VertexAttribute[2] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),  // position
			.(VertexFormat.Float2, 8, 1)   // uv
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)(sizeof(float) * 4), vertexAttributes)
		);

		// Pipeline with alpha blending to show transparent border
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format)
		{
			Blend = BlendState.AlphaBlend
		});

		RenderPipelineDescriptor pipelineDesc = .()
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
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mPipeline = pipeline;

		Console.WriteLine("Resources created");
		return true;
	}

	protected override void OnKeyDown(KeyCode key)
	{
		switch (key)
		{
		case .Num1:
			mCurrentBindGroup = mBindGroupTransparent;
			mCurrentBorderColor = .TransparentBlack;
			Console.WriteLine("Border: TransparentBlack (shows purple background)");
		case .Num2:
			mCurrentBindGroup = mBindGroupBlack;
			mCurrentBorderColor = .OpaqueBlack;
			Console.WriteLine("Border: OpaqueBlack");
		case .Num3:
			mCurrentBindGroup = mBindGroupWhite;
			mCurrentBorderColor = .OpaqueWhite;
			Console.WriteLine("Border: OpaqueWhite");
		default:
		}
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mCurrentBindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.Draw(6, 1, 0, 0);
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroupWhite != null) delete mBindGroupWhite;
		if (mBindGroupBlack != null) delete mBindGroupBlack;
		if (mBindGroupTransparent != null) delete mBindGroupTransparent;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mSamplerWhite != null) delete mSamplerWhite;
		if (mSamplerBlack != null) delete mSamplerBlack;
		if (mSamplerTransparent != null) delete mSamplerTransparent;
		if (mTextureView != null) delete mTextureView;
		if (mTexture != null) delete mTexture;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope BorderSamplerSample();
		return app.Run();
	}
}
