namespace RHI.SampleFramework;

using System;
using System.Collections;
using System.Diagnostics;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;
using Sedulous.Shell.Input;

/// Configuration for an RHI sample application.
struct SampleConfig
{
	public StringView Title = "RHI Sample";
	public int32 Width = 800;
	public int32 Height = 600;
	public bool Resizable = true;
	public bool EnableValidation = true;
	public TextureFormat SwapChainFormat = .BGRA8UnormSrgb;
	public PresentMode PresentMode = .Fifo;
	public Color ClearColor = .(0.1f, 0.1f, 0.1f, 1.0f);
	public bool EnableDepth = false;
	public TextureFormat DepthFormat = .Depth24PlusStencil8;
}

/// Base class for RHI sample applications.
/// Handles common setup, main loop, and cleanup.
abstract class RHISampleApp
{
	// Core objects
	protected SDL3Shell mShell;
	protected IWindow mWindow;
	protected IBackend mBackend;
	protected IDevice mDevice;
	protected ISurface mSurface;
	protected ISwapChain mSwapChain;

	// Depth buffer (optional)
	protected ITexture mDepthTexture;
	protected ITextureView mDepthTextureView;

	// Per-frame command buffers
	protected const int MAX_FRAMES_IN_FLIGHT = 2;
	protected ICommandBuffer[MAX_FRAMES_IN_FLIGHT] mCommandBuffers;

	// Timing
	protected Stopwatch mStopwatch = new .() ~ delete _;
	protected float mDeltaTime;
	protected float mTotalTime;
	private float mLastFrameTime;

	// Error tracking
	private int mConsecutiveErrors = 0;
	private const int MAX_CONSECUTIVE_ERRORS = 10;

	// Configuration
	protected SampleConfig mConfig;

	/// Creates a new sample application with the given configuration.
	public this(SampleConfig config)
	{
		mConfig = config;
	}

	public ~this()
	{
		Cleanup();
	}

	/// Runs the sample application.
	public int Run()
	{
		if (!Initialize())
			return 1;

		mStopwatch.Start();

		// Main loop
		while (mShell.IsRunning)
		{
			mShell.ProcessEvents();

			// Update timing
			float currentTime = (float)mStopwatch.Elapsed.TotalSeconds;
			mDeltaTime = currentTime - mLastFrameTime;
			mLastFrameTime = currentTime;
			mTotalTime = currentTime;

			// Handle escape key
			if (mShell.InputManager.Keyboard.IsKeyPressed(.Escape))
			{
				mShell.RequestExit();
				continue;
			}

			// Check for key presses and call OnKeyDown
			for (int key = 0; key < (int)KeyCode.Count; key++)
			{
				let keyCode = (KeyCode)key;
				if (mShell.InputManager.Keyboard.IsKeyPressed(keyCode))
					OnKeyDown(keyCode);
			}

			// Let sample handle input
			OnInput();

			// Update
			OnUpdate(mDeltaTime, mTotalTime);

			// Render
			if (RenderFrame())
			{
				mConsecutiveErrors = 0;
			}
			else
			{
				mConsecutiveErrors++;
				if (mConsecutiveErrors >= MAX_CONSECUTIVE_ERRORS)
				{
					Console.WriteLine(scope $"Too many consecutive render errors ({MAX_CONSECUTIVE_ERRORS}), exiting.");
					mShell.RequestExit();
				}
			}
		}

		mDevice.WaitIdle();
		return 0;
	}

	/// Initializes the sample. Called after RHI setup completes.
	/// Override to create resources.
	protected virtual bool OnInitialize() => true;

	/// Called each frame for input handling.
	protected virtual void OnInput() { }

	/// Called each frame for updates.
	protected virtual void OnUpdate(float deltaTime, float totalTime) { }

	/// Called to record render commands.
	protected abstract void OnRender(IRenderPassEncoder renderPass);

	/// Called for custom rendering when you need full control over the command encoder.
	/// If this returns true, the default render pass is skipped.
	/// Use this for advanced scenarios like queries that need to wrap render passes.
	protected virtual bool OnRenderCustom(ICommandEncoder encoder) => false;

	/// Called at the end of each frame after present.
	protected virtual void OnFrameEnd() { }

	/// Called when a key is pressed.
	protected virtual void OnKeyDown(KeyCode key) { }

