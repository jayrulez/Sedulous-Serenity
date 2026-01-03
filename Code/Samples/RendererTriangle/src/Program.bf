namespace RendererTriangle;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Framework.Renderer;
using RHI.SampleFramework;

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
	public Matrix4x4 Transform;
}

/// Triangle sample using the Render Graph.
/// This demonstrates basic render graph usage for automatic resource management.
class RendererTriangleSample : RHISampleApp
{
	// GPU resources
	private IBuffer mVertexBuffer;
	private IBuffer mUniformBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	// Render graph
	private RenderGraph mRenderGraph;
	private uint32 mFrameIndex;

	public this() : base(.()
		{
			Title = "Renderer Triangle (Render Graph)",
			Width = 800,
			Height = 600,
			ClearColor = .(0.1f, 0.15f, 0.2f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		// Create render graph
		mRenderGraph = new RenderGraph(Device);

		if (!CreateBuffers())
			return false;

		if (!CreateBindings())
			return false;

		if (!CreatePipeline())
			return false;

		Console.WriteLine("Renderer Triangle initialized with RenderGraph");
		return true;
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
		// Load shaders (reuse triangle shaders)
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
		// Vertex attributes
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

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Update rotation
		float rotationAngle = totalTime * 1.0f;
		Uniforms uniforms = .() { Transform = Matrix4x4.CreateRotationZ(rotationAngle) };
		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		Device.Queue.WriteBuffer(mUniformBuffer, 0, uniformData);
	}

	protected override bool OnRenderCustom(ICommandEncoder encoder)
	{
		// Begin frame for render graph
		mRenderGraph.BeginFrame(mFrameIndex, DeltaTime, TotalTime);

		// Import swap chain texture
		let swapChainHandle = mRenderGraph.ImportTexture(
			"SwapChain",
			SwapChain.CurrentTexture,
			SwapChain.CurrentTextureView,
			.Undefined
		);

		// Capture resources for the lambda
		let pipeline = mPipeline;
		let bindGroup = mBindGroup;
		let vertexBuffer = mVertexBuffer;
		let width = SwapChain.Width;
		let height = SwapChain.Height;
		let clearColor = mConfig.ClearColor;

		// Add forward pass through the render graph
		mRenderGraph.AddGraphicsPass("ForwardPass")
			.SetColorAttachment(0, swapChainHandle, .Clear, .Store, clearColor)
			.SetExecute(new (ctx) =>
			{
				ctx.RenderPass.SetViewport(0, 0, width, height, 0, 1);
				ctx.RenderPass.SetScissorRect(0, 0, width, height);
				ctx.RenderPass.SetPipeline(pipeline);
				ctx.RenderPass.SetBindGroup(0, bindGroup);
				ctx.RenderPass.SetVertexBuffer(0, vertexBuffer, 0);
				ctx.RenderPass.Draw(3, 1, 0, 0);
			});

		// Compile and execute
		mRenderGraph.Compile();
		mRenderGraph.Execute(encoder);

		// End frame
		mRenderGraph.EndFrame();
		mFrameIndex++;

		return true; // We handled rendering ourselves
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we use OnRenderCustom with the render graph
	}

	protected override void OnCleanup()
	{
		if (mRenderGraph != null) delete mRenderGraph;
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
		let app = scope RendererTriangleSample();
		return app.Run();
	}
}
