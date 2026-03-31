namespace RendererFramework;

using System;
using System.IO;
using Sedulous.RHI;
using Sedulous.RHI.Validation;
using Sedulous.RenderGraph;
using Sedulous.Renderer;
using Sedulous.Shell;
using SDL3;
using System.Collections;

/// Backend graphics API selection.
enum BackendType
{
	Vulkan,
	DX12,
}

/// Base class for renderer samples and test applications.
/// Uses Sedulous.Shell for windowing/input instead of raw SDL.
abstract class Application
{
	protected IShell mShell;
	protected IWindow mWindow;
	protected IBackend mBackend;
	protected IDevice mDevice;
	protected IQueue mGraphicsQueue;
	protected ISurface mSurface;
	protected ISwapChain mSwapChain;
	protected RenderSystem mRenderSystem;
	protected RenderWorld mWorld;
	protected RenderView mView;

	protected uint32 mWidth = 1280;
	protected uint32 mHeight = 720;
	protected bool mMinimized;
	protected float mDeltaTime;
	protected float mTotalTime;

	protected BackendType mBackendType;
	private bool mValidation;

	// Asset directories (discovered at init time)
	private String mAssetDirectory = new .() ~ delete _;
	private String mAssetCacheDirectory = new .() ~ delete _;

	public this(BackendType backendType = .Vulkan, bool validation = true)
	{
		mBackendType = backendType;
		mValidation = validation;
	}

	/// Returns the discovered assets directory path (absolute).
	public StringView AssetDirectory => mAssetDirectory;

	/// Returns the discovered asset cache directory path (absolute).
	public StringView AssetCacheDirectory => mAssetCacheDirectory;

	/// Returns a full path for an asset-relative path.
	public void GetAssetPath(StringView relativePath, String outPath)
	{
		outPath.Clear();
		Path.InternalCombine(outPath, mAssetDirectory, relativePath);
	}

	/// Returns a full path for a cache-relative path.
	public void GetAssetCachePath(StringView relativePath, String outPath)
	{
		outPath.Clear();
		Path.InternalCombine(outPath, mAssetCacheDirectory, relativePath);
	}

	/// Override to return the window title.
	protected virtual StringView Title => "Sedulous Renderer";

	/// Override to register render features before init.
	protected virtual void OnRegisterFeatures(RenderSystem renderSystem) { }

	/// Override to initialize application-specific resources.
	protected abstract Result<void> OnInit();

	/// Override to update logic each frame (before render).
	protected virtual void OnUpdate(float deltaTime) { }

	/// Override to handle window resize.
	protected virtual void OnResize(uint32 width, uint32 height) { }

	/// Override to clean up application-specific resources (before renderer shutdown).
	protected abstract void OnShutdown();

	/// Override to clean up resources that must outlive the renderer (e.g. features).
	/// Called after RenderSystem.Shutdown().
	protected virtual void OnPostShutdown() { }

	/// Override to request device features.
	protected virtual DeviceFeatures RequiredFeatures => .();

	/// Runs the application. Call from Main().
	public int Run()
	{
		if (Init() case .Err)
		{
			Shutdown();
			return 1;
		}

		MainLoop();
		Shutdown();
		return 0;
	}

