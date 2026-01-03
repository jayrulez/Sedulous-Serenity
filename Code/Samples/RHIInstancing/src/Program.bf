namespace RHIInstancing;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using RHI.SampleFramework;

/// Per-vertex data (triangle shape)
[CRepr]
struct Vertex
{
	public float[2] Position;

	public this(float x, float y)
	{
		Position = .(x, y);
	}
}

/// Per-instance data
[CRepr]
struct InstanceData
{
	public float[2] Offset;
	public float[4] Color;
	public float Rotation;
	public float _pad;  // Padding for alignment

	public this(float x, float y, float r, float g, float b, float a, float rot)
	{
		Offset = .(x, y);
		Color = .(r, g, b, a);
		Rotation = rot;
		_pad = 0;
	}
}

/// Demonstrates instanced rendering with many small triangles.
class InstancingSample : RHISampleApp
{
	private const int INSTANCE_COUNT = 100;
	private const int GRID_SIZE = 10;

	private IBuffer mVertexBuffer;
	private IBuffer mInstanceBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	private InstanceData[INSTANCE_COUNT] mInstanceData;

	public this() : base(.()
		{
			Title = "RHI Instanced Rendering",
			Width = 800,
			Height = 600,
			ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateBuffers())
			return false;

		if (!CreatePipeline())
			return false;

		Console.WriteLine(scope $"Rendering {INSTANCE_COUNT} instances");
		return true;
	}

	private bool CreateBuffers()
	{
		// Small triangle vertices
		float size = 0.08f;
		Vertex[3] vertices = .(
			.(0.0f, -size),      // Top
			.(size, size),       // Bottom right
			.(-size, size)       // Bottom left
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

		// Generate instance data in a grid pattern
		int index = 0;
		for (int y = 0; y < GRID_SIZE && index < INSTANCE_COUNT; y++)
		{
			for (int x = 0; x < GRID_SIZE && index < INSTANCE_COUNT; x++)
			{
				// Position in grid (-0.8 to 0.8 range)
				float px = -0.8f + (float)x * 1.6f / (GRID_SIZE - 1);
				float py = -0.8f + (float)y * 1.6f / (GRID_SIZE - 1);

				// Color based on position (creates a gradient)
				float r = (float)x / (GRID_SIZE - 1);
				float g = (float)y / (GRID_SIZE - 1);
				float b = 1.0f - (r + g) * 0.5f;

				mInstanceData[index] = .(px, py, r, g, b, 1.0f, 0.0f);
				index++;
			}
		}

		// Create instance buffer
		BufferDescriptor instanceDesc = .()
		{
			Size = (uint64)(sizeof(InstanceData) * INSTANCE_COUNT),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&instanceDesc) not case .Ok(let ib))
			return false;
		mInstanceBuffer = ib;

		Console.WriteLine("Buffers created");
		return true;
	}

	private bool CreatePipeline()
	{
		// Load shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/instancing");
		if (shaderResult case .Err)
			return false;

		(mVertShader, mFragShader) = shaderResult.Get();
		Console.WriteLine("Shaders compiled");

		// Create empty pipeline layout
		PipelineLayoutDescriptor pipelineLayoutDesc = .();
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		// Vertex attributes for per-vertex data (buffer 0)
		VertexAttribute[1] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0)    // Position at location 0
		);

		// Instance attributes for per-instance data (buffer 1)
		VertexAttribute[3] instanceAttributes = .(
			.(VertexFormat.Float2, 0, 1),   // Offset at location 1
			.(VertexFormat.Float4, 8, 2),   // Color at location 2
			.(VertexFormat.Float, 24, 3)    // Rotation at location 3
		);

		// Two vertex buffer layouts: per-vertex and per-instance
		VertexBufferLayout[2] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes, .Vertex),
			.((uint64)sizeof(InstanceData), instanceAttributes, .Instance)
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
		// Update instance rotations based on time
		for (int i = 0; i < INSTANCE_COUNT; i++)
		{
			// Each instance rotates at a slightly different speed
			float speed = 1.0f + (float)i * 0.02f;
			mInstanceData[i].Rotation = totalTime * speed;
		}

		// Upload updated instance data
		Span<uint8> instanceData = .((uint8*)&mInstanceData, sizeof(InstanceData) * INSTANCE_COUNT);
		Device.Queue.WriteBuffer(mInstanceBuffer, 0, instanceData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetPipeline(mPipeline);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.SetVertexBuffer(1, mInstanceBuffer, 0);
		// Draw 3 vertices, INSTANCE_COUNT instances
		renderPass.Draw(3, (.)INSTANCE_COUNT, 0, 0);
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mInstanceBuffer != null) delete mInstanceBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope InstancingSample();
		return app.Run();
	}
}