	/// Called when the window is resized.
	protected virtual void OnResize(uint32 width, uint32 height) { }

	/// Called during cleanup. Override to destroy sample resources.
	protected virtual void OnCleanup() { }

	// Accessors for derived classes
	public IDevice Device => mDevice;
	public ISwapChain SwapChain => mSwapChain;
	public IWindow Window => mWindow;
	public IShell Shell => mShell;
	public float DeltaTime => mDeltaTime;
	public float TotalTime => mTotalTime;

	/// Returns the current depth texture view, or null if depth is disabled.
	public ITextureView DepthTextureView => mDepthTextureView;

	private bool Initialize()
	{
		// Initialize shell
		mShell = new SDL3Shell();
		if (mShell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return false;
		}

		// Create window
		String title = scope .(mConfig.Title);
		let windowSettings = WindowSettings()
		{
			Title = title,
			Width = mConfig.Width,
			Height = mConfig.Height,
			Resizable = mConfig.Resizable,
			Bordered = true
		};

		if (mShell.WindowManager.CreateWindow(windowSettings) not case .Ok(let window))
		{
			Console.WriteLine("Failed to create window");
			return false;
		}
		mWindow = window;

		// Create backend
		mBackend = new VulkanBackend(mConfig.EnableValidation);
		if (!mBackend.IsInitialized)
		{
			Console.WriteLine("Failed to initialize Vulkan backend");
			return false;
		}

		// Create surface
		if (mBackend.CreateSurface(mWindow.NativeHandle) not case .Ok(let surface))
		{
			Console.WriteLine("Failed to create surface");
			return false;
		}
		mSurface = surface;

		// Get adapter
		List<IAdapter> adapters = scope .();
		mBackend.EnumerateAdapters(adapters);
		if (adapters.Count == 0)
		{
			Console.WriteLine("No GPU adapters found");
			return false;
		}
		Console.WriteLine(scope $"Using adapter: {adapters[0].Info.Name}");

		// Create device
		if (adapters[0].CreateDevice() not case .Ok(let device))
		{
			Console.WriteLine("Failed to create device");
			return false;
		}
		mDevice = device;

		// Create swap chain
		SwapChainDescriptor swapChainDesc = .()
		{
			Width = (uint32)mWindow.Width,
			Height = (uint32)mWindow.Height,
			Format = mConfig.SwapChainFormat,
			Usage = .RenderTarget,
			PresentMode = mConfig.PresentMode
		};

		if (mDevice.CreateSwapChain(mSurface, &swapChainDesc) not case .Ok(let swapChain))
		{
			Console.WriteLine("Failed to create swap chain");
			return false;
		}
		mSwapChain = swapChain;
		Console.WriteLine(scope $"Swap chain created: {mSwapChain.Width}x{mSwapChain.Height}");

		// Create depth buffer if enabled
		if (mConfig.EnableDepth)
		{
			if (!CreateDepthBuffer())
			{
				Console.WriteLine("Failed to create depth buffer");
				return false;
			}
		}

		// Let derived class initialize
		if (!OnInitialize())
		{
			Console.WriteLine("Sample initialization failed");
			return false;
		}

		Console.WriteLine(scope $"{mConfig.Title} running. Press Escape to exit.");
		return true;
	}

	private bool CreateDepthBuffer()
	{
		TextureDescriptor depthDesc = TextureDescriptor.Texture2D(
			mSwapChain.Width,
			mSwapChain.Height,
			mConfig.DepthFormat,
			.DepthStencil
		);

		if (mDevice.CreateTexture(&depthDesc) not case .Ok(let texture))
			return false;

		mDepthTexture = texture;

		TextureViewDescriptor viewDesc = .()
		{
			Format = mConfig.DepthFormat,
			Dimension = .Texture2D,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1
		};
		if (mDevice.CreateTextureView(mDepthTexture, &viewDesc) not case .Ok(let view))
			return false;

		mDepthTextureView = view;
		Console.WriteLine("Depth buffer created");
		return true;
	}

	private void DestroyDepthBuffer()
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

