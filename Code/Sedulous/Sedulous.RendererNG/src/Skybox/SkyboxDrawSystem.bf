namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Skybox uniform data for shaders.
[CRepr]
struct SkyboxUniforms
{
	public Matrix InverseViewProjection;
	public float Exposure;
	public float Rotation;
	public float _Padding0;
	public float _Padding1;

	public const uint32 Size = 80;

	public static Self Default => .()
	{
		InverseViewProjection = .Identity,
		Exposure = 1.0f,
		Rotation = 0.0f
	};
}

/// Manages skybox rendering with cubemap support.
class SkyboxDrawSystem : IDisposable
{
	private IDevice mDevice;
	private Renderer mRenderer;

	// Pipeline
	private IRenderPipeline mPipeline ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;

	// Fullscreen triangle vertex buffer (not needed - use vertex ID)
	private IBuffer mUniformBuffer ~ delete _;

	// Default cubemap (1x1 per face, black)
	private ITexture mDefaultCubemap ~ delete _;
	private ITextureView mDefaultCubemapView ~ delete _;
	private ISampler mCubemapSampler ~ delete _;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mInitialized = false;

	// Current state
	private ITextureView mCurrentCubemap;
	private float mExposure = 1.0f;
	private float mRotation = 0.0f;

	public this(Renderer renderer)
	{
		mRenderer = renderer;
		mDevice = null;
	}

	/// Initializes the skybox draw system.
	public Result<void> Initialize(IDevice device, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		mDevice = device;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		if (CreateDefaultResources() case .Err)
			return .Err;

		if (CreateBindGroupLayout() case .Err)
			return .Err;

		if (CreateUniformBuffer() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	private Result<void> CreateDefaultResources()
	{
		// Create 1x1 black cubemap using the helper
		var texDesc = TextureDescriptor.Cubemap(1, .RGBA8Unorm, .Sampled | .CopyDst);

		switch (mDevice.CreateTexture(&texDesc))
		{
		case .Ok(let tex): mDefaultCubemap = tex;
		case .Err: return .Err;
		}

		// Note: Default cubemap is uninitialized (black) which is fine for a fallback

		var viewDesc = TextureViewDescriptor();
		viewDesc.Dimension = .TextureCube;
		viewDesc.Format = .RGBA8Unorm;
		switch (mDevice.CreateTextureView(mDefaultCubemap, &viewDesc))
		{
		case .Ok(let view): mDefaultCubemapView = view;
		case .Err: return .Err;
		}

		// Create sampler for cubemap
		var samplerDesc = SamplerDescriptor();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		samplerDesc.AddressModeW = .ClampToEdge;
		switch (mDevice.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler): mCubemapSampler = sampler;
		case .Err: return .Err;
		}

		mCurrentCubemap = mDefaultCubemapView;
		return .Ok;
	}

	private Result<void> CreateBindGroupLayout()
	{
		// b0 = scene uniforms, b1 = skybox uniforms
		// t0 = cubemap texture, s0 = sampler
		BindGroupLayoutEntry[4] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .TextureCube),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);

		var layoutDesc = BindGroupLayoutDescriptor(layoutEntries);
		switch (mDevice.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		var pipelineLayoutDesc = PipelineLayoutDescriptor(layouts);
		switch (mDevice.CreatePipelineLayout(&pipelineLayoutDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateUniformBuffer()
	{
		var bufDesc = BufferDescriptor(SkyboxUniforms.Size, .Uniform, .Upload);
		switch (mDevice.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mUniformBuffer = buf;
		case .Err: return .Err;
		}
		return .Ok;
	}

	/// Creates the pipeline (call after shaders are available).
	public Result<void> CreatePipeline(IShaderModule vertShader, IShaderModule fragShader)
	{
		if (mPipeline != null)
		{
			delete mPipeline;
			mPipeline = null;
		}

		// No vertex input - shader generates fullscreen triangle from vertex ID
		VertexBufferLayout[0] vertexBuffers = .();

		// Depth state: test LessEqual, no write (skybox at far plane)
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .LessEqual;
		depthState.Format = mDepthFormat;

		ColorTargetState[1] colorTargets = .(ColorTargetState(mColorFormat, .()));

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

		switch (mDevice.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	/// Sets the cubemap texture for the skybox.
	public void SetCubemap(ITextureView cubemap)
	{
		mCurrentCubemap = (cubemap != null) ? cubemap : mDefaultCubemapView;
	}

	/// Sets the exposure for HDR cubemaps.
	public void SetExposure(float exposure)
	{
		mExposure = exposure;
	}

	/// Sets the rotation of the skybox around the Y axis (radians).
	public void SetRotation(float rotation)
	{
		mRotation = rotation;
	}

	/// Updates uniforms before rendering.
	public void UpdateUniforms(Matrix viewMatrix, Matrix projectionMatrix)
	{
		// Calculate inverse view-projection for ray generation
		Matrix viewNoTranslation = viewMatrix;
		viewNoTranslation.M41 = 0;
		viewNoTranslation.M42 = 0;
		viewNoTranslation.M43 = 0;

		Matrix viewProj = viewNoTranslation * projectionMatrix;
		Matrix invViewProj = Matrix.Invert(viewProj);

		SkyboxUniforms uniforms;
		uniforms.InverseViewProjection = invViewProj;
		uniforms.Exposure = mExposure;
		uniforms.Rotation = mRotation;
		uniforms._Padding0 = 0;
		uniforms._Padding1 = 0;

		Span<uint8> data = .((uint8*)&uniforms, (int)SkyboxUniforms.Size);
		mDevice.Queue.WriteBuffer(mUniformBuffer, 0, data);
	}

	/// Renders the skybox.
	public void Render(IRenderPassEncoder renderPass, IBindGroup bindGroup = null)
	{
		if (!mInitialized || mPipeline == null)
			return;

		renderPass.SetPipeline(mPipeline);

		if (bindGroup != null)
			renderPass.SetBindGroup(0, bindGroup, .());

		// Draw fullscreen triangle (3 vertices, generated in shader)
		renderPass.Draw(3, 1, 0, 0);
	}

	/// Gets the bind group layout for external bind group creation.
	public IBindGroupLayout BindGroupLayout => mBindGroupLayout;

	/// Gets the uniform buffer.
	public IBuffer UniformBuffer => mUniformBuffer;

	/// Gets default cubemap view.
	public ITextureView DefaultCubemapView => mDefaultCubemapView;

	/// Gets cubemap sampler.
	public ISampler CubemapSampler => mCubemapSampler;

	/// Gets current cubemap.
	public ITextureView CurrentCubemap => mCurrentCubemap;

	/// Returns true if initialized.
	public bool IsInitialized => mInitialized;

	/// Returns true if pipeline is ready.
	public bool HasPipeline => mPipeline != null;

	public void Dispose()
	{
		// Resources cleaned up by destructor
	}
}
