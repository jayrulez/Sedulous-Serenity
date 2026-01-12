namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;
using Sedulous.Mathematics;

/// Renderer for particle systems.
/// Owns the particle pipeline and handles rendering from ParticleSystem instances.
class ParticleRenderer
{
	private const int32 MAX_FRAMES = 2;

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;

	// Pipeline resources
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IRenderPipeline mPipeline ~ delete _;
	private IBindGroup[MAX_FRAMES] mBindGroups ~ { for (var bg in _) delete bg; };

	// Per-frame camera buffers (references, not owned)
	private IBuffer[MAX_FRAMES] mCameraBuffers;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mInitialized = false;

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Initializes the particle renderer with pipeline resources.
	public Result<void> Initialize(ShaderLibrary shaderLibrary,
		IBuffer[MAX_FRAMES] cameraBuffers, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		if (mDevice == null)
			return .Err;

		mShaderLibrary = shaderLibrary;
		mCameraBuffers = cameraBuffers;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		if (CreatePipeline() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	private Result<void> CreatePipeline()
	{
		// Load particle shaders
		let vertResult = mShaderLibrary.GetShader("particle", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = mShaderLibrary.GetShader("particle", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// Bind group layout: b0=camera uniforms
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mPipelineLayout = pipelineLayout;

		// Create per-frame bind groups
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			BindGroupEntry[1] entries = .(
				BindGroupEntry.Buffer(0, mCameraBuffers[i])
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mBindGroups[i] = group;
		}

		// ParticleVertex: Position(12) + Size(8) + Color(4) + Rotation(4) = 28 bytes
		Sedulous.RHI.VertexAttribute[4] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float2, 12, 1),             // Size
			.(VertexFormat.UByte4Normalized, 20, 2),   // Color
			.(VertexFormat.Float, 24, 3)               // Rotation
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(28, vertexAttrs, .Instance)
		);

		ColorTargetState[1] colorTargets = .(
			ColorTargetState(mColorFormat, .AlphaBlend)
		);

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;  // Particles don't write to depth
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (mDevice.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mPipeline = pipeline;

		return .Ok;
	}

	/// Renders particles from a single particle system.
	public void Render(IRenderPassEncoder renderPass, int32 frameIndex, ParticleSystem particleSystem)
	{
		if (!mInitialized || mPipeline == null || particleSystem == null)
			return;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		let particleCount = particleSystem.ParticleCount;
		if (particleCount == 0)
			return;

		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroups[frameIndex]);
		renderPass.SetVertexBuffer(0, particleSystem.VertexBuffer, 0);
		renderPass.SetIndexBuffer(particleSystem.IndexBuffer, .UInt16, 0);
		renderPass.DrawIndexed(6, (uint32)particleCount, 0, 0, 0);
	}

	/// Renders particles from multiple particle emitter proxies.
	public void RenderEmitters(IRenderPassEncoder renderPass, int32 frameIndex, List<ParticleEmitterProxy*> emitters)
	{
		if (!mInitialized || mPipeline == null || emitters == null || emitters.Count == 0)
			return;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		// Set pipeline and bind group once
		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroups[frameIndex]);

		// Render each emitter's particles
		for (let proxy in emitters)
		{
			if (!proxy.IsVisible || !proxy.HasParticles)
				continue;

			let particleSystem = proxy.System;
			if (particleSystem == null)
				continue;

			renderPass.SetVertexBuffer(0, particleSystem.VertexBuffer, 0);
			renderPass.SetIndexBuffer(particleSystem.IndexBuffer, .UInt16, 0);
			renderPass.DrawIndexed(6, (uint32)particleSystem.ParticleCount, 0, 0, 0);
		}
	}

	/// Returns true if the renderer is fully initialized with pipeline.
	public bool IsInitialized => mInitialized && mPipeline != null;
}