	private bool RenderFrame()
	{
		// Acquire next swap chain image
		if (mSwapChain.AcquireNextImage() case .Err)
		{
			HandleResize();
			return true; // Resize is not an error
		}

		// Clean up previous command buffer for this frame slot
		let frameIndex = mSwapChain.CurrentFrameIndex;
		if (mCommandBuffers[frameIndex] != null)
		{
			delete mCommandBuffers[frameIndex];
			mCommandBuffers[frameIndex] = null;
		}

		// Get current texture view
		let textureView = mSwapChain.CurrentTextureView;
		if (textureView == null)
		{
			// Failed after acquire - error counter will handle recovery
			return false;
		}

		// Create command encoder
		let encoder = mDevice.CreateCommandEncoder();
		if (encoder == null)
		{
			return false;
		}
		defer delete encoder;

		// Check if sample wants custom rendering control
		bool customRendering = OnRenderCustom(encoder);

		if (!customRendering)
		{
			// Begin render pass
			RenderPassColorAttachment[1] colorAttachments = .(.()
			{
				View = textureView,
				ResolveTarget = null,
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = mConfig.ClearColor
			});

			RenderPassDescriptor renderPassDesc = .(colorAttachments);
			RenderPassDepthStencilAttachment depthAttachment = default;
			if (mConfig.EnableDepth && mDepthTextureView != null)
			{
				depthAttachment = .()
				{
					View = mDepthTextureView,
					DepthLoadOp = .Clear,
					DepthStoreOp = .Store,
					DepthClearValue = 1.0f,
					StencilLoadOp = .Clear,
					StencilStoreOp = .Discard,
					StencilClearValue = 0
				};
				renderPassDesc.DepthStencilAttachment = depthAttachment;
			}

			let renderPass = encoder.BeginRenderPass(&renderPassDesc);
			if (renderPass == null)
			{
				return false;
			}
			defer delete renderPass;

			// Set viewport and scissor to full screen
			renderPass.SetViewport(0, 0, mSwapChain.Width, mSwapChain.Height, 0, 1);
			renderPass.SetScissorRect(0, 0, mSwapChain.Width, mSwapChain.Height);

			// Let derived class record commands
			OnRender(renderPass);

			renderPass.End();
		}

		// Finish recording
		let commandBuffer = encoder.Finish();
		if (commandBuffer == null)
		{
			return false;
		}

		// Store command buffer for later deletion
		mCommandBuffers[frameIndex] = commandBuffer;

		// Submit with swap chain synchronization
		mDevice.Queue.Submit(commandBuffer, mSwapChain);

		// Present
		if (mSwapChain.Present() case .Err)
		{
			HandleResize();
		}

		// Notify sample that frame is complete
		OnFrameEnd();

		return true;
	}

	private void HandleResize()
	{
		mDevice.WaitIdle();

		// Clean up command buffers
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (mCommandBuffers[i] != null)
			{
				delete mCommandBuffers[i];
				mCommandBuffers[i] = null;
			}
		}

		// Recreate depth buffer if enabled
		if (mConfig.EnableDepth)
		{
			DestroyDepthBuffer();
		}

		// Resize swap chain
		if (mSwapChain.Resize((uint32)mWindow.Width, (uint32)mWindow.Height) case .Err)
		{
			Console.WriteLine("Failed to resize swap chain");
			return;
		}

		// Recreate depth buffer
		if (mConfig.EnableDepth)
		{
			if (!CreateDepthBuffer())
			{
				Console.WriteLine("Failed to recreate depth buffer");
			}
		}

		// Notify derived class
		OnResize(mSwapChain.Width, mSwapChain.Height);
	}

	private void Cleanup()
	{
		if (mDevice != null)
			mDevice.WaitIdle();

		// Let derived class cleanup first
		OnCleanup();

		// Clean up command buffers
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (mCommandBuffers[i] != null)
			{
				delete mCommandBuffers[i];
				mCommandBuffers[i] = null;
			}
		}

		DestroyDepthBuffer();

		if (mSwapChain != null) { delete mSwapChain; mSwapChain = null; }
		if (mDevice != null) { delete mDevice; mDevice = null; }
		if (mSurface != null) { delete mSurface; mSurface = null; }
		if (mBackend != null) { delete mBackend; mBackend = null; }

		if (mShell != null)
		{
			mShell.Shutdown();
			delete mShell;
			mShell = null;
		}

		Console.WriteLine("Sample finished.");
	}
}