	private Result<void> Init()
	{
		DiscoverAssetDirectories();

		// Create shell
		mShell = new Sedulous.Shell.SDL3.SDL3Shell();
		if (mShell.Initialize() case .Err)
		{
			Console.WriteLine("ERROR: Shell initialization failed");
			return .Err;
		}

		// Create window
		var settings = WindowSettings.Default;
		let titleStr = new String(Title);
		defer delete titleStr;
		settings.Title = titleStr;
		settings.Width = (int32)mWidth;
		settings.Height = (int32)mHeight;

		let windowResult = mShell.WindowManager.CreateWindow(settings);
		if (windowResult case .Err)
		{
			Console.WriteLine("ERROR: Window creation failed");
			return .Err;
		}
		mWindow = windowResult.Value;

		// Subscribe to window events
		mShell.WindowManager.OnWindowEvent.Subscribe(new => OnWindowEvent);

		// Create graphics backend
		if (CreateBackend() case .Err)
		{
			Console.WriteLine("ERROR: Backend creation failed");
			return .Err;
		}

		// Create surface from native handle
		void* hwnd = mWindow.NativeHandle;
		if (hwnd == null)
		{
			Console.WriteLine("ERROR: Failed to get native window handle");
			return .Err;
		}

		let surfaceResult = mBackend.CreateSurface(hwnd);
		if (surfaceResult case .Err)
		{
			Console.WriteLine("ERROR: Surface creation failed");
			return .Err;
		}
		mSurface = surfaceResult.Value;

		// Enumerate adapters, pick first, create device
		let adapters = scope List<IAdapter>();
		mBackend.EnumerateAdapters(adapters);
		if (adapters.IsEmpty)
		{
			Console.WriteLine("ERROR: No GPU adapters found");
			return .Err;
		}

		let deviceResult = adapters[0].CreateDevice(DeviceDesc()
		{
			GraphicsQueueCount = 1,
			RequiredFeatures = RequiredFeatures
		});
		if (deviceResult case .Err)
		{
			Console.WriteLine("ERROR: Device creation failed");
			return .Err;
		}
		mDevice = deviceResult.Value;

		mGraphicsQueue = mDevice.GetQueue(.Graphics);
		if (mGraphicsQueue == null)
		{
			Console.WriteLine("ERROR: No graphics queue available");
			return .Err;
		}

		// Create swap chain
		if (CreateSwapChain() case .Err)
		{
			Console.WriteLine("ERROR: Swap chain creation failed");
			return .Err;
		}

		// Create render system
		mRenderSystem = new RenderSystem();
		mWorld = new RenderWorld();
		mView = new RenderView();
		mView.Name = new String(Title);

		mRenderSystem.SetActiveWorld(mWorld);

		// Add shader search paths before initialization
		let shaderPath = scope String();
		GetAssetPath("Shaders", shaderPath);
		mRenderSystem.Shaders.AddSearchPath(shaderPath);

		OnRegisterFeatures(mRenderSystem);

		if (mRenderSystem.Initialize(mDevice, mGraphicsQueue) case .Err)
		{
			Console.WriteLine("ERROR: RenderSystem initialization failed");
			return .Err;
		}

		// App-specific init
		return OnInit();
	}

	private void MainLoop()
	{
		uint64 lastTime = SDL_GetPerformanceCounter();
		uint64 freq = SDL_GetPerformanceFrequency();

		while (mShell.IsRunning)
		{
			mShell.ProcessEvents();

			// Frame timing
			uint64 now = SDL_GetPerformanceCounter();
			mDeltaTime = (float)((double)(now - lastTime) / (double)freq);
			lastTime = now;
			mTotalTime += mDeltaTime;

			if (!mMinimized)
			{
				CheckAndResize();
				OnUpdate(mDeltaTime);

				mRenderSystem.BeginFrame(mTotalTime, mDeltaTime);
				mView.Width = mWidth;
				mView.Height = mHeight;
				mView.UpdateMatrices();
				mRenderSystem.Render(mView, mSwapChain);
			}
		}
	}

	private void OnWindowEvent(IWindow window, WindowEvent event)
	{
		if (window != mWindow)
			return;

		switch (event.Type)
		{
		case .CloseRequested:
			mShell.RequestExit();

		case .Minimized:
			mMinimized = true;

		case .Restored:
			mMinimized = false;

		case .Resized:
			CheckAndResize();

		default:
		}
	}

	private void CheckAndResize()
	{
		let newWidth = (uint32)mWindow.Width;
		let newHeight = (uint32)mWindow.Height;
		if (newWidth > 0 && newHeight > 0 && (newWidth != mWidth || newHeight != mHeight))
		{
			mWidth = newWidth;
			mHeight = newHeight;
			mDevice.WaitIdle();
			mSwapChain.Resize(mWidth, mHeight);
			OnResize(mWidth, mHeight);
		}
	}

