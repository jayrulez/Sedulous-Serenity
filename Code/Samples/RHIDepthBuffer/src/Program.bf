namespace RHIDepthBuffer;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;

/// Vertex with 3D position and color
[CRepr]
struct Vertex
{
	public float[3] Position;
	public float[3] Color;

	public this(float x, float y, float z, float r, float g, float b)
	{
		Position = .(x, y, z);
		Color = .(r, g, b);
	}

}

/// Uniform data with MVP matrix
[CRepr]
struct Uniforms
{
	public Matrix MVP;
}

/// Demonstrates depth buffer functionality by rendering overlapping quads.
class DepthBufferSample : RHISampleApp
{
	private IBuffer mVertexBuffer;
	private IBuffer mIndexBuffer;
	private IBuffer mUniformBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	public this() : base(.()
		{
			Title = "RHI Depth Buffer Test",
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

		if (!CreateBindings())
			return false;

		if (!CreatePipeline())
			return false;

		return true;
	}

	private bool CreateBuffers()
	{
		// Create two overlapping quads at different depths
		// Red quad in front (z = 0.0), Blue quad in back (z = 0.5)
		// They overlap in the center to demonstrate depth testing
		Vertex[8] vertices = .(
			// Red quad (front, z = 0.0) - positioned to the right and up
			.(-0.5f, -0.5f, 0.0f, 1.0f, 0.2f, 0.2f),  // Bottom-left
			.( 0.5f, -0.5f, 0.0f, 1.0f, 0.2f, 0.2f),  // Bottom-right
			.( 0.5f,  0.5f, 0.0f, 1.0f, 0.2f, 0.2f),  // Top-right
			.(-0.5f,  0.5f, 0.0f, 1.0f, 0.2f, 0.2f),  // Top-left

			// Blue quad (back, z = 0.5) - positioned to the left and down
			.(-0.3f, -0.3f, 0.5f, 0.2f, 0.2f, 1.0f),  // Bottom-left
			.( 0.7f, -0.3f, 0.5f, 0.2f, 0.2f, 1.0f),  // Bottom-right
			.( 0.7f,  0.7f, 0.5f, 0.2f, 0.2f, 1.0f),  // Top-right
			.(-0.3f,  0.7f, 0.5f, 0.2f, 0.2f, 1.0f)   // Top-left
		);

		// Index buffer for two quads (6 indices each)
		uint16[12] indices = .(
			// Red quad (front)
			0, 1, 2,  0, 2, 3,
			// Blue quad (back)
			4, 5, 6,  4, 6, 7
		);

		// Create vertex buffer
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

	private bool CreateBindings()
	{
		// Load shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/depth");
		if (shaderResult case .Err)
			return false;

		(mVertShader, mFragShader) = shaderResult.Get();
		Console.WriteLine("Shaders compiled");

		// Create bind group layout
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		// Create bind group
		BindGroupEntry[1] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffer)
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
			.(VertexFormat.Float3, 0, 0),   // Position at location 0
			.(VertexFormat.Float3, 12, 1)   // Color at location 1
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// Color target
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		// Depth stencil state - enable depth testing
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

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Create rotation around Y axis
		float angle = totalTime * 0.5f;

		let model = Matrix.CreateRotationY(angle);

		// Simple perspective projection
		float aspect = (float)SwapChain.Width / (float)SwapChain.Height;
		var projection = Matrix.CreatePerspectiveFieldOfView(
			Math.PI_f / 4.0f,  // 45 degree FOV
			aspect,
			0.1f,              // Near plane
			100.0f             // Far plane
		);

		// Camera looking at origin from z = 3
		let view = Matrix.CreateLookAt(
			.(0.0f, 0.0f, 3.0f),   // Eye position
			.(0.0f, 0.0f, 0.0f),   // Look at
			.(0.0f, 1.0f, 0.0f)    // Up vector
		);

		// Flip Y for Vulkan's coordinate system
		if (Device.FlipProjectionRequired)
			projection.M22 = -projection.M22;

		// Row-major: MVP = model * view * projection
		Uniforms uniforms = .() { MVP = model * view * projection };
		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		Device.Queue.WriteBuffer(mUniformBuffer, 0, uniformData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);
		renderPass.DrawIndexed(12, 1, 0, 0, 0);  // 12 indices for 2 quads
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroup != null) delete mBindGroup;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mUniformBuffer != null) delete mUniformBuffer;
		if (mIndexBuffer != null) delete mIndexBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope DepthBufferSample();
		return app.Run();
	}
}
