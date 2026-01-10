namespace Sedulous.AppFramework;

using System;
using System.Collections;
using System.Diagnostics;
using System.IO;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;
using Sedulous.Drawing;
using Sedulous.Fonts;
using Sedulous.Fonts.TTF;
using Sedulous.UI;
using Sedulous.UI.Renderer;

// Type aliases to resolve ambiguity
typealias RHITexture = Sedulous.RHI.ITexture;
typealias DrawingTexture = Sedulous.Drawing.ITexture;
typealias ShellKeyCode = Sedulous.Shell.Input.KeyCode;
typealias UIKeyCode = Sedulous.UI.KeyCode;
typealias UIKeyModifiers = Sedulous.UI.KeyModifiers;

/// Configuration for an application.
public struct ApplicationConfig
{
	public StringView Title = "Application";
	public int32 Width = 1280;
	public int32 Height = 720;
	public bool Resizable = true;
	public bool EnableValidation = true;
	public TextureFormat SwapChainFormat = .BGRA8UnormSrgb;
	public PresentMode PresentMode = .Fifo;
	public Color ClearColor = .(0.15f, 0.15f, 0.2f, 1.0f);
}

/// Base class for UI applications.
/// Provides integrated RHI, Shell, UI, and UIRenderer support.
public abstract class Application
{
	// Core RHI objects
	protected SDL3Shell mShell;
	protected IWindow mWindow;
	protected IBackend mBackend;
	protected IDevice mDevice;
	protected ISurface mSurface;
	protected ISwapChain mSwapChain;

	// Per-frame command buffers
	protected const int MAX_FRAMES_IN_FLIGHT = 2;
	protected ICommandBuffer[MAX_FRAMES_IN_FLIGHT] mCommandBuffers;

	// UI system
	protected UIContext mUIContext;
	protected UIRenderer mUIRenderer;
	protected DrawContext mDrawContext;

	// Font system
	protected IFont mFont;
	protected IFontAtlas mFontAtlas;
	protected RHITexture mFontTexture;
	protected ITextureView mFontTextureView;
	protected TextureRef mFontTextureRef;

	// Timing
	protected Stopwatch mStopwatch = new .() ~ delete _;
	protected float mDeltaTime;
	protected float mTotalTime;
	private float mLastFrameTime;

	// Error tracking
	private int mConsecutiveErrors = 0;
	private const int MAX_CONSECUTIVE_ERRORS = 10;

	// Configuration
	protected ApplicationConfig mConfig;

	// Running state
	private bool mIsRunning = true;

	// Asset directory path
	private String mAssetDirectory = new .() ~ delete _;

	// Text input delegate
	private delegate void(StringView) mTextInputDelegate ~ delete _;

	public this(ApplicationConfig config)
	{
		mConfig = config;
		DiscoverAssetDirectory();
	}

	//==========================================================================
	// Public Accessors
	//==========================================================================

	public IDevice Device => mDevice;
	public ISwapChain SwapChain => mSwapChain;
	public IWindow Window => mWindow;
	public IShell Shell => mShell;
	public UIContext UIContext => mUIContext;
	public float DeltaTime => mDeltaTime;
	public float TotalTime => mTotalTime;
	public StringView AssetDirectory => mAssetDirectory;

	/// Request application exit.
	public void Exit()
	{
		mIsRunning = false;
		mShell?.RequestExit();
	}

	/// Returns a path relative to the Assets directory.
	public void GetAssetPath(StringView relativePath, String outPath)
	{
		outPath.Clear();
		Path.InternalCombine(outPath, mAssetDirectory, relativePath);
	}

	//==========================================================================
	// Lifecycle - Override in derived classes
	//==========================================================================

	/// Called after RHI and UI setup. Override to create application resources.
	protected virtual bool OnInitialize() => true;

	/// Called to set up the UI tree. Override to build your UI.
	protected virtual void OnUISetup(UIContext context) { }

