using System;
using System.Diagnostics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Mathematics;

namespace Sedulous.Engine.Runtime;

/// Abstract base class for Sedulous applications.
/// Provides lifecycle methods, window management, and rendering loop.
abstract class Application
{
	private const int MAX_FRAMES_IN_FLIGHT = 2;

	// Injected dependencies (owned by caller)
	protected IShell mShell;
	protected IDevice mDevice;
	protected IBackend mBackend;

	// Created by Application (owned by Application)
	protected IWindow mWindow;
	protected ISurface mSurface;
	protected ISwapChain mSwapChain;
	protected ICommandBuffer[MAX_FRAMES_IN_FLIGHT] mCommandBuffers;
	protected ITexture mDepthTexture;
	protected ITextureView mDepthTextureView;

	// Settings and state
	protected ApplicationSettings mSettings;
	protected bool mIsRunning;

	// Timing
	private Stopwatch mStopwatch = new .() ~ delete _;
	private float mLastFrameTime;

	/// Creates an application with the provided dependencies.
	/// @param shell The shell for windowing and input (must be initialized).
	/// @param device The RHI device for GPU operations.
	/// @param backend The RHI backend (for surface creation).
	public this(IShell shell, IDevice device, IBackend backend)
	{
		mShell = shell;
		mDevice = device;
		mBackend = backend;
	}

	/// The RHI device for GPU operations.
	public IDevice Device => mDevice;

	/// The swap chain for presentation.
	public ISwapChain SwapChain => mSwapChain;

	/// The main application window.
	public IWindow Window => mWindow;

	/// The shell providing platform services.
	public IShell Shell => mShell;

	/// Whether the application is currently running.
	public bool IsRunning => mIsRunning;

	/// Application settings.
	public ApplicationSettings Settings => mSettings;

	/// Runs the application with the given settings.
	/// @param settings Application configuration.
	/// @returns Exit code (0 for success).
	public int Run(ApplicationSettings settings)
	{
		mSettings = settings;

		if (!Initialize())
			return -1;

		OnInitialize();

		mStopwatch.Start();
		mIsRunning = true;

		while (mIsRunning && mShell.IsRunning)
		{
			mShell.ProcessEvents();

			float currentTime = (float)mStopwatch.Elapsed.TotalSeconds;
			float deltaTime = currentTime - mLastFrameTime;
			mLastFrameTime = currentTime;

			OnInput();

			let frameContext = FrameContext()
			{
				DeltaTime = deltaTime,
				TotalTime = currentTime,
				FrameIndex = (int32)mSwapChain.CurrentFrameIndex,
				FrameCount = (int32)mSwapChain.FrameCount
			};

			OnUpdate(frameContext);
			Frame(frameContext);
		}

		mDevice.WaitIdle();
		OnShutdown();
		Cleanup();

		return 0;
	}

	/// Request the application to exit.
	public void Exit()
	{
		mIsRunning = false;
	}

	// Lifecycle methods - override in user application

	/// Called once at startup after device and swap chain are ready.
	protected virtual void OnInitialize() { }

	/// Called once at shutdown before cleanup.
	protected virtual void OnShutdown() { }

	/// Called when the window is resized.
	protected virtual void OnResize(int32 width, int32 height) { }

	/// Called each frame for input handling (before Update).
	protected virtual void OnInput() { }

	/// Called each frame for game/application logic.
	protected virtual void OnUpdate(FrameContext frame) { }

	/// Called after AcquireNextImage - safe to write per-frame GPU buffers.
	protected virtual void OnPrepareFrame(FrameContext frame) { }

	/// Called for rendering with full control over the command encoder.
	/// @returns true if rendering was handled, false to use default render pass.
	protected virtual bool OnRenderFrame(RenderContext render) { return false; }

	/// Called for rendering in the default render pass (if OnRenderFrame returns false).
	protected virtual void OnRender(IRenderPassEncoder renderPass, FrameContext frame) { }

	/// Called after the frame has been submitted and presented.
	protected virtual void OnFrameEnd() { }

	// Internal implementation

	private bool Initialize()
	{
		// Create window
		String title = scope .(mSettings.Title);
		let windowSettings = WindowSettings()
		{
			Title = title,
			Width = mSettings.Width,
			Height = mSettings.Height,
			Resizable = mSettings.Resizable
		};

		if (mShell.WindowManager.CreateWindow(windowSettings) not case .Ok(let window))
			return false;
		mWindow = window;

		// Subscribe to window events
		mShell.WindowManager.OnWindowEvent.Subscribe(new => HandleWindowEvent);

		// Create surface from window
		if (mBackend.CreateSurface(mWindow.NativeHandle) not case .Ok(let surface))
			return false;
		mSurface = surface;

		// Create swap chain
		if (!CreateSwapChain())
			return false;

		// Create depth buffer if enabled
		if (mSettings.EnableDepth)
			CreateDepthBuffer();

		return true;
	}

