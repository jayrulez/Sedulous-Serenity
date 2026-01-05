namespace RHIBindGroups;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;
using SampleFramework;

/// Vertex structure
[CRepr]
struct Vertex
{
	public float[2] Position;

	public this(float x, float y)
	{
		Position = .(x, y);
	}
}

/// Global per-frame uniforms (Set 0)
[CRepr]
struct GlobalUniforms
{
	public float Time;
	public float[3] Padding;
}

/// Per-object uniforms (Set 1, with dynamic offset)
/// Padded to 256 bytes for dynamic offset compatibility
[CRepr]
struct ObjectUniforms
{
	public Matrix Transform;  // 64 bytes
	public float[4] Color;       // 16 bytes
	public uint8[176] _padding;  // Pad to 256 bytes total
}

/// Demonstrates multiple bind groups and dynamic uniform buffer offsets.
/// - Set 0: Global per-frame data (time)
/// - Set 1: Per-object data using dynamic offset
class BindGroupsSample : RHISampleApp
{
	private const int OBJECT_COUNT = 9;  // 3x3 grid
	private const uint32 OBJECT_UNIFORM_SIZE = 256;  // Aligned size for dynamic offset

	// Vertex data
	private IBuffer mVertexBuffer;
	private IBuffer mIndexBuffer;

	// Uniform buffers
	private IBuffer mGlobalUniformBuffer;
	private IBuffer mObjectUniformBuffer;  // Contains all objects, accessed via dynamic offset

	// Shaders
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;

	// Set 0: Global uniforms (static)
	private IBindGroupLayout mGlobalBindGroupLayout;
	private IBindGroup mGlobalBindGroup;

	// Set 1: Object uniforms (dynamic offset)
	private IBindGroupLayout mObjectBindGroupLayout;
	private IBindGroup mObjectBindGroup;

	// Pipeline
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	public this() : base(.()
		{
			Title = "RHI Bind Groups & Dynamic Offsets",
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

		if (!CreateBindGroups())
			return false;

		if (!CreatePipeline())
			return false;

		Console.WriteLine(scope $"Drawing {OBJECT_COUNT} objects using dynamic offsets");
		Console.WriteLine("Set 0: Global uniforms (time)");
		Console.WriteLine("Set 1: Per-object uniforms with dynamic offset");
		return true;
	}

	private bool CreateBuffers()
	{
		// Quad vertices
		Vertex[4] vertices = .(
			.(-0.1f, -0.1f),
			.( 0.1f, -0.1f),
			.( 0.1f,  0.1f),
			.(-0.1f,  0.1f)
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

		// Global uniform buffer
		BufferDescriptor globalUniformDesc = .()
		{
			Size = (uint64)sizeof(GlobalUniforms),
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&globalUniformDesc) not case .Ok(let gub))
			return false;
		mGlobalUniformBuffer = gub;

		// Object uniform buffer - sized for all objects with alignment
		BufferDescriptor objectUniformDesc = .()
		{
			Size = (uint64)(OBJECT_UNIFORM_SIZE * OBJECT_COUNT),
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&objectUniformDesc) not case .Ok(let oub))
			return false;
		mObjectUniformBuffer = oub;

		Console.WriteLine("Buffers created");
		return true;
	}

