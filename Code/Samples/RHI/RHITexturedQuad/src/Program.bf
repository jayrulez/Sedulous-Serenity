namespace RHITexturedQuad;

using System;
using Sedulous.Mathematics;
using Sedulous.Imaging;
using Sedulous.RHI;
using SampleFramework;

/// Vertex structure with position and texture coordinates
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

/// Uniform buffer data for the transform matrix
[CRepr]
struct Uniforms
{
	public Matrix Transform;
}

/// Rotating textured quad sample using the RHI sample framework.
class TexturedQuadSample : RHISampleApp
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

	public this() : base(.()
		{
			Title = "RHI Textured Quad",
			Width = 800,
			Height = 600,
			ClearColor = .(0.1f, 0.1f, 0.1f, 1.0f)
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

		return true;
	}

	private bool CreateBuffers()
	{
		// Define quad vertices (position + UV)
		Vertex[4] vertices = .(
			.(-0.5f, -0.5f, 0.0f, 1.0f),  // Bottom-left
			.( 0.5f, -0.5f, 1.0f, 1.0f),  // Bottom-right
			.( 0.5f,  0.5f, 1.0f, 0.0f),  // Top-right
			.(-0.5f,  0.5f, 0.0f, 0.0f)   // Top-left
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

		// Create index buffer
		uint16[6] indices = .(
			0, 1, 2,  // First triangle
			0, 2, 3   // Second triangle
		);

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

		// Create uniform buffer
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
		// Generate checkerboard image using Sedulous.Imaging
		let image = Image.CreateCheckerboard(256, Color.White, Color(0.2f, 0.2f, 0.8f, 1.0f), 32, .RGBA8);
		defer delete image;

		Console.WriteLine(scope $"Created checkerboard image: {image.Width}x{image.Height}");

		// Create texture
		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			image.Width,
			image.Height,
			.RGBA8Unorm,
			.Sampled | .CopyDst
		);

		if (Device.CreateTexture(&textureDesc) not case .Ok(let texture))
			return false;
		mTexture = texture;

		// Upload texture data
		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = image.Width * 4,
			RowsPerImage = image.Height
		};

		Extent3D writeSize = .(image.Width, image.Height, 1);
		Device.Queue.WriteTexture(mTexture, image.Data, &dataLayout, &writeSize);

		// Create texture view
		TextureViewDescriptor viewDesc = .();
		if (Device.CreateTextureView(mTexture, &viewDesc) not case .Ok(let textureView))
			return false;
		mTextureView = textureView;

		// Create sampler
		SamplerDescriptor samplerDesc = SamplerDescriptor.LinearRepeat();
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return false;
		mSampler = sampler;

		Console.WriteLine("Texture created");
		return true;
	}

	private bool CreateBindings()
	{
		// Load shaders - automatic binding shifts are applied by default
		// b0 -> binding 0, t0 -> binding 1000, s0 -> binding 3000
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/quad");
		if (shaderResult case .Err)
			return false;

		(mVertShader, mFragShader) = shaderResult.Get();
		Console.WriteLine("Shaders compiled");

		// Create bind group layout (uniform buffer + texture + sampler)
		// Use binding 0 for all - the RHI applies shifts based on resource type
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),   // b0 -> Vulkan binding 0
			BindGroupLayoutEntry.SampledTexture(0, .Fragment), // t0 -> Vulkan binding 1000
			BindGroupLayoutEntry.Sampler(0, .Fragment)         // s0 -> Vulkan binding 3000
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
		// Vertex attributes - must be in same scope as pipeline creation
		VertexAttribute[2] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),   // Position at location 0
			.(VertexFormat.Float2, 8, 1)    // TexCoord at location 1
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// Color target
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

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
			DepthStencil = null,
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

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Create rotation matrix around Z axis
		float rotationAngle = totalTime * 0.5f;  // Slower rotation
		Uniforms uniforms = .() { Transform = Matrix.CreateRotationZ(rotationAngle) };
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
		let app = scope TexturedQuadSample();
		return app.Run();
	}
}
