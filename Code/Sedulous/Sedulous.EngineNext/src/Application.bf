namespace Sedulous.EngineNext;

using System;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Shaders;
using Sedulous.RendererNext;

/// Base application class for EngineNext applications.
/// Manages window, device, and main loop.
abstract class Application
{
	protected IShell mShell;
	protected IWindow mWindow;
	protected IDevice mDevice;
	protected ISwapChain mSwapChain;
	protected ShaderLibrary mShaderLibrary;
	protected RenderGraph mRenderGraph;
	protected PipelineCache mPipelineCache;
	protected MaterialSystem mMaterialSystem;
	protected GPUResourceManager mResourceManager;

	// Per-frame command buffers (kept alive until fence signals)
	protected ICommandBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mCommandBuffers;
	protected ICommandEncoder[FrameConfig.MAX_FRAMES_IN_FLIGHT] mCommandEncoders;

	protected int32 mWidth = 1280;
	protected int32 mHeight = 720;
	protected String mTitle = new .("EngineNext Application") ~ delete _;
	protected bool mRunning = false;
	protected int32 mFrameIndex = 0;
	protected float mTime = 0;
	protected float mDeltaTime = 0;

	public this()
	{
	}

	public ~this()
	{
		Shutdown();
	}

	/// Runs the application.
	public void Run()
	{
		if (Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize application");
			return;
		}

		mRunning = true;
		var lastTime = DateTime.Now;

		while (mRunning && mShell.IsRunning)
		{
			// Calculate delta time
			let currentTime = DateTime.Now;
			mDeltaTime = (float)(currentTime - lastTime).TotalSeconds;
			lastTime = currentTime;
			mTime += mDeltaTime;

			// Process events
			mShell.ProcessEvents();

			// Update
			OnUpdate(mDeltaTime);

			// Render frame
			RenderFrame();
		}

		// Wait for GPU to finish before cleanup
		mDevice.WaitIdle();
	}

	/// Renders one frame.
	protected virtual void RenderFrame()
	{
		// Acquire next swap chain image - this waits for the in-flight fence
		if (mSwapChain.AcquireNextImage() case .Err)
			return;

		let frameIndex = (int32)mSwapChain.CurrentFrameIndex;

		// Clean up previous command buffer for this frame slot
		// (safe now because fence has signaled)
		if (mCommandBuffers[frameIndex] != null)
		{
			delete mCommandBuffers[frameIndex];
			mCommandBuffers[frameIndex] = null;
		}
		if (mCommandEncoders[frameIndex] != null)
		{
			delete mCommandEncoders[frameIndex];
			mCommandEncoders[frameIndex] = null;
		}

		// Begin render graph frame
		mRenderGraph.BeginFrame(frameIndex);

		// Let derived class add passes
		OnRender();

		// Create command encoder and execute render graph
		let encoder = mDevice.CreateCommandEncoder();
		mRenderGraph.Execute(encoder);
		let commandBuffer = encoder.Finish();

		// Store for later deletion (after fence signals)
		mCommandBuffers[frameIndex] = commandBuffer;
		mCommandEncoders[frameIndex] = encoder;

		// Submit and present
		mDevice.Queue.Submit(commandBuffer, mSwapChain);
		mSwapChain.Present();

		mRenderGraph.EndFrame();
		mFrameIndex = (mFrameIndex + 1) % FrameConfig.MAX_FRAMES_IN_FLIGHT;
	}

	/// Stops the application.
	public void Stop()
	{
		mRunning = false;
	}

	/// Initializes the application.
	protected virtual Result<void> Initialize()
	{
		// Create shell and window
		if (CreateShell() case .Err)
			return .Err;

		// Create device and swap chain
		if (CreateDevice() case .Err)
			return .Err;

		// Create renderer systems
		if (CreateRenderer() case .Err)
			return .Err;

		// User initialization
		if (OnInitialize() case .Err)
			return .Err;

		return .Ok;
	}

	/// Creates the shell and window.
	protected virtual Result<void> CreateShell()
	{
		// This should be overridden to use SDL3 or other shell implementation
		return .Err;
	}

	/// Creates the device and swap chain.
	protected virtual Result<void> CreateDevice()
	{
		// This should be overridden to use Vulkan or D3D12
		return .Err;
	}

	/// Creates renderer systems.
	protected virtual Result<void> CreateRenderer()
	{
		if (mDevice == null)
			return .Err;

		mShaderLibrary = new ShaderLibrary(mDevice);
		mRenderGraph = new RenderGraph(mDevice);
		mPipelineCache = new PipelineCache(mDevice, mShaderLibrary);
		mMaterialSystem = new MaterialSystem(mDevice, mShaderLibrary);
		mResourceManager = new GPUResourceManager(mDevice);

		return .Ok;
	}

	/// Shuts down the application.
	protected virtual void Shutdown()
	{
		OnShutdown();

		// Clean up command buffers
		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (mCommandBuffers[i] != null)
			{
				delete mCommandBuffers[i];
				mCommandBuffers[i] = null;
			}
			if (mCommandEncoders[i] != null)
			{
				delete mCommandEncoders[i];
				mCommandEncoders[i] = null;
			}
		}

		if (mResourceManager != null)
		{
			delete mResourceManager;
			mResourceManager = null;
		}

		if (mMaterialSystem != null)
		{
			delete mMaterialSystem;
			mMaterialSystem = null;
		}

		if (mPipelineCache != null)
		{
			delete mPipelineCache;
			mPipelineCache = null;
		}

		if (mRenderGraph != null)
		{
			mRenderGraph.Flush();
			delete mRenderGraph;
			mRenderGraph = null;
		}

		if (mShaderLibrary != null)
		{
			delete mShaderLibrary;
			mShaderLibrary = null;
		}

		if (mSwapChain != null)
		{
			delete mSwapChain;
			mSwapChain = null;
		}

		if (mDevice != null)
		{
			delete mDevice;
			mDevice = null;
		}

		if (mWindow != null)
		{
			delete mWindow;
			mWindow = null;
		}

		if (mShell != null)
		{
			delete mShell;
			mShell = null;
		}
	}

	/// Called when the application initializes. Override to set up game state.
	protected virtual Result<void> OnInitialize() => .Ok;

	/// Called when the application shuts down. Override to clean up game state.
	protected virtual void OnShutdown() { }

	/// Called each frame to update game logic.
	protected virtual void OnUpdate(float deltaTime) { }

	/// Called each frame to render. Add passes to mRenderGraph here.
	protected virtual void OnRender() { }

	// Properties
	public IDevice Device => mDevice;
	public ISwapChain SwapChain => mSwapChain;
	public ShaderLibrary ShaderLibrary => mShaderLibrary;
	public RenderGraph RenderGraph => mRenderGraph;
	public PipelineCache PipelineCache => mPipelineCache;
	public MaterialSystem MaterialSystem => mMaterialSystem;
	public GPUResourceManager ResourceManager => mResourceManager;
	public int32 Width => mWidth;
	public int32 Height => mHeight;
	public float Time => mTime;
	public float DeltaTime => mDeltaTime;
	public int32 FrameIndex => mFrameIndex;
}
