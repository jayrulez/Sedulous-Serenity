namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;
using Sedulous.Mathematics;

/// Uniform data for particle rendering.
[CRepr]
struct ParticleUniforms
{
	/// Render mode: 0=Billboard, 1=StretchedBillboard, 2=HorizontalBillboard, 3=VerticalBillboard
	public uint32 RenderMode;
	public float StretchFactor;
	public float MinStretchLength;
	public uint32 UseTexture;

	public static Self Default => .()
	{
		RenderMode = 0,
		StretchFactor = 1.0f,
		MinStretchLength = 0.1f,
		UseTexture = 0
	};
}

/// Renderer for particle systems.
/// Supports multiple blend modes, textures, and render modes.
class ParticleRenderer
{
	private const int32 MAX_FRAMES = 2;

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;

	// Single bind group layout: b0=camera, b1=particle uniforms, t0=texture, s0=sampler
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;

	// Pipelines for different blend modes
	private IRenderPipeline mAlphaBlendPipeline ~ delete _;
	private IRenderPipeline mAdditivePipeline ~ delete _;
	private IRenderPipeline mMultiplyPipeline ~ delete _;
	private IRenderPipeline mPremultipliedPipeline ~ delete _;

	// Per-frame resources
	private IBuffer[MAX_FRAMES] mParticleUniformBuffers ~ { for (var buf in _) delete buf; };
	private IBindGroup[MAX_FRAMES] mBindGroups ~ { for (var bg in _) delete bg; };

	// Default white texture for non-textured particles
	private ITexture mDefaultTexture ~ delete _;
	private ITextureView mDefaultTextureView ~ delete _;
	private ISampler mDefaultSampler ~ delete _;

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

		if (CreateDefaultTexture() case .Err)
			return .Err;

		if (CreateBindGroupLayouts() case .Err)
			return .Err;

		if (CreateUniformBuffers() case .Err)
			return .Err;

		if (CreateBindGroups() case .Err)
			return .Err;

		if (CreatePipelines() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	private Result<void> CreateDefaultTexture()
	{
		// Create a 1x1 white texture for non-textured particles
		TextureDescriptor texDesc = TextureDescriptor.Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);

		if (mDevice.CreateTexture(&texDesc) not case .Ok(let texture))
			return .Err;
		mDefaultTexture = texture;

		// Upload white pixel
		uint8[4] whitePixel = .(255, 255, 255, 255);
		TextureDataLayout dataLayout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
		Extent3D writeSize = .(1, 1, 1);
		mDevice.Queue.WriteTexture(mDefaultTexture, Span<uint8>(&whitePixel, 4), &dataLayout, &writeSize);

		// Create texture view
		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		if (mDevice.CreateTextureView(mDefaultTexture, &viewDesc) not case .Ok(let view))
			return .Err;
		mDefaultTextureView = view;

		// Create default sampler
		SamplerDescriptor samplerDesc = .()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge
		};
		if (mDevice.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return .Err;
		mDefaultSampler = sampler;

		return .Ok;
	}

