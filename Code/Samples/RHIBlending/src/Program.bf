namespace RHIBlending;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;

/// Vertex with 2D position and RGBA color
[CRepr]
struct Vertex
{
	public float[2] Position;
	public float[4] Color;  // RGBA with alpha

	public this(float x, float y, float r, float g, float b, float a)
	{
		Position = .(x, y);
		Color = .(r, g, b, a);
	}

}

/// Demonstrates alpha blending with overlapping transparent quads.
class BlendingSample : RHISampleApp
{
	private IBuffer mVertexBuffer;
	private IBuffer mIndexBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	public this() : base(.()
		{
			Title = "RHI Alpha Blending Test",
			Width = 800,
			Height = 600,
			ClearColor = .(0.2f, 0.2f, 0.2f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateBuffers())
			return false;

		if (!CreatePipeline())
			return false;

		return true;
	}

	private bool CreateBuffers()
	{
		// Create overlapping quads with varying transparency
		// Drawn back to front for correct blending
		Vertex[12] vertices = .(
			// Red quad (back-left) - 70% opaque
			.(-0.8f, -0.6f, 1.0f, 0.2f, 0.2f, 0.7f),
			.( 0.0f, -0.6f, 1.0f, 0.2f, 0.2f, 0.7f),
			.( 0.0f,  0.4f, 1.0f, 0.2f, 0.2f, 0.7f),
			.(-0.8f,  0.4f, 1.0f, 0.2f, 0.2f, 0.7f),

			// Green quad (middle) - 50% opaque
			.(-0.4f, -0.4f, 0.2f, 1.0f, 0.2f, 0.5f),
			.( 0.4f, -0.4f, 0.2f, 1.0f, 0.2f, 0.5f),
			.( 0.4f,  0.6f, 0.2f, 1.0f, 0.2f, 0.5f),
			.(-0.4f,  0.6f, 0.2f, 1.0f, 0.2f, 0.5f),

			// Blue quad (front-right) - 60% opaque
			.( 0.0f, -0.5f, 0.2f, 0.2f, 1.0f, 0.6f),
			.( 0.8f, -0.5f, 0.2f, 0.2f, 1.0f, 0.6f),
			.( 0.8f,  0.5f, 0.2f, 0.2f, 1.0f, 0.6f),
			.( 0.0f,  0.5f, 0.2f, 0.2f, 1.0f, 0.6f)
		);

		// Index buffer for three quads
		uint16[18] indices = .(
			// Red quad
			0, 1, 2,  0, 2, 3,
			// Green quad
			4, 5, 6,  4, 6, 7,
			// Blue quad
			8, 9, 10,  8, 10, 11
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

		Console.WriteLine("Buffers created");
		return true;
	}

	private bool CreatePipeline()
	{
		// Load shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/blend");
		if (shaderResult case .Err)
			return false;

		(mVertShader, mFragShader) = shaderResult.Get();
		Console.WriteLine("Shaders compiled");

		// Create empty pipeline layout (no bindings)
		PipelineLayoutDescriptor pipelineLayoutDesc = .();
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		// Vertex attributes - must be in same scope as pipeline creation
		VertexAttribute[2] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),   // Position at location 0
			.(VertexFormat.Float4, 8, 1)    // Color at location 1
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// Color target with alpha blending enabled
		// Standard alpha blending: result = src.rgb * src.a + dst.rgb * (1 - src.a)
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format, .AlphaBlend));

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

		Console.WriteLine("Pipeline created with alpha blending");
		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetPipeline(mPipeline);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);
		// Draw all three quads (18 indices total)
		renderPass.DrawIndexed(18, 1, 0, 0, 0);
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mIndexBuffer != null) delete mIndexBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope BlendingSample();
		return app.Run();
	}
}
