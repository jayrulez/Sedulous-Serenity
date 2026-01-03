namespace RHIMipmaps;

using System;
using Sedulous.Mathematics;
using Sedulous.Imaging;
using Sedulous.RHI;
using RHI.SampleFramework;

/// Vertex with position and texture coordinates
[CRepr]
struct Vertex
{
	public float[2] Position;
	public float[2] TexCoord;

	public this(float x, float y, float u, float v)
	{
		Position = .(x, y);
		TexCoord = .(u, v);
	}
}

/// Uniform data
[CRepr]
struct Uniforms
{
	public Matrix4x4 MVP;
	public float MipBias;
	public float[3] Padding;
}

/// Demonstrates mipmap levels and GPU mipmap generation.
/// Use arrow keys to move the quad closer/further to see mip level changes.
/// Press M to toggle between manual colored mips (visualization) and GPU-generated mips.
class MipmapSample : RHISampleApp
{
	private IBuffer mVertexBuffer;
	private IBuffer mIndexBuffer;
	private IBuffer mUniformBuffer;
	private ITexture mTexture;
	private ITextureView mTextureView;
	private ISampler mSampler;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	private float mDistance = 2.0f;  // Camera distance (controls mip level)
	private bool mUseGeneratedMips = false;  // Toggle between manual and generated mips

	// Colors for each mip level (for visualization)
	private static Color[8] sMipColors = .(
		.(1.0f, 0.0f, 0.0f, 1.0f),  // Level 0: Red (256x256)
		.(1.0f, 0.5f, 0.0f, 1.0f),  // Level 1: Orange (128x128)
		.(1.0f, 1.0f, 0.0f, 1.0f),  // Level 2: Yellow (64x64)
		.(0.0f, 1.0f, 0.0f, 1.0f),  // Level 3: Green (32x32)
		.(0.0f, 1.0f, 1.0f, 1.0f),  // Level 4: Cyan (16x16)
		.(0.0f, 0.0f, 1.0f, 1.0f),  // Level 5: Blue (8x8)
		.(1.0f, 0.0f, 1.0f, 1.0f),  // Level 6: Magenta (4x4)
		.(1.0f, 1.0f, 1.0f, 1.0f)   // Level 7: White (2x2)
	);

	public this() : base(.()
		{
			Title = "RHI Mipmaps Test",
			Width = 800,
			Height = 600,
			EnableDepth = true,
			ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateBuffers())
			return false;

		if (!CreateTexture())
			return false;

		if (!CreateBindings())
			return false;

		if (!CreatePipeline())
			return false;

		Console.WriteLine("Use Up/Down arrows to move the quad and see mipmap levels change");
		Console.WriteLine("Press M to toggle between manual colored mips and GPU-generated mips");
		Console.WriteLine("Manual mode: Mip 0=Red, 1=Orange, 2=Yellow, 3=Green, 4=Cyan, 5=Blue, 6=Magenta, 7=White");
		return true;
	}

	private bool CreateBuffers()
	{
		// Large quad with tiled texture coordinates
		float size = 2.0f;
		float tiles = 8.0f;  // Repeat texture to make mip levels more visible
		Vertex[4] vertices = .(
			.(-size, -size, 0.0f, tiles),
			.( size, -size, tiles, tiles),
			.( size,  size, tiles, 0.0f),
			.(-size,  size, 0.0f, 0.0f)
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

		Span<uint8> vertexData = .((uint8*)&vertices, (int)vertexDesc.Size);
		Device.Queue.WriteBuffer(mVertexBuffer, 0, vertexData);

		// Index buffer
		uint16[6] indices = .(0, 1, 2, 0, 2, 3);

		BufferDescriptor indexDesc = .()
		{
			Size = (uint64)(sizeof(uint16) * indices.Count),
			Usage = .Index,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&indexDesc) not case .Ok(let ib))
			return false;
		mIndexBuffer = ib;

		Span<uint8> indexData = .((uint8*)&indices, (int)indexDesc.Size);
		Device.Queue.WriteBuffer(mIndexBuffer, 0, indexData);

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

		Console.WriteLine("Buffers created");
		return true;
	}

	private bool CreateTexture()
	{
		return CreateTextureWithMode(mUseGeneratedMips);
	}

