namespace RHICompute;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;

/// Particle data structure (must match shader)
[CRepr]
struct Particle
{
	public float[2] Position;
	public float[2] Velocity;
	public float[4] Color;
}

/// Simulation parameters (must match shader cbuffer)
[CRepr]
struct SimParams
{
	public float DeltaTime;
	public float TotalTime;
	public float[2] Bounds;
}

/// Small triangle vertex for rendering particles
[CRepr]
struct Vertex
{
	public float[2] Position;

	public this(float x, float y)
	{
		Position = .(x, y);
	}
}

/// Demonstrates compute shaders for GPU particle simulation.
class ComputeSample : RHISampleApp
{
	private const int PARTICLE_COUNT = 256;
	// Need 3 frames of command buffers since OnUpdate runs before AcquireNextImage
	private const int COMPUTE_BUFFER_COUNT = 3;

	// Compute resources
	private IBuffer mParticleBuffer;
	private IBuffer mSimParamsBuffer;
	private IShaderModule mComputeShader;
	private IBindGroupLayout mComputeBindGroupLayout;
	private IBindGroup mComputeBindGroup;
	private IPipelineLayout mComputePipelineLayout;
	private IComputePipeline mComputePipeline;

	// Per-frame compute command buffers (need to track for proper lifetime)
	private ICommandBuffer[COMPUTE_BUFFER_COUNT] mComputeCommandBuffers;
	private int mComputeFrameIndex = 0;

	// Render resources
	private IBuffer mVertexBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mRenderBindGroupLayout;
	private IBindGroup mRenderBindGroup;
	private IPipelineLayout mRenderPipelineLayout;
	private IRenderPipeline mRenderPipeline;

	public this() : base(.()
		{
			Title = "RHI Compute Shader",
			Width = 800,
			Height = 600,
			ClearColor = .(0.05f, 0.05f, 0.1f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateBuffers())
			return false;

		if (!CreateComputePipeline())
			return false;

		if (!CreateRenderPipeline())
			return false;

		Console.WriteLine(scope $"Simulating {PARTICLE_COUNT} particles on GPU");
		return true;
	}

	private bool CreateBuffers()
	{
		// Initialize particles with random positions and velocities
		Particle[PARTICLE_COUNT] particles = ?;
		Random rand = scope .(42);

		for (int i = 0; i < PARTICLE_COUNT; i++)
		{
			float x = (float)rand.NextDouble() * 1.6f - 0.8f;
			float y = (float)rand.NextDouble() * 1.6f - 0.8f;
			float vx = (float)rand.NextDouble() * 0.4f - 0.2f;
			float vy = (float)rand.NextDouble() * 0.4f - 0.2f;

			// Color based on initial position
			float r = (x + 0.8f) / 1.6f;
			float g = (y + 0.8f) / 1.6f;
			float b = 1.0f - (r + g) * 0.5f;

			particles[i] = .()
			{
				Position = .(x, y),
				Velocity = .(vx, vy),
				Color = .(r, g, b, 1.0f)
			};
		}

		// Create particle storage buffer
		BufferDescriptor particleDesc = .()
		{
			Size = (uint64)(sizeof(Particle) * PARTICLE_COUNT),
			Usage = .Storage | .Vertex | .CopyDst,  // Used by compute, as vertex input, and receives initial data
			MemoryAccess = .GpuOnly
		};

		if (Device.CreateBuffer(&particleDesc) not case .Ok(let pb))
			return false;
		mParticleBuffer = pb;

		// Upload initial particle data via staging
		BufferDescriptor stagingDesc = .()
		{
			Size = particleDesc.Size,
			Usage = .CopySrc,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&stagingDesc) not case .Ok(let staging))
			return false;
		defer delete staging;

		Span<uint8> particleData = .((uint8*)&particles, (int)particleDesc.Size);
		Device.Queue.WriteBuffer(staging, 0, particleData);

		// Copy staging to particle buffer
		let encoder = Device.CreateCommandEncoder();
		defer delete encoder;
		encoder.CopyBufferToBuffer(staging, 0, mParticleBuffer, 0, particleDesc.Size);
		let cmdBuffer = encoder.Finish();
		defer delete cmdBuffer;
		Device.Queue.Submit(cmdBuffer);
		Device.WaitIdle();

		// Create simulation parameters uniform buffer
		BufferDescriptor simParamsDesc = .()
		{
			Size = (uint64)sizeof(SimParams),
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&simParamsDesc) not case .Ok(let spb))
			return false;
		mSimParamsBuffer = spb;

		// Create small triangle vertices for rendering particles
		float size = 0.02f;
		Vertex[3] vertices = .(
			.(0.0f, -size),
			.(size, size),
			.(-size, size)
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

		Console.WriteLine("Buffers created");
		return true;
	}

	private bool CreateComputePipeline()
	{
		// Load compute shader - automatic binding shifts are applied by default
		// b0 -> binding 0, u0 -> binding 2000
		if (ShaderUtils.LoadShader(Device, "shaders/particles.comp.hlsl", "main", .Compute) case .Ok(let shader))
			mComputeShader = shader;
		else
			return false;

		Console.WriteLine("Compute shader compiled");

		// Create bind group layout for compute
		// Use binding 0 for all - the RHI applies shifts based on resource type
		BindGroupLayoutEntry[2] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Compute),           // b0 -> Vulkan binding 0
			BindGroupLayoutEntry.StorageBufferReadWrite(0, .Compute)   // u0 -> Vulkan binding 2000
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mComputeBindGroupLayout = layout;