	private bool CreateSwapChain()
	{
		SwapChainDescriptor desc = .()
		{
			Width = (uint32)mWindow.Width,
			Height = (uint32)mWindow.Height,
			Format = mSettings.SwapChainFormat,
			Usage = .RenderTarget,
			PresentMode = mSettings.PresentMode
		};

		if (mDevice.CreateSwapChain(mSurface, &desc) not case .Ok(let swapChain))
			return false;

		mSwapChain = swapChain;
		return true;
	}

	private void CreateDepthBuffer()
	{
		TextureDescriptor desc = .()
		{
			Width = (uint32)mWindow.Width,
			Height = (uint32)mWindow.Height,
			Format = mSettings.DepthFormat,
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
				mDepthTextureView = view;
		}
	}

	private void Frame(FrameContext frameContext)
	{
		// Acquire next image (sync point - waits for fence)
		if (mSwapChain.AcquireNextImage() case .Err)
		{
			HandleResize();
			return;
		}

		// Safe to write per-frame buffers now
		OnPrepareFrame(frameContext);

		// Clean up old command buffer
		let frameIndex = frameContext.FrameIndex;
		if (mCommandBuffers[frameIndex] != null)
		{
			delete mCommandBuffers[frameIndex];
			mCommandBuffers[frameIndex] = null;
		}

		// Create encoder
		let encoder = mDevice.CreateCommandEncoder();

		let renderContext = RenderContext()
		{
			Encoder = encoder,
			SwapChain = mSwapChain,
			CurrentTextureView = mSwapChain.CurrentTextureView,
			DepthTextureView = mDepthTextureView,
			Frame = frameContext,
			ClearColor = mSettings.ClearColor
		};

		// Let app render
		if (!OnRenderFrame(renderContext))
		{
			RenderDefaultPass(encoder, renderContext);
		}

		let commandBuffer = encoder.Finish();
		mCommandBuffers[frameIndex] = commandBuffer;

		mDevice.Queue.Submit(commandBuffer, mSwapChain);

		if (mSwapChain.Present() case .Err)
			HandleResize();

		delete encoder;
		OnFrameEnd();
	}

	private void RenderDefaultPass(ICommandEncoder encoder, RenderContext ctx)
	{
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = ctx.CurrentTextureView,
			ResolveTarget = null,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = ctx.ClearColor
		});

		RenderPassDescriptor desc = .(colorAttachments);

		if (mDepthTextureView != null)
		{
			desc.DepthStencilAttachment = .()
			{
				View = mDepthTextureView,
				DepthLoadOp = .Clear,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f,
				StencilLoadOp = .Clear,
				StencilStoreOp = .Store, // different from SF
				StencilClearValue = 0
			};
		}

		let renderPass = encoder.BeginRenderPass(&desc);
		renderPass.SetViewport(0, 0, mSwapChain.Width, mSwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, mSwapChain.Width, mSwapChain.Height);

		OnRender(renderPass, ctx.Frame);

		renderPass.End();

		delete renderPass;
	}

	private void HandleWindowEvent(IWindow window, WindowEvent evt)
	{
		if (window != mWindow)
			return;

		switch (evt.Type)
		{
		case .Resized:
			HandleResize();
		case .CloseRequested:
			Exit();
		default:
		}
	}

	private void HandleResize()
	{
		if (mWindow.Width == 0 || mWindow.Height == 0)
			return;

		mDevice.WaitIdle();

		// Cleanup depth buffer
		if (mDepthTextureView != null) { delete mDepthTextureView; mDepthTextureView = null; }
		if (mDepthTexture != null) { delete mDepthTexture; mDepthTexture = null; }

		// Resize swap chain
		mSwapChain.Resize((uint32)mWindow.Width, (uint32)mWindow.Height);

		// Recreate depth buffer
		if (mSettings.EnableDepth)
			CreateDepthBuffer();

		OnResize(mWindow.Width, mWindow.Height);
	}

	private void Cleanup()
	{
		// Clean up command buffers
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (mCommandBuffers[i] != null)
			{
				delete mCommandBuffers[i];
				mCommandBuffers[i] = null;
			}
		}

		// Clean up depth buffer
		if (mDepthTextureView != null) delete mDepthTextureView;
		if (mDepthTexture != null) delete mDepthTexture;

		// Clean up swap chain and surface (owned by Application)
		if (mSwapChain != null) delete mSwapChain;
		if (mSurface != null) delete mSurface;

		// Note: shell, device, backend are NOT deleted - they're owned by caller
	}
}