	private Result<void> CreateBackend()
	{
		switch (mBackendType)
		{
		case .DX12:
			let result = Sedulous.RHI.DX12.DX12Backend.Create(mValidation);
			if (result case .Ok(let backend))
			{
				mBackend = mValidation ? WrapWithValidation(backend) : backend;
				return .Ok;
			}
			Console.WriteLine("ERROR: DX12Backend.Create failed");
			return .Err;

		case .Vulkan:
			let result = Sedulous.RHI.Vulkan.VulkanBackend.Create(mValidation);
			if (result case .Ok(let backend))
			{
				mBackend = mValidation ? WrapWithValidation(backend) : backend;
				return .Ok;
			}
			Console.WriteLine("ERROR: VulkanBackend.Create failed");
			return .Err;
		}
	}

	private IBackend WrapWithValidation(IBackend inner)
	{
		return CreateValidatedBackend(inner);
	}

	private Result<void> CreateSwapChain()
	{
		let desc = SwapChainDesc()
		{
			Width = mWidth,
			Height = mHeight,
			Format = .BGRA8UnormSrgb,
			PresentMode = .Fifo,
			BufferCount = 2,
		};

		let result = mDevice.CreateSwapChain(mSurface, desc);
		if (result case .Err)
		{
			Console.WriteLine("ERROR: Device.CreateSwapChain failed");
			return .Err;
		}
		mSwapChain = result.Value;
		return .Ok;
	}

	private void Shutdown()
	{
		if (mDevice != null)
			mDevice.WaitIdle();

		OnShutdown();

		if (mRenderSystem != null)
		{
			mRenderSystem.Shutdown();
			delete mRenderSystem;
		}

		OnPostShutdown();

		delete mView;
		delete mWorld;

		if (mSwapChain != null && mDevice != null)
			mDevice.DestroySwapChain(ref mSwapChain);
		if (mSurface != null && mDevice != null)
			mDevice.DestroySurface(ref mSurface);
		if (mDevice != null)
		{
			mDevice.Destroy();
			if (let validated = mDevice as ValidatedDevice)
			{
				let inner = validated.Inner;
				delete validated;
				delete inner;
			}
			else
				delete mDevice;
			mDevice = null;
		}
		if (mBackend != null)
		{
			mBackend.Destroy();
			if (let validated = mBackend as ValidatedBackend)
			{
				let inner = validated.Inner;
				delete validated;
				delete inner;
			}
			else
				delete mBackend;
			mBackend = null;
		}

		if (mWindow != null && mShell != null)
			mShell.WindowManager.DestroyWindow(mWindow);
		if (mShell != null)
		{
			mShell.Shutdown();
			delete mShell;
		}
	}

	/// Discovers asset directories by walking up from CWD looking for Assets/.assets marker.
	private void DiscoverAssetDirectories()
	{
		let currentDir = Directory.GetCurrentDirectory(.. scope .());
		String searchDir = scope .(currentDir);

		while (true)
		{
			let assetsPath = scope String();
			Path.InternalCombine(assetsPath, searchDir, "Assets");

			if (Directory.Exists(assetsPath))
			{
				let markerPath = scope String();
				Path.InternalCombine(markerPath, assetsPath, ".assets");

				if (File.Exists(markerPath))
				{
					mAssetDirectory.Set(assetsPath);
					Path.InternalCombine(mAssetCacheDirectory, searchDir, "Assets", "cache");

					if (!Directory.Exists(mAssetCacheDirectory))
						Directory.CreateDirectory(mAssetCacheDirectory);

					Console.WriteLine(scope $"Asset directory: {mAssetDirectory}");
					return;
				}
			}

			let parentDir = Path.GetDirectoryPath(searchDir, .. scope .());
			if (parentDir.IsEmpty || parentDir == searchDir)
			{
				Console.WriteLine("WARNING: Could not find Assets directory with .assets marker. Using current directory.");
				mAssetDirectory.Set(currentDir);
				mAssetCacheDirectory.Set(currentDir);
				return;
			}

			searchDir.Set(parentDir);
		}
	}
}
