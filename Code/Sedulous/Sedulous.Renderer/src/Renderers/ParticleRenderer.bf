namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
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

	// Soft particle parameters
	public uint32 SoftParticlesEnabled;
	public float SoftParticleDistance;
	public float NearPlane;
	public float FarPlane;

	public static Self Default => .()
	{
		RenderMode = 0,
		StretchFactor = 1.0f,
		MinStretchLength = 0.1f,
		UseTexture = 0,
		SoftParticlesEnabled = 0,
		SoftParticleDistance = 0.5f,
		NearPlane = 0.1f,
		FarPlane = 1000.0f
	};
}

/// Renderer for particle systems.
/// Supports multiple blend modes, textures, and render modes.
class ParticleRenderer
{

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;

	// Single bind group layout: b0=camera, b1=particle uniforms, t0=texture, s0=sampler
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;

	// Pipelines for different blend modes (with depth attachment)
	private IRenderPipeline mAlphaBlendPipeline ~ delete _;
	private IRenderPipeline mAdditivePipeline ~ delete _;
	private IRenderPipeline mMultiplyPipeline ~ delete _;
	private IRenderPipeline mPremultipliedPipeline ~ delete _;

	// No-depth pipelines for transparent pass (soft particles)
	private IRenderPipeline mAlphaBlendNoDepthPipeline ~ delete _;
	private IRenderPipeline mAdditiveNoDepthPipeline ~ delete _;
	private IRenderPipeline mMultiplyNoDepthPipeline ~ delete _;
	private IRenderPipeline mPremultipliedNoDepthPipeline ~ delete _;

	// Per-frame resources
	private IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mParticleUniformBuffers ~ { for (var buf in _) delete buf; };
	private IBindGroup[FrameConfig.MAX_FRAMES_IN_FLIGHT] mBindGroups ~ { for (var bg in _) delete bg; };

	// Default white texture for non-textured particles
	private ITexture mDefaultTexture ~ delete _;
	private ITextureView mDefaultTextureView ~ delete _;
	private ISampler mDefaultSampler ~ delete _;

	// Default depth texture for non-soft particles (1x1 white, depth=1.0)
	private ITexture mDefaultDepthTexture ~ delete _;
	private ITextureView mDefaultDepthTextureView ~ delete _;
	private ISampler mDepthSampler ~ delete _;

	// Per-frame camera buffers (references, not owned)
	private IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mCameraBuffers;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mInitialized = false;

