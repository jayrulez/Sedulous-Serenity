namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Mathematics;

/// Configuration for the scene renderer.
struct SceneRendererConfig
{
	public Color ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f);
	public bool EnableDepthPrePass = true;
	public bool EnableSkybox = false;
	public TextureFormat ColorFormat = .BGRA8Unorm;
	public TextureFormat DepthFormat = .Depth24PlusStencil8;
	public uint32 Width = 1280;
	public uint32 Height = 720;
}

/// High-level scene renderer that orchestrates render passes via RenderGraph.
/// Manages camera, lights, and drawable objects.
class SceneRenderer
{
	private IDevice mDevice;
	private RenderGraph mRenderGraph;
	private ShaderLibrary mShaderLibrary;
	private PipelineCache mPipelineCache;
	private UniformBufferAllocator mUniformAllocator;
	private BindGroupCache mBindGroupCache;

	private SceneRendererConfig mConfig;
	private int32 mCurrentFrame = 0;

	// Depth buffer (owned)
	private ITexture mDepthTexture;
	private ITextureView mDepthTextureView;

	// Camera state
	private Matrix mViewMatrix = .Identity;
	private Matrix mProjectionMatrix = .Identity;
	private Matrix mViewProjectionMatrix = .Identity;
	private Vector3 mCameraPosition = .Zero;

	// Draw lists for this frame
	private List<DrawCommand> mOpaqueCommands = new .() ~ delete _;
	private List<DrawCommand> mTransparentCommands = new .() ~ delete _;

	/// Creates a scene renderer.
	public this(IDevice device, ShaderLibrary shaderLibrary)
	{
		mDevice = device;
		mShaderLibrary = shaderLibrary;
		mRenderGraph = new RenderGraph(device);
		mPipelineCache = new PipelineCache(device, shaderLibrary);
		mUniformAllocator = new UniformBufferAllocator(device);
		mBindGroupCache = new BindGroupCache(device);
	}

	public ~this()
	{
		Cleanup();
		delete mBindGroupCache;
		delete mUniformAllocator;
		delete mPipelineCache;
		delete mRenderGraph;
	}

	/// Initializes the scene renderer with the given configuration.
	public Result<void> Initialize(SceneRendererConfig config)
	{
		mConfig = config;

		// Create depth buffer
		if (CreateDepthBuffer() case .Err)
			return .Err;

		return .Ok;
	}

	/// Resizes the renderer (call when window resizes).
	public void Resize(uint32 width, uint32 height)
	{
		if (width == 0 || height == 0)
			return;

		mConfig.Width = width;
		mConfig.Height = height;

		// Recreate depth buffer
		CleanupDepthBuffer();
		CreateDepthBuffer();
	}

	/// Sets the camera matrices for this frame.
	public void SetCamera(Matrix view, Matrix projection, Vector3 position)
	{
		mViewMatrix = view;
		mProjectionMatrix = projection;
		mViewProjectionMatrix = view * projection;
		mCameraPosition = position;
	}

	/// Submits a draw command for this frame.
	public void Submit(DrawCommand command)
	{
		if (command.BlendMode == .Opaque)
			mOpaqueCommands.Add(command);
		else
			mTransparentCommands.Add(command);
	}

	/// Begins a new frame.
	public void BeginFrame(int32 frameIndex, ITextureView swapChainView)
	{
		mCurrentFrame = frameIndex;
		mOpaqueCommands.Clear();
		mTransparentCommands.Clear();

		mRenderGraph.BeginFrame(frameIndex);
		mUniformAllocator.BeginFrame(frameIndex);
		mBindGroupCache.BeginFrame(frameIndex);
	}

	/// Renders the frame.
	public Result<void> Render(ITextureView swapChainView)
	{
		// Sort transparent commands back-to-front
		SortTransparentCommands();

		// Build render passes
		BuildRenderPasses(swapChainView);

		// Compile and execute
		if (mRenderGraph.Compile() case .Err)
			return .Err;

		let encoder = mDevice.CreateCommandEncoder();
		if (mRenderGraph.Execute(encoder) case .Err)
		{
			delete encoder;
			return .Err;
		}

		let commandBuffer = encoder.Finish();
		mDevice.Queue.Submit(commandBuffer);
		delete commandBuffer;
		delete encoder;

		return .Ok;
	}

	/// Ends the frame.
	public void EndFrame()
	{
		mRenderGraph.EndFrame();
	}

	/// Cleans up all resources.
	public void Cleanup()
	{
		CleanupDepthBuffer();
		mRenderGraph.Flush();
		mPipelineCache.Clear();
	}

