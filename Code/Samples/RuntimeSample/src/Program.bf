namespace RuntimeSample;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Framework.Runtime;
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

/// Uniform buffer data for the transform matrix
[CRepr]
struct Uniforms
{
	public Matrix Transform;
}

/// Triangle sample using the Sedulous.Framework.Runtime application framework.
class TriangleApp : Application
{
	private IBuffer mVertexBuffer;
	private IBuffer mUniformBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;
	private bool mInitialized = false;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize()
	{
		if (!CreateBuffers())
		{
			Exit();
			return;
		}

		if (!CreateBindings())
		{
			Exit();
			return;
		}

		if (!CreatePipeline())
		{
			Exit();
			return;
		}

		mInitialized = true;
		Console.WriteLine("RuntimeSample initialized successfully");
	}

	private bool CreateBuffers()
	{
		// Define triangle vertices (position + color)
		Vertex[3] vertices = .(
			.(0.0f, -0.5f, 1.0f, 0.0f, 0.0f),   // Top - Red
			.(0.5f, 0.5f, 0.0f, 1.0f, 0.0f),    // Bottom right - Green
			.(-0.5f, 0.5f, 0.0f, 0.0f, 1.0f)    // Bottom left - Blue
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
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/triangle");
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
			.(VertexFormat.Float2, 0, 0),   // Position at location 0
			.(VertexFormat.Float3, 8, 1)    // Color at location 1
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

	protected override void OnInput()
	{
		// Check for ESC key to exit
		if (Shell.InputManager.Keyboard.IsKeyPressed(.Escape))
			Exit();
	}

	protected override void OnUpdate(FrameContext frame)
	{
		if (!mInitialized)
			return;

		// Create rotation matrix around Z axis
		float rotationAngle = frame.TotalTime * 1.0f;  // 1 radian per second
		Uniforms uniforms = .() { Transform = Matrix.CreateRotationZ(rotationAngle) };
		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		Device.Queue.WriteBuffer(mUniformBuffer, 0, uniformData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass, FrameContext frame)
	{
		if (!mInitialized)
			return;

		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.Draw(3, 1, 0, 0);
	}

	protected override void OnShutdown()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroup != null) delete mBindGroup;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mUniformBuffer != null) delete mUniformBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		// Create and initialize shell
		let shell = new SDL3Shell();
		defer { shell.Shutdown(); delete shell; }

		if (shell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return -1;
		}

		// Create Vulkan backend
		let backend = new VulkanBackend(enableValidation: true);
		defer delete backend;

		if (!backend.IsInitialized)
		{
			Console.WriteLine("Failed to initialize Vulkan backend");
			return -1;
		}

		// Enumerate adapters and create device
		List<IAdapter> adapters = scope .();
		backend.EnumerateAdapters(adapters);

		if (adapters.Count == 0)
		{
			Console.WriteLine("No GPU adapters found");
			return -1;
		}

		Console.WriteLine("Using adapter: {0}", adapters[0].Info.Name);

		let device = adapters[0].CreateDevice().GetValueOrDefault();
		if (device == null)
		{
			Console.WriteLine("Failed to create device");
			return -1;
		}
		defer delete device;

		// Create and run application
		let settings = ApplicationSettings()
		{
			Title = "Runtime Sample - Triangle",
			Width = 800,
			Height = 600,
			ClearColor = .(0.0f, 0.2f, 0.4f, 1.0f)
		};

		let app = scope TriangleApp(shell, device, backend);
		return app.Run(settings);
	}
}
