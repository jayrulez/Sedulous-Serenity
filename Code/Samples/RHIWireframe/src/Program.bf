namespace RHIWireframe;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell.Input;
using SampleFramework;

/// Vertex structure with position and color for 3D cube
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

/// Uniform buffer for transform matrix
[CRepr]
struct Uniforms
{
	public Matrix Transform;
}

/// Wireframe rendering sample - demonstrates FillMode.Wireframe
/// Press SPACE to toggle between solid and wireframe rendering.
class WireframeSample : RHISampleApp
{
	private IBuffer mVertexBuffer;
	private IBuffer mIndexBuffer;
	private IBuffer mUniformBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mSolidPipeline;
	private IRenderPipeline mWireframePipeline;
	private bool mUseWireframe = true;

	public this() : base(.()
		{
			Title = "RHI Wireframe",
			Width = 800,
			Height = 600,
			ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f),
			EnableDepth = true
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateBuffers())
			return false;

		if (!CreateBindings())
			return false;

		if (!CreatePipelines())
			return false;

		Console.WriteLine("Press SPACE to toggle wireframe mode");
		return true;
	}

	private bool CreateBuffers()
	{
		// Define cube vertices (position + color)
		Vertex[8] vertices = .(
			.(-0.5f, -0.5f, -0.5f, 1.0f, 0.0f, 0.0f),  // 0: Front-bottom-left - Red
			.( 0.5f, -0.5f, -0.5f, 0.0f, 1.0f, 0.0f),  // 1: Front-bottom-right - Green
			.( 0.5f,  0.5f, -0.5f, 0.0f, 0.0f, 1.0f),  // 2: Front-top-right - Blue
			.(-0.5f,  0.5f, -0.5f, 1.0f, 1.0f, 0.0f),  // 3: Front-top-left - Yellow
			.(-0.5f, -0.5f,  0.5f, 1.0f, 0.0f, 1.0f),  // 4: Back-bottom-left - Magenta
			.( 0.5f, -0.5f,  0.5f, 0.0f, 1.0f, 1.0f),  // 5: Back-bottom-right - Cyan
			.( 0.5f,  0.5f,  0.5f, 1.0f, 1.0f, 1.0f),  // 6: Back-top-right - White
			.(-0.5f,  0.5f,  0.5f, 0.5f, 0.5f, 0.5f)   // 7: Back-top-left - Gray
		);

		// Cube indices (36 indices for 12 triangles)
		uint16[36] indices = .(
			// Front face
			0, 2, 1, 0, 3, 2,
			// Back face
			4, 5, 6, 4, 6, 7,
			// Left face
			4, 7, 3, 4, 3, 0,
			// Right face
			1, 2, 6, 1, 6, 5,
			// Top face
			3, 7, 6, 3, 6, 2,
			// Bottom face
			4, 0, 1, 4, 1, 5
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
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/wireframe");
		if (shaderResult case .Err)
			return false;

		(mVertShader, mFragShader) = shaderResult.Get();
		Console.WriteLine("Shaders compiled");

		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		BindGroupEntry[1] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mBindGroup = group;

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		Console.WriteLine("Bindings created");
		return true;
	}

	private bool CreatePipelines()
	{
		VertexAttribute[2] vertexAttributes = .(
			.(VertexFormat.Float3, 0, 0),   // Position at location 0
			.(VertexFormat.Float3, 12, 1)   // Color at location 1
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		// Create SOLID pipeline
		RenderPipelineDescriptor solidDesc = .()
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
				CullMode = .Back,
				FillMode = .Solid  // Solid fill
			},
			DepthStencil = DepthStencilState.Default,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&solidDesc) not case .Ok(let solidPipeline))
			return false;
		mSolidPipeline = solidPipeline;

		// Create WIREFRAME pipeline
		RenderPipelineDescriptor wireframeDesc = solidDesc;
		wireframeDesc.Primitive.FillMode = .Wireframe;  // Wireframe fill
		wireframeDesc.Primitive.CullMode = .None;       // No culling in wireframe

		if (Device.CreateRenderPipeline(&wireframeDesc) not case .Ok(let wireframePipeline))
			return false;
		mWireframePipeline = wireframePipeline;

		Console.WriteLine("Pipelines created (solid + wireframe)");
		return true;
	}

	protected override void OnKeyDown(KeyCode key)
	{
		if (key == .Space)
		{
			mUseWireframe = !mUseWireframe;
			Console.WriteLine(scope $"Wireframe mode: {mUseWireframe ? "ON" : "OFF"}");
		}
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Create combined rotation and perspective matrix
		float rotY = totalTime * 0.7f;
		float rotX = totalTime * 0.5f;

		Matrix model = Matrix.CreateRotationY(rotY) * Matrix.CreateRotationX(rotX);
		Matrix view = Matrix.CreateLookAt(.(0, 0, 3), .(0, 0, 0), .(0, 1, 0));
		float aspect = (float)SwapChain.Width / (float)SwapChain.Height;
		Matrix proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, aspect, 0.1f, 100.0f);

		// Flip Y for Vulkan's coordinate system
		if (Device.FlipProjectionRequired)
			proj.M22 = -proj.M22;

		// Row-major: MVP = model * view * projection
		Uniforms uniforms = .() { Transform = model * view * proj };
		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		Device.Queue.WriteBuffer(mUniformBuffer, 0, uniformData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Use wireframe or solid pipeline based on toggle
		renderPass.SetPipeline(mUseWireframe ? mWireframePipeline : mSolidPipeline);
		renderPass.SetBindGroup(0, mBindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);
		renderPass.DrawIndexed(36, 1, 0, 0, 0);
	}

	protected override void OnCleanup()
	{
		if (mWireframePipeline != null) delete mWireframePipeline;
		if (mSolidPipeline != null) delete mSolidPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroup != null) delete mBindGroup;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mIndexBuffer != null) delete mIndexBuffer;
		if (mUniformBuffer != null) delete mUniformBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope WireframeSample();
		return app.Run();
	}
}
