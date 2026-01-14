namespace Sedulous.EngineNext;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;

/// Concrete application class using SDL3 for windowing and Vulkan for rendering.
/// This is the primary application type for EngineNext.
class SDL3VulkanApplication : Application
{
	protected SDL3Shell mSDL3Shell;
	protected VulkanBackend mBackend;
	protected IAdapter mAdapter;
	protected ISurface mSurface;

	public this()
	{
	}

	public ~this()
	{
	}

	protected override Result<void> CreateShell()
	{
		// Initialize SDL3
		mSDL3Shell = new SDL3Shell();
		if (mSDL3Shell.Initialize() case .Err)
		{
			delete mSDL3Shell;
			mSDL3Shell = null;
			return .Err;
		}
		mShell = mSDL3Shell;

		// Create window
		WindowSettings windowSettings = .()
		{
			Title = mTitle,
			Width = mWidth,
			Height = mHeight,
			Resizable = true,
			Bordered = true
		};

		if (mShell.WindowManager.CreateWindow(windowSettings) case .Ok(let window))
		{
			mWindow = window;
		}
		else
		{
			return .Err;
		}

		// Subscribe to window events
		mShell.WindowManager.OnWindowEvent.Subscribe(new => HandleWindowEvent);

		return .Ok;
	}

	protected override Result<void> CreateDevice()
	{
		// Create Vulkan backend (initialization happens in constructor)
		mBackend = new VulkanBackend(true);  // Enable validation
		if (!mBackend.IsInitialized)
		{
			delete mBackend;
			mBackend = null;
			return .Err;
		}

		// Get adapters
		List<IAdapter> adapters = scope .();
		mBackend.EnumerateAdapters(adapters);
		if (adapters.Count == 0)
			return .Err;

		// Use first adapter
		mAdapter = adapters[0];

		// Create surface from window
		if (mBackend.CreateSurface(mWindow.NativeHandle) case .Ok(let surface))
		{
			mSurface = surface;
		}
		else
		{
			return .Err;
		}

		// Create device from adapter
		if (mAdapter.CreateDevice() case .Ok(let device))
		{
			mDevice = device;
		}
		else
		{
			return .Err;
		}

		// Create swap chain
		SwapChainDescriptor swapChainDesc = .()
		{
			Width = (uint32)mWidth,
			Height = (uint32)mHeight,
			Format = .BGRA8Unorm,
			Usage = .RenderTarget,
			PresentMode = .Fifo
		};

		if (mDevice.CreateSwapChain(mSurface, &swapChainDesc) case .Ok(let swapChain))
		{
			mSwapChain = swapChain;
		}
		else
		{
			return .Err;
		}

		return .Ok;
	}

	protected override void Shutdown()
	{
		base.Shutdown();

		if (mSurface != null)
		{
			delete mSurface;
			mSurface = null;
		}

		// Note: mAdapter is owned by mBackend, not deleted here

		if (mBackend != null)
		{
			delete mBackend;
			mBackend = null;
		}
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
			Stop();
		default:
		}
	}

	protected virtual void HandleResize()
	{
		if (mWindow.Width == 0 || mWindow.Height == 0)
			return;

		mDevice.WaitIdle();

		mWidth = mWindow.Width;
		mHeight = mWindow.Height;

		mSwapChain.Resize((uint32)mWidth, (uint32)mHeight);

		OnResize(mWidth, mHeight);
	}

	/// Called when the window is resized.
	protected virtual void OnResize(int32 width, int32 height) { }

	// Expose backend for advanced users
	public VulkanBackend Backend => mBackend;
	public ISurface Surface => mSurface;
	public IAdapter Adapter => mAdapter;
}