	private Result<void> CreateBindGroupLayouts()
	{
		// Single bind group layout matching shader:
		// b0 = camera uniforms, b1 = particle uniforms, t0 = texture, s0 = sampler
		BindGroupLayoutEntry[4] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),   // b0: camera
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),   // b1: particle uniforms
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),            // t0: texture
			BindGroupLayoutEntry.Sampler(0, .Fragment)                    // s0: sampler
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mBindGroupLayout = layout;

		// Pipeline layout with single bind group
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mPipelineLayout = pipelineLayout;

		return .Ok;
	}

	private Result<void> CreateUniformBuffers()
	{
		uint64 uniformSize = sizeof(ParticleUniforms);

		for (int i = 0; i < MAX_FRAMES; i++)
		{
			BufferDescriptor bufferDesc = .(uniformSize, .Uniform, .Upload);
			if (mDevice.CreateBuffer(&bufferDesc) not case .Ok(let buffer))
				return .Err;
			mParticleUniformBuffers[i] = buffer;
		}

		return .Ok;
	}

	private Result<void> CreateBindGroups()
	{
		// Create per-frame bind groups with all bindings
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			BindGroupEntry[4] entries = .(
				BindGroupEntry.Buffer(0, mCameraBuffers[i]),         // b0: camera
				BindGroupEntry.Buffer(1, mParticleUniformBuffers[i]), // b1: particle uniforms
				BindGroupEntry.Texture(0, mDefaultTextureView),      // t0: texture
				BindGroupEntry.Sampler(0, mDefaultSampler)           // s0: sampler
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mBindGroups[i] = group;
		}

		return .Ok;
	}

	private Result<void> CreatePipelines()
	{
		// Load particle shaders
		let vertResult = mShaderLibrary.GetShader("particle", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShaderInfo = vertResult.Get();

		let fragResult = mShaderLibrary.GetShader("particle", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShaderInfo = fragResult.Get();

		// Updated ParticleVertex layout: 52 bytes
		// Position(12) + Size(8) + Color(4) + Rotation(4) + TexCoordOffset(8) + TexCoordScale(8) + Velocity2D(8)
		Sedulous.RHI.VertexAttribute[7] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float2, 12, 1),             // Size
			.(VertexFormat.UByte4Normalized, 20, 2),   // Color
			.(VertexFormat.Float, 24, 3),              // Rotation
			.(VertexFormat.Float2, 28, 4),             // TexCoordOffset
			.(VertexFormat.Float2, 36, 5),             // TexCoordScale
			.(VertexFormat.Float2, 44, 6)              // Velocity2D
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(52, vertexAttrs, .Instance)
		);

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;  // Particles don't write to depth
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		// Alpha blend pipeline
		ColorTargetState[1] alphaTargets = .(
			ColorTargetState(mColorFormat, BlendState.AlphaBlend)
		);
		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, alphaTargets) not case .Ok(let alphaPipeline))
			return .Err;
		mAlphaBlendPipeline = alphaPipeline;

		// Additive blend pipeline (srcColor * srcAlpha + dstColor)
		BlendState additiveBlend = .();
		additiveBlend.Color = .(.Add, .SrcAlpha, .One);
		additiveBlend.Alpha = .(.Add, .One, .One);
		ColorTargetState[1] additiveTargets = .(
			ColorTargetState(mColorFormat, additiveBlend)
		);
		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, additiveTargets) not case .Ok(let additivePipeline))
			return .Err;
		mAdditivePipeline = additivePipeline;

		// Multiply blend pipeline (dstColor * srcColor)
		BlendState multiplyBlend = .();
		multiplyBlend.Color = .(.Add, .Dst, .Zero);
		multiplyBlend.Alpha = .(.Add, .DstAlpha, .Zero);

		ColorTargetState[1] multiplyTargets = .(
			ColorTargetState(mColorFormat, multiplyBlend)
		);
		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, multiplyTargets) not case .Ok(let multiplyPipeline))
			return .Err;
		mMultiplyPipeline = multiplyPipeline;

		// Premultiplied alpha pipeline
		BlendState premultBlend = .();
		premultBlend.Color = .(.Add, .One, .OneMinusSrcAlpha);
		premultBlend.Alpha = .(.Add, .One, .OneMinusSrcAlpha);

		ColorTargetState[1] premultTargets = .(
			ColorTargetState(mColorFormat, premultBlend)
		);
		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, premultTargets) not case .Ok(let premultPipeline))
			return .Err;
		mPremultipliedPipeline = premultPipeline;

		return .Ok;
	}

	private Result<IRenderPipeline> CreatePipelineWithTargets(
		IShaderModule vertShader, IShaderModule fragShader,
		Span<VertexBufferLayout> vertexBuffers,
		DepthStencilState depthState,
		Span<ColorTargetState> colorTargets)
	{
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader, "main"),
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
		return .Ok(pipeline);
	}

	private IRenderPipeline GetPipelineForBlendMode(ParticleBlendMode blendMode)
	{
		switch (blendMode)
		{
		case .Additive: return mAdditivePipeline;
		case .Multiply: return mMultiplyPipeline;
		case .Premultiplied: return mPremultipliedPipeline;
		default: return mAlphaBlendPipeline;
		}
	}

	/// Updates the particle uniform buffer for a specific render configuration.
	public void UpdateUniforms(int32 frameIndex, ParticleEmitterConfig config)
	{
		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		ParticleUniforms uniforms = .();
		uniforms.RenderMode = (uint32)config.RenderMode;
		uniforms.StretchFactor = config.StretchFactor;
		uniforms.MinStretchLength = config.MinStretchLength;
		uniforms.UseTexture = config.Texture != null ? 1 : 0;

		Span<uint8> data = .((uint8*)&uniforms, sizeof(ParticleUniforms));
		mDevice.Queue.WriteBuffer(mParticleUniformBuffers[frameIndex], 0, data);
	}

	/// Renders particles from a single particle system.
	public void Render(IRenderPassEncoder renderPass, int32 frameIndex, ParticleSystem particleSystem)
	{
		if (!mInitialized || particleSystem == null)
			return;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		let particleCount = particleSystem.ParticleCount;
		if (particleCount == 0)
			return;

		let config = particleSystem.Config;
		if (config == null)
			return;

		// Update uniforms
		UpdateUniforms(frameIndex, config);

		// Select pipeline based on blend mode
		let pipeline = GetPipelineForBlendMode(config.BlendMode);
		if (pipeline == null)
			return;

		renderPass.SetPipeline(pipeline);
		renderPass.SetBindGroup(0, mBindGroups[frameIndex]);

		renderPass.SetVertexBuffer(0, particleSystem.VertexBuffer, 0);
		renderPass.SetIndexBuffer(particleSystem.IndexBuffer, .UInt16, 0);
		renderPass.DrawIndexed(6, (uint32)particleCount, 0, 0, 0);
	}

	/// Renders particles from multiple particle emitter proxies.
	public void RenderEmitters(IRenderPassEncoder renderPass, int32 frameIndex, List<ParticleEmitterProxy*> emitters)
	{
		if (!mInitialized || emitters == null || emitters.Count == 0)
			return;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		IRenderPipeline currentPipeline = null;

		for (let proxy in emitters)
		{
			if (!proxy.IsVisible || !proxy.HasParticles)
				continue;

			let particleSystem = proxy.System;
			if (particleSystem == null)
				continue;

			let config = particleSystem.Config;
			if (config == null)
				continue;

			// Update uniforms for this emitter
			UpdateUniforms(frameIndex, config);

			// Switch pipeline if blend mode changed
			let pipeline = GetPipelineForBlendMode(config.BlendMode);
			if (pipeline != currentPipeline)
			{
				renderPass.SetPipeline(pipeline);
				currentPipeline = pipeline;
			}

			renderPass.SetBindGroup(0, mBindGroups[frameIndex]);

			renderPass.SetVertexBuffer(0, particleSystem.VertexBuffer, 0);
			renderPass.SetIndexBuffer(particleSystem.IndexBuffer, .UInt16, 0);
			renderPass.DrawIndexed(6, (uint32)particleSystem.ParticleCount, 0, 0, 0);
		}
	}

	/// Returns true if the renderer is fully initialized with pipelines.
	public bool IsInitialized => mInitialized && mAlphaBlendPipeline != null;
}