	private bool CreateTextureWithMode(bool useGeneratedMips)
	{
		// Create texture with multiple mip levels
		uint32 baseSize = 256;
		uint32 mipLevels = 8;  // 256 -> 128 -> 64 -> 32 -> 16 -> 8 -> 4 -> 2

		// For generated mips, we need CopySrc and CopyDst for the blit operations
		TextureUsage usage = useGeneratedMips
			? .Sampled | .CopyDst | .CopySrc
			: .Sampled | .CopyDst;

		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			baseSize,
			baseSize,
			.RGBA8Unorm,
			usage,
			mipLevels
		);

		if (Device.CreateTexture(&textureDesc) not case .Ok(let texture))
			return false;
		mTexture = texture;

		if (useGeneratedMips)
		{
			// Upload only level 0 with a detailed pattern, then generate mips on GPU
			let color1 = Color(0.2f, 0.6f, 1.0f, 1.0f);  // Light blue
			let color2 = Color(1.0f, 0.8f, 0.2f, 1.0f);  // Yellow/gold
			let image = Image.CreateCheckerboard(baseSize, color1, color2, 16, .RGBA8);
			defer delete image;

			TextureDataLayout dataLayout = .()
			{
				Offset = 0,
				BytesPerRow = baseSize * 4,
				RowsPerImage = baseSize
			};

			Extent3D extent = .(baseSize, baseSize, 1);
			Device.Queue.WriteTexture(mTexture, image.Data, &dataLayout, &extent, 0, 0);

			// Generate mipmaps on GPU
			let encoder = Device.CreateCommandEncoder();
			defer delete encoder;

			encoder.GenerateMipmaps(mTexture);

			let cmdBuffer = encoder.Finish();
			defer delete cmdBuffer;
			Device.Queue.Submit(cmdBuffer);
			Device.WaitIdle();

			Console.WriteLine(scope $"Texture created with {mipLevels} GPU-generated mip levels");
		}
		else
		{
			// Upload each mip level with a different colored checkerboard (for visualization)
			uint32 mipWidth = baseSize;
			uint32 mipHeight = baseSize;

			for (uint32 level = 0; level < mipLevels; level++)
			{
				// Create checkerboard image for this level
				let color1 = sMipColors[level];
				let color2 = Color(color1.R * 0.5f, color1.G * 0.5f, color1.B * 0.5f, 1.0f);

				let image = Image.CreateCheckerboard(mipWidth, color1, color2, Math.Max(mipWidth / 8, 1), .RGBA8);
				defer delete image;

				// Upload to specific mip level
				TextureDataLayout dataLayout = .()
				{
					Offset = 0,
					BytesPerRow = mipWidth * 4,
					RowsPerImage = mipHeight
				};

				Extent3D extent = .(mipWidth, mipHeight, 1);
				Device.Queue.WriteTexture(mTexture, image.Data, &dataLayout, &extent, level, 0);

				mipWidth = Math.Max(mipWidth / 2, 1);
				mipHeight = Math.Max(mipHeight / 2, 1);
			}

			Console.WriteLine(scope $"Texture created with {mipLevels} manually-colored mip levels");
		}

		// Create texture view for all mip levels
		TextureViewDescriptor viewDesc = .()
		{
			Format = .RGBA8Unorm,
			Dimension = .Texture2D,
			BaseMipLevel = 0,
			MipLevelCount = mipLevels,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1
		};
		if (Device.CreateTextureView(mTexture, &viewDesc) not case .Ok(let view))
			return false;
		mTextureView = view;

