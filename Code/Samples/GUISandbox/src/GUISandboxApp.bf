namespace GUISandbox;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;
using Sedulous.Drawing;
using Sedulous.Fonts;
using Sedulous.GUI;
using Sedulous.Drawing.Fonts;
using Sedulous.Drawing.Renderer;
using Sedulous.Shell.Input;
using Sedulous.GUI.Shell;
using Sedulous.Shaders;
using Sedulous.Imaging;

/// GUI Sandbox sample demonstrating the Sedulous.GUI framework.
/// Features a professional header with theme/scale switching and demo navigation.
class GUISandboxApp : RHISampleApp
{
	// GUI System
	private GUIContext mGUIContext ~ delete _;

	// Main shell with header and navigation
	private MainShell mMainShell ~ delete _;

	// Font service
	private FontService mFontService ~ delete _;

	// Drawing context
	private DrawContext mDrawContext ~ delete _;

	// Drawing renderer
	private DrawingRenderer mDrawingRenderer;

	// Shader system
	private NewShaderSystem mShaderSystem;

	// FPS tracking
	private int mFrameCount = 0;
	private float mFpsTimer = 0;
	private int mCurrentFps = 0;

	// Demo images for Image control demo
	private OwnedImageData mDemoCheckerboard ~ delete _;
	private OwnedImageData mDemoGradient ~ delete _;

	// Clipboard adapter
	private ShellClipboardAdapter mClipboard ~ delete _;

	// Cursor tracking
	private Sedulous.GUI.CursorType mLastCursor = .Default;

	// Key repeat tracking
	private Sedulous.Shell.Input.KeyCode mHeldKey = .Unknown;
	private float mKeyHoldTime = 0;
	private const float KeyRepeatDelay = 0.4f;
	private const float KeyRepeatRate = 0.03f;
	private float mLastRepeatTime = 0;
	private float mFrameDelta = 0;