		// Create bind group - use binding 0 for all resource types
		BindGroupEntry[2] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mSimParamsBuffer),
			BindGroupEntry.Buffer(0, mParticleBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mComputeBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mComputeBindGroup = group;

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mComputeBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mComputePipelineLayout = pipelineLayout;

		// Create compute pipeline
		ComputePipelineDescriptor pipelineDesc = .(mComputePipelineLayout, mComputeShader, "main");
		if (Device.CreateComputePipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mComputePipeline = pipeline;

		Console.WriteLine("Compute pipeline created");
		return true;
	}

	private bool CreateRenderPipeline()
	{
		// Load render shaders - automatic binding shifts are applied by default
		// t0 -> binding 1000
		if (ShaderUtils.LoadShader(Device, "shaders/particle_render.vert.hlsl", "main", .Vertex) case .Ok(let vs))
			mVertShader = vs;
		else
			return false;

		if (ShaderUtils.LoadShader(Device, "shaders/particle_render.frag.hlsl", "main", .Fragment) case .Ok(let fs))
			mFragShader = fs;
		else
			return false;

		Console.WriteLine("Render shaders compiled");

		// Create bind group layout for rendering
		// Use binding 0 - the RHI applies shifts based on resource type
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.StorageBuffer(0, .Vertex)  // t0 -> Vulkan binding 1000
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mRenderBindGroupLayout = layout;

		// Create bind group
		BindGroupEntry[1] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mParticleBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mRenderBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mRenderBindGroup = group;

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mRenderBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mRenderPipelineLayout = pipelineLayout;

		// Vertex attributes for triangle shape (per-vertex, not instanced here)
		VertexAttribute[1] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0)  // Position at location 0
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// Color target
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format, .AlphaBlend));

		// Pipeline descriptor
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mRenderPipelineLayout,
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
		mRenderPipeline = pipeline;

		Console.WriteLine("Render pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Use our own frame counter since OnUpdate runs BEFORE AcquireNextImage
		// With 3 buffer slots, the command buffer at mComputeFrameIndex is from 3 frames ago
		// and guaranteed to be complete
		let frameIndex = mComputeFrameIndex;
		mComputeFrameIndex = (mComputeFrameIndex + 1) % COMPUTE_BUFFER_COUNT;

		// Clean up previous compute command buffer for this frame slot
		// (GPU is guaranteed to be done with it after 3 frames)
		if (mComputeCommandBuffers[frameIndex] != null)
		{
			delete mComputeCommandBuffers[frameIndex];
			mComputeCommandBuffers[frameIndex] = null;
		}

		// Update simulation parameters
		SimParams simParams = .()
		{
			DeltaTime = deltaTime,
			TotalTime = totalTime,
			Bounds = .(0.95f, 0.95f)
		};
		Span<uint8> simData = .((uint8*)&simParams, sizeof(SimParams));
		Device.Queue.WriteBuffer(mSimParamsBuffer, 0, simData);

		// Run compute shader to update particles
		let encoder = Device.CreateCommandEncoder();
		defer delete encoder;

		let computePass = encoder.BeginComputePass();
		defer delete computePass;

		computePass.SetPipeline(mComputePipeline);
		computePass.SetBindGroup(0, mComputeBindGroup);

		// Dispatch enough workgroups to cover all particles
		// 64 threads per workgroup, so we need ceil(PARTICLE_COUNT / 64) workgroups
		uint32 workgroupCount = (PARTICLE_COUNT + 63) / 64;
		computePass.Dispatch(workgroupCount, 1, 1);
		computePass.End();

		let cmdBuffer = encoder.Finish();
		// Store for later deletion (after GPU is done)
		mComputeCommandBuffers[frameIndex] = cmdBuffer;
		Device.Queue.Submit(cmdBuffer);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetPipeline(mRenderPipeline);
		renderPass.SetBindGroup(0, mRenderBindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);

		// Draw all particles with a single instanced draw call
		// 3 vertices per triangle, PARTICLE_COUNT instances
		renderPass.Draw(3, (.)PARTICLE_COUNT, 0, 0);
	}

	protected override void OnCleanup()
	{
		// Clean up compute command buffers
		for (int i = 0; i < COMPUTE_BUFFER_COUNT; i++)
		{
			if (mComputeCommandBuffers[i] != null)
			{
				delete mComputeCommandBuffers[i];
				mComputeCommandBuffers[i] = null;
			}
		}

		// Render resources
		if (mRenderPipeline != null) delete mRenderPipeline;
		if (mRenderPipelineLayout != null) delete mRenderPipelineLayout;
		if (mRenderBindGroup != null) delete mRenderBindGroup;
		if (mRenderBindGroupLayout != null) delete mRenderBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mVertexBuffer != null) delete mVertexBuffer;

		// Compute resources
		if (mComputePipeline != null) delete mComputePipeline;
		if (mComputePipelineLayout != null) delete mComputePipelineLayout;
		if (mComputeBindGroup != null) delete mComputeBindGroup;
		if (mComputeBindGroupLayout != null) delete mComputeBindGroupLayout;
		if (mComputeShader != null) delete mComputeShader;
		if (mSimParamsBuffer != null) delete mSimParamsBuffer;
		if (mParticleBuffer != null) delete mParticleBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope ComputeSample();
		return app.Run();
	}
}