	/// Called each frame for game logic.
	/// Do NOT write to per-frame GPU buffers here - use OnPrepareFrame instead.
	protected virtual void OnUpdate(float deltaTime) { }

	/// Called after fence wait to prepare per-frame GPU resources.
	protected virtual void OnPrepareFrame(int32 frameIndex) { }

	/// Called to record custom render commands before UI.
	/// Return true if you've begun your own render pass, false to use default clear.
	protected virtual bool OnRender(ICommandEncoder encoder, int32 frameIndex) => false;

	/// Called during cleanup.
	protected virtual void OnCleanup() { }

	/// Called when a key is pressed.
	protected virtual void OnKeyDown(ShellKeyCode key) { }

	/// Called when a key is released.
	protected virtual void OnKeyUp(ShellKeyCode key) { }

	/// Called when the window is resized.
	protected virtual void OnResize(uint32 width, uint32 height) { }

	//==========================================================================
	// Main Entry Point
	//==========================================================================

	/// Run the application main loop.
	public int Run()
	{
		if (!Initialize())
			return 1;

		mStopwatch.Start();

		while (mShell.IsRunning && mIsRunning)
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
				Exit();
				continue;
			}

			// Process key events
			ProcessKeyEvents();

			// Route input to UI
			ProcessUIInput();

			// Update UI
			mUIContext.Update(mDeltaTime, (double)mTotalTime);

			// Application update
			OnUpdate(mDeltaTime);