	private Result<void> CreateDepthBuffer()
	{
		TextureDescriptor desc = .()
		{
			Width = mConfig.Width,
			Height = mConfig.Height,
			Format = mConfig.DepthFormat,
			Usage = .DepthStencil,
			Dimension = .Texture2D,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1
		};

		if (mDevice.CreateTexture(&desc) case .Ok(let texture))
		{
			mDepthTexture = texture;
			if (mDevice.CreateTextureView(texture, null) case .Ok(let view))
			{
				mDepthTextureView = view;
				return .Ok;
			}
		}

		return .Err;
	}

	private void CleanupDepthBuffer()
	{
		if (mDepthTextureView != null)
		{
			delete mDepthTextureView;
			mDepthTextureView = null;
		}
		if (mDepthTexture != null)
		{
			delete mDepthTexture;
			mDepthTexture = null;
		}
	}

	private void SortTransparentCommands()
	{
		// Sort by distance from camera (back to front)
		mTransparentCommands.Sort(scope (a, b) =>
		{
			let distA = Vector3.DistanceSquared(a.WorldPosition, mCameraPosition);
			let distB = Vector3.DistanceSquared(b.WorldPosition, mCameraPosition);
			return distB.CompareTo(distA);  // Back to front
		});
	}

	private void BuildRenderPasses(ITextureView swapChainView)
	{
		// Import swap chain texture
		let colorHandle = mRenderGraph.ImportTexture("SwapChain", null, swapChainView);

		// Import depth buffer
		let depthHandle = mRenderGraph.ImportTexture("Depth", mDepthTexture, mDepthTextureView);

		// Upload camera data
		CameraData cameraData = .()
		{
			View = mViewMatrix,
			Projection = mProjectionMatrix,
			ViewProjection = mViewProjectionMatrix,
			Position = mCameraPosition
		};

		// Add depth pre-pass (if enabled and we have opaque commands)
		if (mConfig.EnableDepthPrePass && mOpaqueCommands.Count > 0)
		{
			let depthPrePass = new DepthPrePass();
			depthPrePass.SetDepthTarget(depthHandle);
			depthPrePass.SetCameraData(cameraData);
			depthPrePass.SetDrawCommands(Span<DrawCommand>(mOpaqueCommands.Ptr, mOpaqueCommands.Count));
			depthPrePass.SetViewport(mConfig.Width, mConfig.Height);
			mRenderGraph.AddPass(depthPrePass);
		}

		// Add opaque pass
		if (mOpaqueCommands.Count > 0)
		{
			let opaquePass = new OpaquePass();
			opaquePass.SetRenderTargets(colorHandle, depthHandle);
			opaquePass.SetClearColor(mConfig.ClearColor);
			opaquePass.SetCameraData(cameraData);
			opaquePass.SetDrawCommands(Span<DrawCommand>(mOpaqueCommands.Ptr, mOpaqueCommands.Count));
			opaquePass.SetViewport(mConfig.Width, mConfig.Height);
			opaquePass.SetPipelineCache(mPipelineCache);
			mRenderGraph.AddPass(opaquePass);
		}
		else
		{
			// Clear pass if no opaque geometry
			let clearPass = new ClearPass();
			clearPass.SetRenderTarget(colorHandle, depthHandle);
			clearPass.SetClearColor(mConfig.ClearColor);
			clearPass.SetViewport(mConfig.Width, mConfig.Height);
			mRenderGraph.AddPass(clearPass);
		}

		// Add skybox pass (if enabled)
		if (mConfig.EnableSkybox)
		{
			let skyboxPass = new SkyboxPass();
			skyboxPass.SetRenderTargets(colorHandle, depthHandle);
			skyboxPass.SetCameraData(cameraData);
			skyboxPass.SetViewport(mConfig.Width, mConfig.Height);
			mRenderGraph.AddPass(skyboxPass);
		}

		// Add transparent pass (if we have transparent commands)
		if (mTransparentCommands.Count > 0)
		{
			let transparentPass = new TransparentPass();
			transparentPass.SetRenderTargets(colorHandle, depthHandle);
			transparentPass.SetCameraData(cameraData);
			transparentPass.SetDrawCommands(Span<DrawCommand>(mTransparentCommands.Ptr, mTransparentCommands.Count));
			transparentPass.SetViewport(mConfig.Width, mConfig.Height);
			transparentPass.SetPipelineCache(mPipelineCache);
			mRenderGraph.AddPass(transparentPass);
		}
	}

	// Public accessors
	public IDevice Device => mDevice;
	public RenderGraph RenderGraph => mRenderGraph;
	public ShaderLibrary ShaderLibrary => mShaderLibrary;
	public PipelineCache PipelineCache => mPipelineCache;
	public UniformBufferAllocator UniformAllocator => mUniformAllocator;
	public BindGroupCache BindGroupCache => mBindGroupCache;
	public int32 OpaqueCommandCount => (int32)mOpaqueCommands.Count;
	public int32 TransparentCommandCount => (int32)mTransparentCommands.Count;
	public uint32 Width => mConfig.Width;
	public uint32 Height => mConfig.Height;
}