	private bool CreateBindGroups()
	{
		// Load shaders with space0 and space1 for the two descriptor sets
		ShaderCompileOptions vertOptions = .();
		vertOptions.EntryPoint = "main";
		vertOptions.Stage = .Vertex;
		vertOptions.Target = .SPIRV;
		vertOptions.DescriptorSet = 0;  // Will handle both sets

		let compiler = scope HLSLCompiler();
		if (!compiler.IsInitialized)
			return false;

		// Compile vertex shader
		String vertSource = scope .();
		if (!ShaderUtils.ReadTextFile("shaders/bindgroups.vert.hlsl", vertSource))
			return false;

		let vertResult = compiler.Compile(vertSource, vertOptions);
		defer delete vertResult;
		if (!vertResult.Success)
		{
			Console.WriteLine(scope $"Vertex shader compilation failed: {vertResult.Errors}");
			return false;
		}

		ShaderModuleDescriptor vertDesc = .(vertResult.Bytecode);
		if (Device.CreateShaderModule(&vertDesc) not case .Ok(let vs))
			return false;
		mVertShader = vs;

		// Compile fragment shader
		String fragSource = scope .();
		if (!ShaderUtils.ReadTextFile("shaders/bindgroups.frag.hlsl", fragSource))
			return false;

		ShaderCompileOptions fragOptions = .();
		fragOptions.EntryPoint = "main";
		fragOptions.Stage = .Fragment;
		fragOptions.Target = .SPIRV;

		let fragResult = compiler.Compile(fragSource, fragOptions);
		defer delete fragResult;
		if (!fragResult.Success)
		{
			Console.WriteLine(scope $"Fragment shader compilation failed: {fragResult.Errors}");
			return false;
		}

		ShaderModuleDescriptor fragDesc = .(fragResult.Bytecode);
		if (Device.CreateShaderModule(&fragDesc) not case .Ok(let fs))
			return false;
		mFragShader = fs;

		Console.WriteLine("Shaders compiled");

		// Set 0: Global uniforms layout (static binding)
		BindGroupLayoutEntry[1] globalLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor globalLayoutDesc = .(globalLayoutEntries);
		if (Device.CreateBindGroupLayout(&globalLayoutDesc) not case .Ok(let globalLayout))
			return false;
		mGlobalBindGroupLayout = globalLayout;

		// Set 1: Object uniforms layout (dynamic offset)
		BindGroupLayoutEntry[1] objectLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex, dynamicOffset: true)
		);
		BindGroupLayoutDescriptor objectLayoutDesc = .(objectLayoutEntries);
		if (Device.CreateBindGroupLayout(&objectLayoutDesc) not case .Ok(let objectLayout))
			return false;
		mObjectBindGroupLayout = objectLayout;

		// Create bind groups
		BindGroupEntry[1] globalEntries = .(
			BindGroupEntry.Buffer(0, mGlobalUniformBuffer)
		);
		BindGroupDescriptor globalBindGroupDesc = .(mGlobalBindGroupLayout, globalEntries);
		if (Device.CreateBindGroup(&globalBindGroupDesc) not case .Ok(let globalGroup))
			return false;
		mGlobalBindGroup = globalGroup;

		// For dynamic offset, we bind the full buffer but specify range = OBJECT_UNIFORM_SIZE
		BindGroupEntry[1] objectEntries = .(
			BindGroupEntry.Buffer(0, mObjectUniformBuffer, 0, OBJECT_UNIFORM_SIZE)
		);
		BindGroupDescriptor objectBindGroupDesc = .(mObjectBindGroupLayout, objectEntries);
		if (Device.CreateBindGroup(&objectBindGroupDesc) not case .Ok(let objectGroup))
			return false;
		mObjectBindGroup = objectGroup;

		Console.WriteLine("Bind groups created");
		return true;
	}

	private bool CreatePipeline()
	{
		// Pipeline layout with two bind group layouts
		IBindGroupLayout[2] layouts = .(mGlobalBindGroupLayout, mObjectBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		// Vertex attributes
		VertexAttribute[1] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0)
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
		// Update global uniforms
		GlobalUniforms globalUniforms = .() { Time = totalTime };
		Span<uint8> globalData = .((uint8*)&globalUniforms, sizeof(GlobalUniforms));
		Device.Queue.WriteBuffer(mGlobalUniformBuffer, 0, globalData);

		// Update per-object uniforms
		int gridSize = (int)Math.Sqrt(OBJECT_COUNT);
		for (int i = 0; i < OBJECT_COUNT; i++)
		{
			int x = i % gridSize;
			int y = i / gridSize;

			// Position in grid
			float px = -0.6f + (float)x * 0.6f;
			float py = -0.6f + (float)y * 0.6f;

			// Rotation based on time and position
			float rotation = totalTime * (1.0f + (float)i * 0.2f);

			// Create transform matrix
			Matrix transform = Matrix.CreateRotationZ(rotation) * Matrix.CreateTranslation(px, py, 0);

			// Color based on position
			float r = (float)x / (gridSize - 1);
			float g = (float)y / (gridSize - 1);
			float b = 1.0f - (r + g) * 0.5f;

			ObjectUniforms objectUniforms = .()
			{
				Transform = transform,
				Color = .(r, g, b, 1.0f)
			};

			// Write to the appropriate offset in the buffer
			uint64 offset = (uint64)(OBJECT_UNIFORM_SIZE * i);
			Span<uint8> objectData = .((uint8*)&objectUniforms, sizeof(ObjectUniforms));
			Device.Queue.WriteBuffer(mObjectUniformBuffer, offset, objectData);
		}
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetPipeline(mPipeline);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);

		// Set global bind group (set 0) - no dynamic offset
		renderPass.SetBindGroup(0, mGlobalBindGroup);

		// Draw each object with a different dynamic offset
		for (int i = 0; i < OBJECT_COUNT; i++)
		{
			// Calculate offset for this object
			uint32[1] dynamicOffsets = .((uint32)(OBJECT_UNIFORM_SIZE * i));

			// Set object bind group (set 1) with dynamic offset
			renderPass.SetBindGroup(1, mObjectBindGroup, dynamicOffsets);

			// Draw the quad
			renderPass.DrawIndexed(6, 1, 0, 0, 0);
		}
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mObjectBindGroup != null) delete mObjectBindGroup;
		if (mObjectBindGroupLayout != null) delete mObjectBindGroupLayout;
		if (mGlobalBindGroup != null) delete mGlobalBindGroup;
		if (mGlobalBindGroupLayout != null) delete mGlobalBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mObjectUniformBuffer != null) delete mObjectUniformBuffer;
		if (mGlobalUniformBuffer != null) delete mGlobalUniformBuffer;
		if (mIndexBuffer != null) delete mIndexBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope BindGroupsSample();
		return app.Run();
	}
}