			// Frame rendering
			if (Frame())
			{
				mConsecutiveErrors = 0;
			}
			else
			{
				mConsecutiveErrors++;
				if (mConsecutiveErrors >= MAX_CONSECUTIVE_ERRORS)
				{
					Console.WriteLine(scope $"Too many consecutive render errors, exiting.");
					Exit();
				}
			}
		}

		mDevice.WaitIdle();
		Cleanup();
		return 0;
	}

	//==========================================================================
	// Private Implementation
	//==========================================================================

	private void DiscoverAssetDirectory()
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
					return;
				}
			}

			let parentDir = Path.GetDirectoryPath(searchDir, .. scope .());
			if (parentDir.IsEmpty || parentDir == searchDir)
			{
				Runtime.FatalError("Could not find Assets directory with .assets marker file.");
			}
			searchDir.Set(parentDir);
		}
	}

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

		// Initialize font system
		if (!InitializeFonts())
		{
			Console.WriteLine("Failed to initialize fonts");
			return false;
		}

		// Initialize UI system
		if (!InitializeUI())
		{
			Console.WriteLine("Failed to initialize UI");
			return false;
		}

		// Initialize UI renderer
		if (!InitializeUIRenderer())
		{
			Console.WriteLine("Failed to initialize UI renderer");
			return false;
		}

		// Let derived class initialize
		if (!OnInitialize())
		{
			Console.WriteLine("Application initialization failed");
			return false;
		}

		// Let derived class setup UI
		OnUISetup(mUIContext);

		Console.WriteLine(scope $"{mConfig.Title} running. Press Escape to exit.");
		return true;
	}

	private bool InitializeFonts()
	{
		// Initialize TrueType font system
		TrueTypeFonts.Initialize();

		// Load default font
		let fontPath = GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", .. scope .());

		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 16;

		if (FontLoaderFactory.LoadFont(fontPath, options) case .Ok(let font))
			mFont = font;
		else
		{
			Console.WriteLine(scope $"Failed to load font: {fontPath}");
			return false;
		}

		// Create font atlas
		if (FontLoaderFactory.CreateAtlas(mFont, options) case .Ok(let atlas))
			mFontAtlas = atlas;
		else
		{
			Console.WriteLine("Failed to create font atlas");
			return false;
		}

		// Get atlas dimensions
		let atlasWidth = mFontAtlas.Width;
		let atlasHeight = mFontAtlas.Height;
		let r8Data = mFontAtlas.PixelData;

		// Convert R8 to RGBA8
		uint8[] rgba8Data = new uint8[atlasWidth * atlasHeight * 4];
		defer delete rgba8Data;

		for (uint32 i = 0; i < atlasWidth * atlasHeight; i++)
		{
			let alpha = r8Data[i];
			rgba8Data[i * 4 + 0] = 255;
			rgba8Data[i * 4 + 1] = 255;
			rgba8Data[i * 4 + 2] = 255;
			rgba8Data[i * 4 + 3] = alpha;
		}

		// Create GPU texture for atlas
		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			atlasWidth, atlasHeight,
			.RGBA8Unorm, .Sampled | .CopyDst
		);
		if (mDevice.CreateTexture(&textureDesc) not case .Ok(let texture))
		{
			Console.WriteLine("Failed to create font texture");
			return false;
		}
		mFontTexture = texture;

		// Upload atlas data
		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = atlasWidth * 4,
			RowsPerImage = atlasHeight
		};
		Extent3D writeSize = .(atlasWidth, atlasHeight, 1);
		mDevice.Queue.WriteTexture(mFontTexture, Span<uint8>(rgba8Data.Ptr, rgba8Data.Count), &dataLayout, &writeSize);

		// Create texture view
		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		if (mDevice.CreateTextureView(mFontTexture, &viewDesc) not case .Ok(let view))
		{
			Console.WriteLine("Failed to create font texture view");
			return false;
		}
		mFontTextureView = view;

		// Create texture reference for Drawing system
		mFontTextureRef = new TextureRef(mFontTexture, atlasWidth, atlasHeight);

		return true;
	}

	private bool InitializeUI()
	{
		// Create draw context
		mDrawContext = new DrawContext();

		// Set white pixel UV for solid color rendering
		let (u, v) = mFontAtlas.WhitePixelUV;
		mDrawContext.WhitePixelUV = .(u, v);

		// Create font service
		let fontService = new AppFontService(mFont, mFontAtlas, mFontTextureRef);

		// Create clipboard adapter
		let clipboard = new AppClipboardAdapter();

		// Create UI context
		mUIContext = new UIContext();
		mUIContext.RegisterClipboard(clipboard);
		mUIContext.RegisterService<IFontService>(fontService);
		mUIContext.SetViewportSize((float)mSwapChain.Width, (float)mSwapChain.Height);

		// Subscribe to text input events
		mTextInputDelegate = new => OnTextInput;
		mShell.InputManager.Keyboard.OnTextInput.Subscribe(mTextInputDelegate);

		return true;
	}

	private bool InitializeUIRenderer()
	{
		mUIRenderer = new UIRenderer();
		if (mUIRenderer.Initialize(mDevice, mSwapChain.Format, (int32)mSwapChain.FrameCount) case .Err)
		{
			Console.WriteLine("Failed to initialize UI renderer");
			return false;
		}

		// Set the font texture for UI rendering
		mUIRenderer.SetTexture(mFontTextureView);

		return true;
	}

	private void ProcessKeyEvents()
	{
		for (int key = 0; key < (int)ShellKeyCode.Count; key++)
		{
			let keyCode = (ShellKeyCode)key;
			if (mShell.InputManager.Keyboard.IsKeyPressed(keyCode))
				OnKeyDown(keyCode);
			if (mShell.InputManager.Keyboard.IsKeyReleased(keyCode))
				OnKeyUp(keyCode);
		}
	}

	private void ProcessUIInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;
		let mods = GetUIModifiers(keyboard);

		// Mouse position
		mUIContext.ProcessMouseMove(mouse.X, mouse.Y, mods);

		// Mouse buttons - pass x, y, modifiers
		if (mouse.IsButtonPressed(.Left))
			mUIContext.ProcessMouseDown(.Left, mouse.X, mouse.Y, mods);
		if (mouse.IsButtonReleased(.Left))
			mUIContext.ProcessMouseUp(.Left, mouse.X, mouse.Y, mods);
		if (mouse.IsButtonPressed(.Right))
			mUIContext.ProcessMouseDown(.Right, mouse.X, mouse.Y, mods);
		if (mouse.IsButtonReleased(.Right))
			mUIContext.ProcessMouseUp(.Right, mouse.X, mouse.Y, mods);
		if (mouse.IsButtonPressed(.Middle))
			mUIContext.ProcessMouseDown(.Middle, mouse.X, mouse.Y, mods);
		if (mouse.IsButtonReleased(.Middle))
			mUIContext.ProcessMouseUp(.Middle, mouse.X, mouse.Y, mods);

		// Mouse wheel
		if (mouse.ScrollX != 0 || mouse.ScrollY != 0)
			mUIContext.ProcessMouseWheel(mouse.ScrollX, mouse.ScrollY, mouse.X, mouse.Y, mods);

		// Keyboard - route to UI
		for (int key = 0; key < (int)ShellKeyCode.Count; key++)
		{
			let shellKey = (ShellKeyCode)key;
			let uiKey = MapKeyCode(shellKey);
			if (keyboard.IsKeyPressed(shellKey))
				mUIContext.ProcessKeyDown(uiKey, 0, mods);
			if (keyboard.IsKeyReleased(shellKey))
				mUIContext.ProcessKeyUp(uiKey, 0, mods);
		}
	}

	private void OnTextInput(StringView text)
	{
		for (let c in text.DecodedChars)
			mUIContext.ProcessTextInput(c);
	}

	private UIKeyModifiers GetUIModifiers(Sedulous.Shell.Input.IKeyboard keyboard)
	{
		UIKeyModifiers mods = .None;
		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
			mods |= .Shift;
		if (keyboard.IsKeyDown(.LeftCtrl) || keyboard.IsKeyDown(.RightCtrl))
			mods |= .Ctrl;
		if (keyboard.IsKeyDown(.LeftAlt) || keyboard.IsKeyDown(.RightAlt))
			mods |= .Alt;
		return mods;
	}

	private static UIKeyCode MapKeyCode(ShellKeyCode shellKey)
	{
		return (UIKeyCode)(int32)shellKey;
	}

	private bool Frame()
	{
		// Acquire next swap chain image
		if (mSwapChain.AcquireNextImage() case .Err)
		{
			HandleResize();
			return true;
		}

		let frameIndex = (int32)mSwapChain.CurrentFrameIndex;

		// Clean up previous command buffer
		if (mCommandBuffers[frameIndex] != null)
		{
			delete mCommandBuffers[frameIndex];
			mCommandBuffers[frameIndex] = null;
		}

		// Prepare phase
		OnPrepareFrame(frameIndex);

		// Build UI draw commands
		mDrawContext.Clear();
		mUIContext.Render(mDrawContext);

		// Prepare UI renderer
		mUIRenderer.UpdateProjection(mSwapChain.Width, mSwapChain.Height, frameIndex);
		mUIRenderer.Prepare(mDrawContext.GetBatch(), frameIndex);

		// Get current texture view
		let textureView = mSwapChain.CurrentTextureView;
		if (textureView == null)
			return false;

		// Create command encoder
		let encoder = mDevice.CreateCommandEncoder();
		if (encoder == null)
			return false;
		defer delete encoder;

		// Let app do custom rendering
		bool customRendering = OnRender(encoder, frameIndex);

		// Default render pass with UI
		if (!customRendering)
		{
			RenderPassColorAttachment[1] colorAttachments = .(.()
			{
				View = textureView,
				ResolveTarget = null,
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = mConfig.ClearColor
			});
			RenderPassDescriptor renderPassDesc = .(colorAttachments);

			let renderPass = encoder.BeginRenderPass(&renderPassDesc);
			if (renderPass == null)
				return false;
			defer delete renderPass;

			// Render UI
			mUIRenderer.Render(renderPass, mSwapChain.Width, mSwapChain.Height, frameIndex);

			renderPass.End();
		}

		// Finish and submit
		let commandBuffer = encoder.Finish();
		if (commandBuffer == null)
			return false;

		mCommandBuffers[frameIndex] = commandBuffer;
		mDevice.Queue.Submit(commandBuffer, mSwapChain);

		if (mSwapChain.Present() case .Err)
			HandleResize();

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

		// Resize swap chain
		if (mSwapChain.Resize((uint32)mWindow.Width, (uint32)mWindow.Height) case .Err)
		{
			Console.WriteLine("Failed to resize swap chain");
			return;
		}

		// Update UI context size
		mUIContext.SetViewportSize((float)mSwapChain.Width, (float)mSwapChain.Height);

		// Notify derived class
		OnResize(mSwapChain.Width, mSwapChain.Height);
	}

	private void Cleanup()
	{
		if (mDevice != null)
			mDevice.WaitIdle();

		// Let derived class cleanup first
		OnCleanup();

		// Unsubscribe from text input events
		if (mTextInputDelegate != null && mShell != null)
			mShell.InputManager.Keyboard.OnTextInput.Unsubscribe(mTextInputDelegate, false);

		// Clean up command buffers
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (mCommandBuffers[i] != null)
			{
				delete mCommandBuffers[i];
				mCommandBuffers[i] = null;
			}
		}

		// UI renderer
		if (mUIRenderer != null)
		{
			mUIRenderer.Dispose();
			delete mUIRenderer;
		}

		// UI context (owns font service and clipboard)
		if (mUIContext != null)
			delete mUIContext;

		// Draw context
		if (mDrawContext != null)
			delete mDrawContext;

		// Font resources
		// NOTE: mFont and mFontAtlas are owned by CachedFont (via AppFontService via UIContext)
		// so we don't delete them here - they're cleaned up when UIContext is deleted
		if (mFontTextureRef != null)
			delete mFontTextureRef;
		if (mFontTextureView != null)
			delete mFontTextureView;
		if (mFontTexture != null)
			delete mFontTexture;

		// RHI resources
		if (mSwapChain != null)
			delete mSwapChain;
		if (mDevice != null)
			delete mDevice;
		if (mSurface != null)
			delete mSurface;
		if (mBackend != null)
			delete mBackend;

		// Shell
		if (mShell != null)
		{
			mShell.Shutdown();
			delete mShell;
		}

		Console.WriteLine("Application finished.");
	}
}