	public this() : base(.()
		{
			Title = "Sedulous.GUI Sandbox",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		// Initialize fonts
		mFontService = new FontService();

		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 16;

		if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
		{
			Console.WriteLine(scope $"Failed to load font: {fontPath}");
			return false;
		}

		// Initialize shader system
		mShaderSystem = new NewShaderSystem();
		String shaderPath = scope .();
		GetAssetPath("Render/shaders", shaderPath);
		if (mShaderSystem.Initialize(Device, scope StringView[](shaderPath)) case .Err)
		{
			Console.WriteLine("Failed to initialize shader system");
			return false;
		}

		// Create draw context
		mDrawContext = new DrawContext(mFontService);

		// Initialize drawing renderer
		mDrawingRenderer = new DrawingRenderer();
		if (mDrawingRenderer.Initialize(Device, SwapChain.Format, MAX_FRAMES_IN_FLIGHT, mShaderSystem) case .Err)
		{
			Console.WriteLine("Failed to initialize drawing renderer");
			return false;
		}

		// Create demo images for Image control demo
		CreateDemoImages();

		// Initialize GUI
		InitializeGUI();

		Console.WriteLine("Sedulous.GUI Sandbox initialized.");
		Console.WriteLine("  Use the header controls to switch demos, themes, and scale.");
		Console.WriteLine("  F2: Toggle debug overlay | ESC: Exit");
		return true;
	}

	private void CreateDemoImages()
	{
		// Create a checkerboard pattern image (64x64)
		let checkerboard = Sedulous.Imaging.Image.CreateSolidColor(64, 64, Color.Red);
		mDemoCheckerboard = new OwnedImageData(checkerboard.Width, checkerboard.Height, .RGBA8, checkerboard.Data);
		delete checkerboard;

		// Create a gradient image (80x60)
		let gradient = Sedulous.Imaging.Image.CreateGradient(80, 60, Color(100, 200, 100, 255), Color(100, 100, 200, 255), .RGBA8);
		mDemoGradient = new OwnedImageData(gradient.Width, gradient.Height, .RGBA8, gradient.Data);
		delete gradient;
	}

	private void InitializeGUI()
	{
		mGUIContext = new GUIContext();
		mGUIContext.SetViewportSize((float)SwapChain.Width, (float)SwapChain.Height);

		// Register clipboard adapter
		mClipboard = new ShellClipboardAdapter(mShell.Clipboard);
		mGUIContext.RegisterClipboard(mClipboard);

		// Register font service for text rendering
		mGUIContext.RegisterService<IFontService>(mFontService);

		// Create main shell
		mMainShell = new MainShell(mGUIContext, mDemoCheckerboard, mDemoGradient);
		mMainShell.Create();
		mGUIContext.RootElement = mMainShell.Root;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		// Get modifiers using InputMapping
		let modifiers = InputMapping.MapModifiers(keyboard.Modifiers);

		// Toggle debug overlay with F2
		if (keyboard.IsKeyPressed(.F2))
		{
			mMainShell.ToggleDebugMode();
		}

		// Route mouse input to GUI
		float mouseX = mouse.X;
		float mouseY = mouse.Y;
		mGUIContext.ProcessMouseMove(mouseX, mouseY);

		// Update cursor based on hovered element
		UpdateCursor(mouse);

		if (mouse.IsButtonPressed(.Left))
			mGUIContext.ProcessMouseDown(mouseX, mouseY, .Left, modifiers);
		if (mouse.IsButtonReleased(.Left))
			mGUIContext.ProcessMouseUp(mouseX, mouseY, .Left, modifiers);

		if (mouse.IsButtonPressed(.Right))
			mGUIContext.ProcessMouseDown(mouseX, mouseY, .Right, modifiers);
		if (mouse.IsButtonReleased(.Right))
			mGUIContext.ProcessMouseUp(mouseX, mouseY, .Right, modifiers);

		// Forward mouse wheel to GUI
		if (mouse.ScrollY != 0)
			mGUIContext.ProcessMouseWheel(mouseX, mouseY, mouse.ScrollY, modifiers);

		// Forward navigation and editing keys to GUI
		ForwardKeyIfPressed(keyboard, .Tab, modifiers);
		ForwardKeyIfPressed(keyboard, .Left, modifiers);
		ForwardKeyIfPressed(keyboard, .Right, modifiers);
		ForwardKeyIfPressed(keyboard, .Up, modifiers);
		ForwardKeyIfPressed(keyboard, .Down, modifiers);
		ForwardKeyIfPressed(keyboard, .Home, modifiers);
		ForwardKeyIfPressed(keyboard, .End, modifiers);
		ForwardKeyIfPressed(keyboard, .PageUp, modifiers);
		ForwardKeyIfPressed(keyboard, .PageDown, modifiers);
		ForwardKeyIfPressed(keyboard, .Backspace, modifiers);
		ForwardKeyIfPressed(keyboard, .Delete, modifiers);
		ForwardKeyIfPressed(keyboard, .Return, modifiers);

		// Forward Ctrl+key shortcuts
		if (modifiers.HasFlag(.Ctrl))
		{
			ForwardKeyIfPressed(keyboard, .A, modifiers);
			ForwardKeyIfPressed(keyboard, .C, modifiers);
			ForwardKeyIfPressed(keyboard, .V, modifiers);
			ForwardKeyIfPressed(keyboard, .X, modifiers);
			ForwardKeyIfPressed(keyboard, .Z, modifiers);
			ForwardKeyIfPressed(keyboard, .Y, modifiers);
		}

		// Forward Alt key for menu accelerators
		ForwardKeyIfPressed(keyboard, .LeftAlt, modifiers);
		ForwardKeyIfPressed(keyboard, .RightAlt, modifiers);

		// Forward Alt+letter for menu accelerators
		if (modifiers.HasFlag(.Alt))
		{
			ForwardAllLetterKeys(keyboard, modifiers);
		}

		// Generate text input for printable keys
		if (!modifiers.HasFlag(.Ctrl) && !modifiers.HasFlag(.Alt))
		{
			ForwardAllTextInput(keyboard, modifiers);
		}

		// Handle key repeat for held keys
		HandleKeyRepeat(keyboard, modifiers);
	}

	private void ForwardAllLetterKeys(Sedulous.Shell.Input.IKeyboard keyboard, Sedulous.GUI.KeyModifiers modifiers)
	{
		Sedulous.Shell.Input.KeyCode[?] letters = .(
			.A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M,
			.N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z
		);
		for (let key in letters)
			ForwardKeyIfPressed(keyboard, key, modifiers);
	}

	private void ForwardAllTextInput(Sedulous.Shell.Input.IKeyboard keyboard, Sedulous.GUI.KeyModifiers modifiers)
	{
		Sedulous.Shell.Input.KeyCode[?] printableKeys = .(
			.A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M,
			.N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z,
			.Num0, .Num1, .Num2, .Num3, .Num4, .Num5, .Num6, .Num7, .Num8, .Num9,
			.Space, .Minus, .Equals, .LeftBracket, .RightBracket, .Backslash,
			.Semicolon, .Apostrophe, .Grave, .Comma, .Period, .Slash,
			.Keypad0, .Keypad1, .Keypad2, .Keypad3, .Keypad4, .Keypad5,
			.Keypad6, .Keypad7, .Keypad8, .Keypad9, .KeypadPeriod,
			.KeypadDivide, .KeypadMultiply, .KeypadMinus, .KeypadPlus
		);
		for (let key in printableKeys)
			ForwardTextInputIfPressed(keyboard, key, modifiers);
	}

	/// Handles key repeat for held keys.
	private void HandleKeyRepeat(Sedulous.Shell.Input.IKeyboard keyboard, Sedulous.GUI.KeyModifiers modifiers)
	{
		Sedulous.Shell.Input.KeyCode[?] repeatableKeys = .(
			.Backspace, .Delete, .Left, .Right, .Up, .Down, .Home, .End,
			.A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M,
			.N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z,
			.Num0, .Num1, .Num2, .Num3, .Num4, .Num5, .Num6, .Num7, .Num8, .Num9,
			.Space, .Minus, .Equals, .LeftBracket, .RightBracket, .Backslash,
			.Semicolon, .Apostrophe, .Grave, .Comma, .Period, .Slash,
			.Keypad0, .Keypad1, .Keypad2, .Keypad3, .Keypad4, .Keypad5,
			.Keypad6, .Keypad7, .Keypad8, .Keypad9, .KeypadPeriod,
			.KeypadDivide, .KeypadMultiply, .KeypadMinus, .KeypadPlus
		);

		for (let key in repeatableKeys)
		{
			if (keyboard.IsKeyPressed(key))
			{
				mHeldKey = key;
				mKeyHoldTime = 0;
				mLastRepeatTime = 0;
				return;
			}
		}

		if (mHeldKey != .Unknown)
		{
			if (keyboard.IsKeyDown(mHeldKey))
			{
				mKeyHoldTime += mFrameDelta;

				if (mKeyHoldTime >= KeyRepeatDelay)
				{
					mLastRepeatTime += mFrameDelta;
					while (mLastRepeatTime >= KeyRepeatRate)
					{
						mLastRepeatTime -= KeyRepeatRate;

						let guiKey = InputMapping.MapKey(mHeldKey);

						if (mHeldKey == .Backspace || mHeldKey == .Delete ||
							mHeldKey == .Left || mHeldKey == .Right ||
							mHeldKey == .Up || mHeldKey == .Down ||
							mHeldKey == .Home || mHeldKey == .End)
						{
							mGUIContext.InputManager.ProcessKeyDown(guiKey, modifiers);
						}
						else if (!modifiers.HasFlag(.Ctrl) && !modifiers.HasFlag(.Alt))
						{
							let c = InputMapping.KeyToChar(mHeldKey, modifiers.HasFlag(.Shift));
							if (c != '\0')
								mGUIContext.InputManager.ProcessTextInput(c);
						}
					}
				}
			}
			else
			{
				mHeldKey = .Unknown;
				mKeyHoldTime = 0;
				mLastRepeatTime = 0;
			}
		}
	}

	/// Updates the mouse cursor based on the hovered UI element.
	private void UpdateCursor(Sedulous.Shell.Input.IMouse mouse)
	{
		let guiCursor = mGUIContext.CurrentCursor;
		if (guiCursor != mLastCursor)
		{
			mLastCursor = guiCursor;
			mouse.Cursor = InputMapping.MapCursor(guiCursor);
		}
	}

	private void ForwardKeyIfPressed(Sedulous.Shell.Input.IKeyboard keyboard, Sedulous.Shell.Input.KeyCode shellKey, Sedulous.GUI.KeyModifiers modifiers)
	{
		if (keyboard.IsKeyPressed(shellKey))
		{
			let guiKey = InputMapping.MapKey(shellKey);
			mGUIContext.InputManager.ProcessKeyDown(guiKey, modifiers);
		}
	}

	private void ForwardTextInputIfPressed(Sedulous.Shell.Input.IKeyboard keyboard, Sedulous.Shell.Input.KeyCode shellKey, Sedulous.GUI.KeyModifiers modifiers)
	{
		if (keyboard.IsKeyPressed(shellKey))
		{
			let c = InputMapping.KeyToChar(shellKey, modifiers.HasFlag(.Shift));
			if (c != '\0')
				mGUIContext.InputManager.ProcessTextInput(c);
		}
	}

	/// Override to handle Escape key - let GUI handle it first
	protected override bool OnEscapePressed()
	{
		if (mGUIContext.ProcessKeyDown(.Escape, .None))
			return true;
		return false;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mFrameDelta = deltaTime;

		// FPS calculation
		mFrameCount++;
		mFpsTimer += deltaTime;
		if (mFpsTimer >= 1.0f)
		{
			mCurrentFps = mFrameCount;
			mFrameCount = 0;
			mFpsTimer -= 1.0f;

			// Update FPS display in shell
			mMainShell.UpdateFps(mCurrentFps);
		}

		// Update GUI
		mGUIContext.Update(deltaTime, (double)totalTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		BuildDrawCommands();

		// Update renderer
		mDrawingRenderer.UpdateProjection(SwapChain.Width, SwapChain.Height, frameIndex);
		mDrawingRenderer.Prepare(mDrawContext.GetBatch(), frameIndex);
	}

	private void BuildDrawCommands()
	{
		mDrawContext.Clear();

		// Render GUI (includes debug overlay if enabled)
		mGUIContext.Render(mDrawContext);

		// Debug indicator (top-right corner)
		if (mGUIContext.DebugSettings.ShowLayoutBounds)
		{
			let cachedFont = mFontService.GetFont(16);
			let atlasTexture = mFontService.GetAtlasTexture(cachedFont);
			float screenWidth = (float)SwapChain.Width;
			mDrawContext.DrawText("[DEBUG]", cachedFont.Atlas, atlasTexture, .(screenWidth - 70, 60 + cachedFont.Font.Metrics.Ascent), Color.Yellow);
		}
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		mDrawingRenderer.Render(renderPass, SwapChain.Width, SwapChain.Height, (int32)SwapChain.CurrentFrameIndex, useMsaa: false);
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		mGUIContext?.SetViewportSize((float)width, (float)height);
	}

	protected override void OnCleanup()
	{
		// Clean up drawing renderer
		if (mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
			mDrawingRenderer = null;
		}

		// Clean up shader system
		if (mShaderSystem != null)
		{
			mShaderSystem.Dispose();
			delete mShaderSystem;
		}
	}
}