	// Statistics (reset per RenderEmitters call)
	private int32 mLastDrawCallCount = 0;
	private int32 mLastPipelineSwitchCount = 0;

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Initializes the particle renderer with pipeline resources.
	public Result<void> Initialize(ShaderLibrary shaderLibrary,
		IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] cameraBuffers, TextureFormat colorFormat, TextureFormat depthFormat)
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

		// Create default depth texture (R32Float with depth=1.0 = far plane)
		TextureDescriptor depthTexDesc = TextureDescriptor.Texture2D(1, 1, .R32Float, .Sampled | .CopyDst);
		if (mDevice.CreateTexture(&depthTexDesc) not case .Ok(let depthTex))
			return .Err;
		mDefaultDepthTexture = depthTex;

		// Upload max depth (1.0)
		float maxDepth = 1.0f;
		TextureDataLayout depthDataLayout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
		mDevice.Queue.WriteTexture(mDefaultDepthTexture, Span<uint8>((uint8*)&maxDepth, 4), &depthDataLayout, &writeSize);

		// Create depth texture view
		TextureViewDescriptor depthViewDesc = .() { Format = .R32Float };
		if (mDevice.CreateTextureView(mDefaultDepthTexture, &depthViewDesc) not case .Ok(let depthView))
			return .Err;
		mDefaultDepthTextureView = depthView;

		// Create depth sampler (point sampling for depth)
		SamplerDescriptor depthSamplerDesc = .()
		{
			MinFilter = .Nearest,
			MagFilter = .Nearest,
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge
		};
		if (mDevice.CreateSampler(&depthSamplerDesc) not case .Ok(let depthSampler))
			return .Err;
		mDepthSampler = depthSampler;

		return .Ok;
	}

	private Result<void> CreateBindGroupLayouts()
	{
		// Single bind group layout matching shader:
		// b0 = camera uniforms, b1 = particle uniforms
		// t0 = particle texture, s0 = particle sampler
		// t1 = depth texture (for soft particles), s1 = depth sampler
		BindGroupLayoutEntry[6] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),   // b0: camera
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),   // b1: particle uniforms
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),            // t0: particle texture
			BindGroupLayoutEntry.Sampler(0, .Fragment),                   // s0: particle sampler
			BindGroupLayoutEntry.SampledTexture(1, .Fragment),            // t1: depth texture
			BindGroupLayoutEntry.Sampler(1, .Fragment)                    // s1: depth sampler
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

		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
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
		// Create per-frame bind groups with all bindings (using default depth texture)
		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			BindGroupEntry[6] entries = .(
				BindGroupEntry.Buffer(0, mCameraBuffers[i]),           // b0: camera
				BindGroupEntry.Buffer(1, mParticleUniformBuffers[i]),  // b1: particle uniforms
				BindGroupEntry.Texture(0, mDefaultTextureView),        // t0: particle texture
				BindGroupEntry.Sampler(0, mDefaultSampler),            // s0: particle sampler
				BindGroupEntry.Texture(1, mDefaultDepthTextureView),   // t1: depth texture (default)
				BindGroupEntry.Sampler(1, mDepthSampler)               // s1: depth sampler
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mBindGroups[i] = group;
		}

		return .Ok;
	}

	/// Creates a bind group with an actual depth texture for soft particles.
	/// The caller is responsible for deleting the returned bind group.
	public Result<IBindGroup> CreateSoftParticleBindGroup(int32 frameIndex, ITextureView depthTextureView)
	{
		if (frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return .Err;

		BindGroupEntry[6] entries = .(
			BindGroupEntry.Buffer(0, mCameraBuffers[frameIndex]),           // b0: camera
			BindGroupEntry.Buffer(1, mParticleUniformBuffers[frameIndex]),  // b1: particle uniforms
			BindGroupEntry.Texture(0, mDefaultTextureView),                 // t0: particle texture
			BindGroupEntry.Sampler(0, mDefaultSampler),                     // s0: particle sampler
			BindGroupEntry.Texture(1, depthTextureView),                    // t1: actual depth texture
			BindGroupEntry.Sampler(1, mDepthSampler)                        // s1: depth sampler
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
		if (mDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return .Err;
		return .Ok(group);
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

		// Depth state for pipelines with depth attachment
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;  // Particles don't write to depth
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		// No-depth state for transparent pass (soft particles)
		DepthStencilState noDepthState = .();
		noDepthState.DepthTestEnabled = false;
		noDepthState.DepthWriteEnabled = false;
		noDepthState.Format = .Undefined;

		// Define blend states
		BlendState additiveBlend = .();
		additiveBlend.Color = .(.Add, .SrcAlpha, .One);
		additiveBlend.Alpha = .(.Add, .One, .One);

		BlendState multiplyBlend = .();
		multiplyBlend.Color = .(.Add, .Dst, .Zero);
		multiplyBlend.Alpha = .(.Add, .DstAlpha, .Zero);

		BlendState premultBlend = .();
		premultBlend.Color = .(.Add, .One, .OneMinusSrcAlpha);
		premultBlend.Alpha = .(.Add, .One, .OneMinusSrcAlpha);

		// Create pipelines WITH depth attachment
		ColorTargetState[1] alphaTargets = .(ColorTargetState(mColorFormat, BlendState.AlphaBlend));
		ColorTargetState[1] additiveTargets = .(ColorTargetState(mColorFormat, additiveBlend));
		ColorTargetState[1] multiplyTargets = .(ColorTargetState(mColorFormat, multiplyBlend));
		ColorTargetState[1] premultTargets = .(ColorTargetState(mColorFormat, premultBlend));

		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, alphaTargets) not case .Ok(let alphaPipeline))
			return .Err;
		mAlphaBlendPipeline = alphaPipeline;

		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, additiveTargets) not case .Ok(let additivePipeline))
			return .Err;
		mAdditivePipeline = additivePipeline;

		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, multiplyTargets) not case .Ok(let multiplyPipeline))
			return .Err;
		mMultiplyPipeline = multiplyPipeline;

		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, premultTargets) not case .Ok(let premultPipeline))
			return .Err;
		mPremultipliedPipeline = premultPipeline;

		// Create pipelines WITHOUT depth attachment (for soft particle transparent pass)
		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, noDepthState, alphaTargets) not case .Ok(let alphaNoDepthPipeline))
			return .Err;
		mAlphaBlendNoDepthPipeline = alphaNoDepthPipeline;

		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, noDepthState, additiveTargets) not case .Ok(let additiveNoDepthPipeline))
			return .Err;
		mAdditiveNoDepthPipeline = additiveNoDepthPipeline;

		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, noDepthState, multiplyTargets) not case .Ok(let multiplyNoDepthPipeline))
			return .Err;
		mMultiplyNoDepthPipeline = multiplyNoDepthPipeline;

		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, noDepthState, premultTargets) not case .Ok(let premultNoDepthPipeline))
			return .Err;
		mPremultipliedNoDepthPipeline = premultNoDepthPipeline;

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

	private IRenderPipeline GetPipelineForBlendMode(ParticleBlendMode blendMode, bool useNoDepth = false)
	{
		if (useNoDepth)
		{
			switch (blendMode)
			{
			case .Additive: return mAdditiveNoDepthPipeline;
			case .Multiply: return mMultiplyNoDepthPipeline;
			case .Premultiplied: return mPremultipliedNoDepthPipeline;
			default: return mAlphaBlendNoDepthPipeline;
			}
		}
		else
		{
			switch (blendMode)
			{
			case .Additive: return mAdditivePipeline;
			case .Multiply: return mMultiplyPipeline;
			case .Premultiplied: return mPremultipliedPipeline;
			default: return mAlphaBlendPipeline;
			}
		}
	}

	/// Updates the particle uniform buffer for a specific render configuration.
	public void UpdateUniforms(int32 frameIndex, ParticleEmitterConfig config, float nearPlane = 0.1f, float farPlane = 1000.0f)
	{
		if (frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		ParticleUniforms uniforms = .();
		uniforms.RenderMode = (uint32)config.RenderMode;
		uniforms.StretchFactor = config.StretchFactor;
		uniforms.MinStretchLength = config.MinStretchLength;
		uniforms.UseTexture = config.Texture != null ? 1 : 0;

		// Soft particle parameters
		uniforms.SoftParticlesEnabled = config.SoftParticles ? 1 : 0;
		uniforms.SoftParticleDistance = config.SoftParticleDistance;
		uniforms.NearPlane = nearPlane;
		uniforms.FarPlane = farPlane;

		Span<uint8> data = .((uint8*)&uniforms, sizeof(ParticleUniforms));
		mDevice.Queue.WriteBuffer(mParticleUniformBuffers[frameIndex], 0, data);
	}

	/// Renders particles from a single particle system.
	public void Render(IRenderPassEncoder renderPass, int32 frameIndex, ParticleSystem particleSystem,
		float nearPlane = 0.1f, float farPlane = 1000.0f, IBindGroup softParticleBindGroup = null)
	{
		if (!mInitialized || particleSystem == null)
			return;

		if (frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		let particleCount = particleSystem.ParticleCount;
		if (particleCount == 0)
			return;

		let config = particleSystem.Config;
		if (config == null)
			return;

		// Update uniforms
		UpdateUniforms(frameIndex, config, nearPlane, farPlane);

		// Select pipeline based on blend mode
		let pipeline = GetPipelineForBlendMode(config.BlendMode);
		if (pipeline == null)
			return;

		renderPass.SetPipeline(pipeline);

		// Use soft particle bind group if available and soft particles are enabled
		if (config.SoftParticles && softParticleBindGroup != null)
			renderPass.SetBindGroup(0, softParticleBindGroup);
		else
			renderPass.SetBindGroup(0, mBindGroups[frameIndex]);

		renderPass.SetVertexBuffer(0, particleSystem.GetVertexBuffer(frameIndex), 0);
		renderPass.SetIndexBuffer(particleSystem.IndexBuffer, .UInt16, 0);
		renderPass.DrawIndexed(6, (uint32)particleCount, 0, 0, 0);
	}

	/// Renders particles from multiple particle emitter proxies.
	/// softParticleBindGroup: Optional bind group with depth texture for soft particles
	/// useNoDepthPipelines: Use pipelines without depth attachment (for transparent pass with soft particles)
	/// nearPlane/farPlane: Camera planes for depth linearization
	/// sortByBlendMode: If true, sorts emitters by blend mode to minimize pipeline switches (default: true)
	public void RenderEmitters(IRenderPassEncoder renderPass, int32 frameIndex, List<ParticleEmitterProxy*> emitters,
		float nearPlane = 0.1f, float farPlane = 1000.0f, IBindGroup softParticleBindGroup = null, bool useNoDepthPipelines = false,
		bool sortByBlendMode = true)
	{
		if (!mInitialized || emitters == null || emitters.Count == 0)
			return;

		if (frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		// Sort emitters by blend mode to minimize pipeline switches
		// This groups AlphaBlend, Additive, Multiply, Premultiplied together
		if (sortByBlendMode && emitters.Count > 1)
		{
			emitters.Sort(scope (a, b) =>
			{
				// Primary sort: blend mode (to minimize pipeline switches)
				int32 blendA = (int32)a.BlendMode;
				int32 blendB = (int32)b.BlendMode;
				if (blendA != blendB)
					return blendA <=> blendB;

				// Secondary sort: distance (back-to-front for transparency)
				// Note: Distance sorting was already done in VisibilityResolver,
				// but we maintain it within each blend mode group
				if (a.DistanceToCamera > b.DistanceToCamera) return -1;
				if (a.DistanceToCamera < b.DistanceToCamera) return 1;
				return 0;
			});
		}

		IRenderPipeline currentPipeline = null;
		bool usingSoftBindGroup = false;
		ParticleBlendMode currentBlendMode = .AlphaBlend;
		bool firstPipeline = true;

		// Track statistics
		mLastDrawCallCount = 0;
		mLastPipelineSwitchCount = 0;

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
			UpdateUniforms(frameIndex, config, nearPlane, farPlane);

			// Switch pipeline if blend mode changed or first emitter
			if (firstPipeline || config.BlendMode != currentBlendMode)
			{
				let pipeline = GetPipelineForBlendMode(config.BlendMode, useNoDepthPipelines);
				if (pipeline != currentPipeline)
				{
					renderPass.SetPipeline(pipeline);
					currentPipeline = pipeline;
					currentBlendMode = config.BlendMode;
					mLastPipelineSwitchCount++;
				}
				firstPipeline = false;
			}

			// Use soft particle bind group if available and this emitter uses soft particles
			bool needSoftBindGroup = config.SoftParticles && softParticleBindGroup != null;
			if (needSoftBindGroup != usingSoftBindGroup || !usingSoftBindGroup)
			{
				if (needSoftBindGroup)
					renderPass.SetBindGroup(0, softParticleBindGroup);
				else
					renderPass.SetBindGroup(0, mBindGroups[frameIndex]);
				usingSoftBindGroup = needSoftBindGroup;
			}

			// Render main particle system
			if (particleSystem.ParticleCount > 0)
			{
				renderPass.SetVertexBuffer(0, particleSystem.GetVertexBuffer(frameIndex), 0);
				renderPass.SetIndexBuffer(particleSystem.IndexBuffer, .UInt16, 0);
				renderPass.DrawIndexed(6, (uint32)particleSystem.ParticleCount, 0, 0, 0);
				mLastDrawCallCount++;
			}

			// Render sub-emitter instances
			if (proxy.HasActiveSubEmitters)
			{
				let subManager = proxy.SubEmitters;
				for (let instance in subManager.ActiveInstances)
				{
					let subSystem = instance.System;
					if (subSystem == null || subSystem.ParticleCount == 0)
						continue;

					let subConfig = subSystem.Config;
					if (subConfig == null)
						continue;

					// Update uniforms for sub-emitter
					UpdateUniforms(frameIndex, subConfig, nearPlane, farPlane);

					// Switch pipeline if blend mode changed
					if (subConfig.BlendMode != currentBlendMode)
					{
						let pipeline = GetPipelineForBlendMode(subConfig.BlendMode, useNoDepthPipelines);
						if (pipeline != currentPipeline)
						{
							renderPass.SetPipeline(pipeline);
							currentPipeline = pipeline;
							currentBlendMode = subConfig.BlendMode;
							mLastPipelineSwitchCount++;
						}
					}

					// Sub-emitters use the same bind group as parent (soft particles or not)
					bool subNeedSoftBindGroup = subConfig.SoftParticles && softParticleBindGroup != null;
					if (subNeedSoftBindGroup != usingSoftBindGroup)
					{
						if (subNeedSoftBindGroup)
							renderPass.SetBindGroup(0, softParticleBindGroup);
						else
							renderPass.SetBindGroup(0, mBindGroups[frameIndex]);
						usingSoftBindGroup = subNeedSoftBindGroup;
					}

					renderPass.SetVertexBuffer(0, subSystem.GetVertexBuffer(frameIndex), 0);
					renderPass.SetIndexBuffer(subSystem.IndexBuffer, .UInt16, 0);
					renderPass.DrawIndexed(6, (uint32)subSystem.ParticleCount, 0, 0, 0);
					mLastDrawCallCount++;
				}
			}
		}
	}

	/// Gets the bind group layout for external use (e.g., creating custom bind groups).
	public IBindGroupLayout BindGroupLayout => mBindGroupLayout;

	/// Returns true if the renderer is fully initialized with pipelines.
	public bool IsInitialized => mInitialized && mAlphaBlendPipeline != null;

	// ==================== Statistics ====================

	/// Number of draw calls issued in the last RenderEmitters call.
	public int32 LastDrawCallCount => mLastDrawCallCount;

	/// Number of pipeline switches in the last RenderEmitters call.
	/// Lower is better - sorting by blend mode helps minimize this.
	public int32 LastPipelineSwitchCount => mLastPipelineSwitchCount;
}