//==========================================================================
// Helper Classes
//==========================================================================

/// Font service implementation for Application.
class AppFontService : IFontService
{
	private CachedFont mCachedFont;
	private DrawingTexture mFontTexture ~ { }; // Not owned
	private String mDefaultFontFamily = new .("Roboto") ~ delete _;

	public this(IFont font, IFontAtlas atlas, DrawingTexture texture)
	{
		mCachedFont = new CachedFont(font, atlas);
		mFontTexture = texture;
	}

	public ~this()
	{
		delete mCachedFont;
	}

	public StringView DefaultFontFamily => mDefaultFontFamily;

	public CachedFont GetFont(float pixelHeight) => mCachedFont;
	public CachedFont GetFont(StringView familyName, float pixelHeight) => mCachedFont;

	public DrawingTexture GetAtlasTexture(CachedFont font) => mFontTexture;
	public DrawingTexture GetAtlasTexture(StringView familyName, float pixelHeight) => mFontTexture;

	public void ReleaseFont(CachedFont font) { }
}

/// Clipboard adapter for Application.
class AppClipboardAdapter : Sedulous.UI.IClipboard
{
	private Sedulous.Shell.IClipboard mShellClipboard ~ delete _;

	public this()
	{
		mShellClipboard = new SDL3Clipboard();
	}

	public Result<void> GetText(String outText) => mShellClipboard.GetText(outText);
	public Result<void> SetText(StringView text) => mShellClipboard.SetText(text);
	public bool HasText => mShellClipboard.HasText;
}
