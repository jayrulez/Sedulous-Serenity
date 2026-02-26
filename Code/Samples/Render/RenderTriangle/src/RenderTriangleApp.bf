namespace RenderTriangle;

using System;
using System.IO;
using Sedulous.Foundation.Mathematics;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Shell;
using Sedulous.Framework.Runtime;
using Sedulous.Render;

/// Vertex structure with position and color.
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

/// Uniform buffer data for the transform matrix.
[CRepr]
struct Uniforms
{
	public Matrix Transform;
}

/// Triangle sample using the Render Graph.
/// Demonstrates basic render graph usage for automatic resource management.
class RenderTriangleApp : Application
{
	// GPU resources
	private IBuffer mVertexBuffer ~ delete _;
	private IBuffer mUniformBuffer ~ delete _;
	private IShaderModule mVertShader ~ delete _;
	private IShaderModule mFragShader ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IBindGroup mBindGroup ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IRenderPipeline mPipeline ~ delete _;

	// Render graph
	private RenderGraph mRenderGraph ~ delete _;

	// Timing
	private float mTotalTime = 0;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Framework.Core.Context context)
	{
		// Create render graph
		mRenderGraph = new RenderGraph(mDevice);

		if (!CreateBuffers())
		{
			Console.WriteLine("ERROR: Failed to create buffers");
			return;
		}

		if (!CreateShaders())
		{
			Console.WriteLine("ERROR: Failed to create shaders");
			return;
		}

		if (!CreateBindings())
		{
			Console.WriteLine("ERROR: Failed to create bindings");
			return;
		}

		if (!CreatePipeline())
		{
			Console.WriteLine("ERROR: Failed to create pipeline");
			return;
		}

		Console.WriteLine("Render Triangle initialized");
		Console.WriteLine("  ESC: exit");
	}

	private bool CreateBuffers()
	{
		// Define triangle vertices (position + color)
		Vertex[3] vertices = .(
			.(0.0f, -0.5f, 1.0f, 0.0f, 0.0f),   // Top - Red
			.(0.5f, 0.5f, 0.0f, 1.0f, 0.0f),     // Bottom right - Green
			.(-0.5f, 0.5f, 0.0f, 0.0f, 1.0f)      // Bottom left - Blue
		);

		// Create vertex buffer
		BufferDescriptor vertexDesc = .()
		{
			Size = (uint64)(sizeof(Vertex) * vertices.Count),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};

		if (mDevice.CreateBuffer(&vertexDesc) not case .Ok(let vb))
			return false;
		mVertexBuffer = vb;

		Span<uint8> vertexData = .((uint8*)&vertices, (int)vertexDesc.Size);
		mDevice.Queue.WriteBuffer(mVertexBuffer, 0, vertexData);

		// Create uniform buffer
		BufferDescriptor uniformDesc = .()
		{
			Size = (uint64)sizeof(Uniforms),
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		if (mDevice.CreateBuffer(&uniformDesc) not case .Ok(let ub))
			return false;
		mUniformBuffer = ub;

		return true;
	}

	private bool CreateShaders()
	{
		let compiler = scope ShaderCompiler();
		if (compiler.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shader compiler");
			return false;
		}

		// Load and compile vertex shader
		String vertSource = scope .();
		if (!ReadTextFile("shaders/triangle.vert.hlsl", vertSource))
		{
			Console.WriteLine("Failed to read vertex shader file");
			return false;
		}

		var vertResult = compiler.Compile(vertSource, ShaderVariantKey("triangle", .Vertex));
		defer vertResult.Dispose();

		if (!vertResult.Success)
		{
			Console.WriteLine("Vertex shader compilation failed: {}", vertResult.Messages);
			return false;
		}

		ShaderModuleDescriptor vertDesc = .(vertResult.Bytecode);
		if (mDevice.CreateShaderModule(&vertDesc) case .Ok(let vs))
			mVertShader = vs;
		else
			return false;

		// Load and compile fragment shader
		String fragSource = scope .();
		if (!ReadTextFile("shaders/triangle.frag.hlsl", fragSource))
		{
			Console.WriteLine("Failed to read fragment shader file");
			return false;
		}

		var fragResult = compiler.Compile(fragSource, ShaderVariantKey("triangle", .Fragment));
		defer fragResult.Dispose();

		if (!fragResult.Success)
		{
			Console.WriteLine("Fragment shader compilation failed: {}", fragResult.Messages);
			return false;
		}

		ShaderModuleDescriptor fragDesc = .(fragResult.Bytecode);
		if (mDevice.CreateShaderModule(&fragDesc) case .Ok(let fs))
			mFragShader = fs;
		else
			return false;

		return true;
	}

	private bool CreateBindings()
	{
		// Create bind group layout
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		// Create bind group
		BindGroupEntry[1] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (mDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mBindGroup = group;

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		return true;
	}

	private bool CreatePipeline()
	{
		// Vertex attributes
		VertexAttribute[2] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),   // Position at location 0
			.(VertexFormat.Float3, 8, 1)    // Color at location 1
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// Color target
		ColorTargetState[1] colorTargets = .(.(mSwapChain.Format));

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

		if (mDevice.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mPipeline = pipeline;

		return true;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mTotalTime = frame.TotalTime;

		// Update rotation uniform
		float rotationAngle = mTotalTime * 1.0f;
		Uniforms uniforms = .() { Transform = Matrix.CreateRotationZ(rotationAngle) };
		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		mDevice.Queue.WriteBuffer(mUniformBuffer, 0, uniformData);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		// Begin frame for render graph
		mRenderGraph.BeginFrame(render.Frame.FrameIndex);

		// Import swap chain texture
		let swapChainHandle = mRenderGraph.ImportTexture(
			"SwapChain",
			render.SwapChain.CurrentTexture,
			render.SwapChain.CurrentTextureView
		);

		// Capture resources for the lambda
		let pipeline = mPipeline;
		let bindGroup = mBindGroup;
		let vertexBuffer = mVertexBuffer;
		let width = render.SwapChain.Width;
		let height = render.SwapChain.Height;
		let clearColor = Color(25, 38, 51, 255);

		// Add forward pass through the render graph
		mRenderGraph.AddGraphicsPass("ForwardPass")
			.WriteColor(swapChainHandle, .Clear, .Store, clearColor)
			.NeverCull()
			.SetExecuteCallback(new (encoder) =>
			{
				encoder.SetViewport(0, 0, width, height, 0, 1);
				encoder.SetScissorRect(0, 0, width, height);
				encoder.SetPipeline(pipeline);
				encoder.SetBindGroup(0, bindGroup);
				encoder.SetVertexBuffer(0, vertexBuffer, 0);
				encoder.Draw(3, 1, 0, 0);
			});

		// Compile and execute
		mRenderGraph.Compile();
		mRenderGraph.Execute(render.Encoder);

		// End frame
		mRenderGraph.EndFrame();

		return true;
	}

	protected override void OnShutdown()
	{
		mRenderGraph?.Dispose();
		Console.WriteLine("Render Triangle shutting down");
	}

	/// Reads a text file into a string.
	private static bool ReadTextFile(StringView path, String outContent)
	{
		let stream = scope FileStream();
		if (stream.Open(path, .Read, .Read) case .Err)
			return false;

		let reader = scope StreamReader(stream);
		if (reader.ReadToEnd(outContent) case .Err)
			return false;

		return true;
	}
}