		// Create sampler with trilinear filtering (enables smooth mip transitions)
		SamplerDescriptor samplerDesc = .()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear,
			AddressModeU = .Repeat,
			AddressModeV = .Repeat,
			AddressModeW = .Repeat,
			LodMinClamp = 0.0f,
			LodMaxClamp = 32.0f,
			MaxAnisotropy = 1
		};
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return false;
		mSampler = sampler;

		return true;
	}

	private void RecreateTexture()
	{
		Device.WaitIdle();

		// Clean up old bind group (references old texture view)
		if (mBindGroup != null)
		{
			delete mBindGroup;
			mBindGroup = null;
		}

		// Clean up old texture resources
		if (mTextureView != null)
		{
			delete mTextureView;
			mTextureView = null;
		}
		if (mTexture != null)
		{
			delete mTexture;
			mTexture = null;
		}
		if (mSampler != null)
		{
			delete mSampler;
			mSampler = null;
		}

		// Recreate with new mode
		if (!CreateTextureWithMode(mUseGeneratedMips))
		{
			Console.WriteLine("Failed to recreate texture!");
			return;
		}

		// Recreate bind group with new texture - use binding 0 for all resource types
		BindGroupEntry[3] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffer),
			BindGroupEntry.Texture(0, mTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
			mBindGroup = group;
	}

	private bool CreateBindings()
	{
		// Load shaders - automatic binding shifts are applied by default
		// b0 -> binding 0, t0 -> binding 1000, s0 -> binding 3000
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/mipmap");
		if (shaderResult case .Err)
			return false;

		(mVertShader, mFragShader) = shaderResult.Get();
		Console.WriteLine("Shaders compiled");

		// Create bind group layout - use binding 0 for all resource types
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),     // b0 -> Vulkan binding 0
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),  // t0 -> Vulkan binding 1000
			BindGroupLayoutEntry.Sampler(0, .Fragment)          // s0 -> Vulkan binding 3000
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		// Create bind group - use binding 0 for all resource types
		BindGroupEntry[3] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffer),
			BindGroupEntry.Texture(0, mTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mBindGroup = group;

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		Console.WriteLine("Bindings created");
		return true;
	}

	private bool CreatePipeline()
	{
		// Vertex attributes
		VertexAttribute[2] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),
			.(VertexFormat.Float2, 8, 1)
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// Color target
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		// Depth stencil
		DepthStencilState depthStencil = .()
		{
			Format = .Depth24PlusStencil8,
			DepthWriteEnabled = true,
			DepthCompare = .Less,
			StencilFront = .(),
			StencilBack = .(),
			StencilReadMask = 0xFF,
			StencilWriteMask = 0xFF
		};

		// Pipeline descriptor
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
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = depthStencil,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue,
				AlphaToCoverageEnabled = false
			}
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mPipeline = pipeline;

		Console.WriteLine("Pipeline created");
		return true;
	}

	protected override void OnInput()
	{
		// Move quad closer/further with arrow keys
		float speed = 5.0f * DeltaTime;
		if (Shell.InputManager.Keyboard.IsKeyDown(.Up))
			mDistance = Math.Max(0.5f, mDistance - speed);
		if (Shell.InputManager.Keyboard.IsKeyDown(.Down))
			mDistance = Math.Min(20.0f, mDistance + speed);

		// Toggle between manual and generated mipmaps
		if (Shell.InputManager.Keyboard.IsKeyPressed(.M))
		{
			mUseGeneratedMips = !mUseGeneratedMips;
			Console.WriteLine(scope $"Switching to {(mUseGeneratedMips ? "GPU-generated" : "manual colored")} mipmaps...");
			RecreateTexture();
		}
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Create MVP matrix
		let model = Matrix4x4.CreateRotationX(-Math.PI_f * 0.3f);  // Tilt the quad

		float aspect = (float)SwapChain.Width / (float)SwapChain.Height;
		let projection = Matrix4x4.CreatePerspective(
			Math.PI_f / 4.0f,
			aspect,
			0.1f,
			100.0f
		);

		let view = Matrix4x4.CreateLookAt(
			.(0.0f, 0.0f, mDistance),
			.(0.0f, 0.0f, 0.0f),
			.(0.0f, 1.0f, 0.0f)
		);

		Uniforms uniforms = .()
		{
			MVP = projection * view * model,
			MipBias = 0.0f,
			Padding = default
		};
		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		Device.Queue.WriteBuffer(mUniformBuffer, 0, uniformData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);
		renderPass.DrawIndexed(6, 1, 0, 0, 0);
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroup != null) delete mBindGroup;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mSampler != null) delete mSampler;
		if (mTextureView != null) delete mTextureView;
		if (mTexture != null) delete mTexture;
		if (mUniformBuffer != null) delete mUniformBuffer;
		if (mIndexBuffer != null) delete mIndexBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope MipmapSample();
		return app.Run();
	}
}
