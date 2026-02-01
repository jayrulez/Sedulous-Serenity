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
/// Phase 3: Theming, Phase 4: Layout Panels, Phase 5: Display Controls, Phase 6: Interactive Controls
class GUISandboxApp : RHISampleApp
{
	// GUI System
	private GUIContext mGUIContext ~ delete _;

	// Font service
	private FontService mFontService ~ delete _;

	// Drawing context
	private DrawContext mDrawContext ~ delete _;

	// Drawing renderer
	private DrawingRenderer mDrawingRenderer;

	// Shader system
	private NewShaderSystem mShaderSystem;

	// Current demo
	private DemoType mCurrentDemo = .FocusAndTheme;

	// Demo root (we recreate on switch)
	private UIElement mDemoRoot ~ delete _;

	// FPS tracking
	private int mFrameCount = 0;
	private float mFpsTimer = 0;
	private int mCurrentFps = 0;

	// Track current theme for toggle
	private bool mUsingDarkTheme = true;

	// Demo images for Image control demo
	private OwnedImageData mDemoCheckerboard ~ delete _;
	private OwnedImageData mDemoGradient ~ delete _;

	// Interactive controls demo instance (has state)
	private InteractiveControlsDemo mInteractiveDemo ~ delete _;

	// Text input demo instance (has state)
	private TextInputDemo mTextInputDemo ~ delete _;

	// Scrolling demo instance (has state)
	private ScrollingDemo mScrollingDemo ~ delete _;

	// List controls demo instance (has state)
	private ListControlsDemo mListControlsDemo ~ delete _;

	// Tab navigation demo instance (has state)
	private TabNavigationDemo mTabNavigationDemo ~ delete _;

	// Clipboard adapter
	private ShellClipboardAdapter mClipboard ~ delete _;

	// Cursor tracking
	private Sedulous.GUI.CursorType mLastCursor = .Default;

	// Key repeat tracking
	private Sedulous.Shell.Input.KeyCode mHeldKey = .Unknown;
	private float mKeyHoldTime = 0;
	private const float KeyRepeatDelay = 0.4f; // Initial delay before repeat
	private const float KeyRepeatRate = 0.03f; // Time between repeats
	private float mLastRepeatTime = 0;
	private float mFrameDelta = 0;

	public this() : base(.()
		{
			Title = "GUI Sandbox - Phase 3, 4, 5, 6 & 7",
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

		Console.WriteLine("GUISandbox Phase 3, 4, 5, 6 & 7 initialized.");
		Console.WriteLine("  0: Focus & Theme demo (Phase 3)");
		Console.WriteLine("  1-6: Layout demos (Phase 4)");
		Console.WriteLine("    1: StackPanel  2: Grid  3: Canvas");
		Console.WriteLine("    4: DockPanel   5: WrapPanel  6: SplitPanel");
		Console.WriteLine("  7: Display Controls (Phase 5)");
		Console.WriteLine("  8: Interactive Controls (Phase 6)");
		Console.WriteLine("  9: Text Input Controls (Phase 7)");
		Console.WriteLine("  A: Scrolling & Range Controls (Phase 8)");
		Console.WriteLine("  B: List Controls (Phase 9)");
		Console.WriteLine("  C: Tab & Navigation Controls (Phase 10)");
		Console.WriteLine("  T: Toggle theme | Tab: Navigate focus | F2: Debug");
		Console.WriteLine("  Ctrl +/-: Adjust UI scale");
		Console.WriteLine("  ESC: Exit");
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

		// Create initial demo
		SwitchDemo(.FocusAndTheme);
	}

	private void SwitchDemo(DemoType demo)
	{
		mCurrentDemo = demo;

		// Remove old demo
		if (mDemoRoot != null)
		{
			mGUIContext.RootElement = null;
			delete mDemoRoot;
			mDemoRoot = null;
		}

		// Clean up interactive demo when switching away
		if (demo != .InteractiveControls && mInteractiveDemo != null)
		{
			delete mInteractiveDemo;
			mInteractiveDemo = null;
		}

		// Clean up text input demo when switching away
		if (demo != .TextInput && mTextInputDemo != null)
		{
			delete mTextInputDemo;
			mTextInputDemo = null;
		}

		// Clean up scrolling demo when switching away
		if (demo != .Scrolling && mScrollingDemo != null)
		{
			delete mScrollingDemo;
			mScrollingDemo = null;
		}

		// Clean up list controls demo when switching away
		if (demo != .ListControls && mListControlsDemo != null)
		{
			delete mListControlsDemo;
			mListControlsDemo = null;
		}

		// Clean up tab navigation demo when switching away
		if (demo != .TabNavigation && mTabNavigationDemo != null)
		{
			delete mTabNavigationDemo;
			mTabNavigationDemo = null;
		}

		// Create new demo
		switch (demo)
		{
		case .FocusAndTheme:
			mDemoRoot = FocusAndThemeDemo.Create();
		case .StackPanel:
			mDemoRoot = LayoutDemos.CreateStackPanel();
		case .Grid:
			mDemoRoot = LayoutDemos.CreateGrid();
		case .Canvas:
			mDemoRoot = LayoutDemos.CreateCanvas();
		case .DockPanel:
			mDemoRoot = LayoutDemos.CreateDockPanel();
		case .WrapPanel:
			mDemoRoot = LayoutDemos.CreateWrapPanel();
		case .SplitPanel:
			mDemoRoot = LayoutDemos.CreateSplitPanel();
		case .DisplayControls:
			mDemoRoot = DisplayControlsDemo.Create(mDemoCheckerboard, mDemoGradient);
		case .InteractiveControls:
			if (mInteractiveDemo == null)
				mInteractiveDemo = new InteractiveControlsDemo();
			mDemoRoot = mInteractiveDemo.Create();
		case .TextInput:
			if (mTextInputDemo == null)
				mTextInputDemo = new TextInputDemo();
			mDemoRoot = mTextInputDemo.Create();
		case .Scrolling:
			if (mScrollingDemo == null)
				mScrollingDemo = new ScrollingDemo();
			mDemoRoot = mScrollingDemo.CreateDemo();
		case .ListControls:
			if (mListControlsDemo == null)
				mListControlsDemo = new ListControlsDemo();
			mDemoRoot = mListControlsDemo.CreateDemo();
		case .TabNavigation:
			if (mTabNavigationDemo == null)
				mTabNavigationDemo = new TabNavigationDemo();
			mDemoRoot = mTabNavigationDemo.CreateDemo();
		}

		mGUIContext.RootElement = mDemoRoot;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		// Get modifiers using InputMapping
		let modifiers = InputMapping.MapModifiers(keyboard.Modifiers);

		// Switch demos with number keys (only when not typing in a text control)
		// Skip demo switching when a textbox has focus
		bool textControlFocused = mCurrentDemo == .TextInput && mGUIContext.FocusManager?.FocusedElement != null;
		if (!textControlFocused)
		{
			if (keyboard.IsKeyPressed(.Num0) || keyboard.IsKeyPressed(.Keypad0))
				SwitchDemo(.FocusAndTheme);
			if (keyboard.IsKeyPressed(.Num1) || keyboard.IsKeyPressed(.Keypad1))
				SwitchDemo(.StackPanel);
			if (keyboard.IsKeyPressed(.Num2) || keyboard.IsKeyPressed(.Keypad2))
				SwitchDemo(.Grid);
			if (keyboard.IsKeyPressed(.Num3) || keyboard.IsKeyPressed(.Keypad3))
				SwitchDemo(.Canvas);
			if (keyboard.IsKeyPressed(.Num4) || keyboard.IsKeyPressed(.Keypad4))
				SwitchDemo(.DockPanel);
			if (keyboard.IsKeyPressed(.Num5) || keyboard.IsKeyPressed(.Keypad5))
				SwitchDemo(.WrapPanel);
			if (keyboard.IsKeyPressed(.Num6) || keyboard.IsKeyPressed(.Keypad6))
				SwitchDemo(.SplitPanel);
			if (keyboard.IsKeyPressed(.Num7) || keyboard.IsKeyPressed(.Keypad7))
				SwitchDemo(.DisplayControls);
			if (keyboard.IsKeyPressed(.Num8) || keyboard.IsKeyPressed(.Keypad8))
				SwitchDemo(.InteractiveControls);
			if (keyboard.IsKeyPressed(.Num9) || keyboard.IsKeyPressed(.Keypad9))
				SwitchDemo(.TextInput);
			if (keyboard.IsKeyPressed(.A))
				SwitchDemo(.Scrolling);
			if (keyboard.IsKeyPressed(.B))
				SwitchDemo(.ListControls);
			if (keyboard.IsKeyPressed(.C))
				SwitchDemo(.TabNavigation);
		}

		// UI Scale with Ctrl+/Ctrl-
		if (modifiers.HasFlag(.Ctrl) && keyboard.IsKeyPressed(.Equals)) // Ctrl + (=/+)
		{
			mGUIContext.ScaleFactor = mGUIContext.ScaleFactor + 0.1f;
			Console.WriteLine(scope $"UI Scale: {mGUIContext.ScaleFactor:0.0}x");
		}
		if (modifiers.HasFlag(.Ctrl) && keyboard.IsKeyPressed(.Minus)) // Ctrl -
		{
			mGUIContext.ScaleFactor = mGUIContext.ScaleFactor - 0.1f;
			Console.WriteLine(scope $"UI Scale: {mGUIContext.ScaleFactor:0.0}x");
		}

		// Toggle theme with T (only when not in text input demo with focus)
		if (!textControlFocused && keyboard.IsKeyPressed(.T))
		{
			mUsingDarkTheme = !mUsingDarkTheme;
			if (mUsingDarkTheme)
				mGUIContext.Theme = new DarkTheme();
			else
				mGUIContext.Theme = new LightTheme();
		}

		// Toggle debug overlay with F2
		if (keyboard.IsKeyPressed(.F2))
		{
			if (mGUIContext.DebugSettings.ShowLayoutBounds)
				mGUIContext.DebugSettings = .Default;
			else
				mGUIContext.DebugSettings = .() { ShowLayoutBounds = true, ShowFocused = true, ShowHovered = true, ShowHitTestBounds = true };
		}

		// Route mouse input to GUI (use GUIContext methods for proper scaling)
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

		// Forward mouse wheel to GUI (with modifiers for Shift+wheel horizontal scroll)
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

		// Generate text input for printable keys as fallback
		// Skip when Ctrl or Alt are held - those are shortcuts, not text input
		if (!modifiers.HasFlag(.Ctrl) && !modifiers.HasFlag(.Alt))
		{
			// Check all printable keys using InputMapping.KeyToChar
			ForwardTextInputIfPressed(keyboard, .A, modifiers);
			ForwardTextInputIfPressed(keyboard, .B, modifiers);
			ForwardTextInputIfPressed(keyboard, .C, modifiers);
			ForwardTextInputIfPressed(keyboard, .D, modifiers);
			ForwardTextInputIfPressed(keyboard, .E, modifiers);
			ForwardTextInputIfPressed(keyboard, .F, modifiers);
			ForwardTextInputIfPressed(keyboard, .G, modifiers);
			ForwardTextInputIfPressed(keyboard, .H, modifiers);
			ForwardTextInputIfPressed(keyboard, .I, modifiers);
			ForwardTextInputIfPressed(keyboard, .J, modifiers);
			ForwardTextInputIfPressed(keyboard, .K, modifiers);
			ForwardTextInputIfPressed(keyboard, .L, modifiers);
			ForwardTextInputIfPressed(keyboard, .M, modifiers);
			ForwardTextInputIfPressed(keyboard, .N, modifiers);
			ForwardTextInputIfPressed(keyboard, .O, modifiers);
			ForwardTextInputIfPressed(keyboard, .P, modifiers);
			ForwardTextInputIfPressed(keyboard, .Q, modifiers);
			ForwardTextInputIfPressed(keyboard, .R, modifiers);
			ForwardTextInputIfPressed(keyboard, .S, modifiers);
			ForwardTextInputIfPressed(keyboard, .T, modifiers);
			ForwardTextInputIfPressed(keyboard, .U, modifiers);
			ForwardTextInputIfPressed(keyboard, .V, modifiers);
			ForwardTextInputIfPressed(keyboard, .W, modifiers);
			ForwardTextInputIfPressed(keyboard, .X, modifiers);
			ForwardTextInputIfPressed(keyboard, .Y, modifiers);
			ForwardTextInputIfPressed(keyboard, .Z, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num0, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num1, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num2, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num3, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num4, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num5, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num6, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num7, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num8, modifiers);
			ForwardTextInputIfPressed(keyboard, .Num9, modifiers);
			ForwardTextInputIfPressed(keyboard, .Space, modifiers);
			ForwardTextInputIfPressed(keyboard, .Minus, modifiers);
			ForwardTextInputIfPressed(keyboard, .Equals, modifiers);
			ForwardTextInputIfPressed(keyboard, .LeftBracket, modifiers);
			ForwardTextInputIfPressed(keyboard, .RightBracket, modifiers);
			ForwardTextInputIfPressed(keyboard, .Backslash, modifiers);
			ForwardTextInputIfPressed(keyboard, .Semicolon, modifiers);
			ForwardTextInputIfPressed(keyboard, .Apostrophe, modifiers);
			ForwardTextInputIfPressed(keyboard, .Grave, modifiers);
			ForwardTextInputIfPressed(keyboard, .Comma, modifiers);
			ForwardTextInputIfPressed(keyboard, .Period, modifiers);
			ForwardTextInputIfPressed(keyboard, .Slash, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad0, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad1, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad2, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad3, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad4, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad5, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad6, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad7, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad8, modifiers);
			ForwardTextInputIfPressed(keyboard, .Keypad9, modifiers);
			ForwardTextInputIfPressed(keyboard, .KeypadDivide, modifiers);
			ForwardTextInputIfPressed(keyboard, .KeypadMultiply, modifiers);
			ForwardTextInputIfPressed(keyboard, .KeypadMinus, modifiers);
			ForwardTextInputIfPressed(keyboard, .KeypadPlus, modifiers);
			ForwardTextInputIfPressed(keyboard, .KeypadPeriod, modifiers);
		}

		// Handle key repeat for held keys
		HandleKeyRepeat(keyboard, modifiers);
	}

	/// Handles key repeat for held keys.
	private void HandleKeyRepeat(Sedulous.Shell.Input.IKeyboard keyboard, Sedulous.GUI.KeyModifiers modifiers)
	{
		// Check editing keys (these should repeat)
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
				// New key pressed - start tracking
				mHeldKey = key;
				mKeyHoldTime = 0;
				mLastRepeatTime = 0;
				return; // Initial press already handled
			}
		}

		// Check if the currently held key is still down
		if (mHeldKey != .Unknown)
		{
			if (keyboard.IsKeyDown(mHeldKey))
			{
				mKeyHoldTime += mFrameDelta;

				// After initial delay, start repeating
				if (mKeyHoldTime >= KeyRepeatDelay)
				{
					mLastRepeatTime += mFrameDelta;
					while (mLastRepeatTime >= KeyRepeatRate)
					{
						mLastRepeatTime -= KeyRepeatRate;

						// Generate repeat event
						let guiKey = InputMapping.MapKey(mHeldKey);

						// For editing keys, send key down
						if (mHeldKey == .Backspace || mHeldKey == .Delete ||
							mHeldKey == .Left || mHeldKey == .Right ||
							mHeldKey == .Up || mHeldKey == .Down ||
							mHeldKey == .Home || mHeldKey == .End)
						{
							mGUIContext.InputManager.ProcessKeyDown(guiKey, modifiers);
						}
						else if (!modifiers.HasFlag(.Ctrl) && !modifiers.HasFlag(.Alt))
						{
							// For printable keys, send text input
							let c = InputMapping.KeyToChar(mHeldKey, modifiers.HasFlag(.Shift));
							if (c != '\0')
								mGUIContext.InputManager.ProcessTextInput(c);
						}
					}
				}
			}
			else
			{
				// Key released
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

		// FPS and info overlay
		float screenWidth = (float)SwapChain.Width;
		let cachedFont = mFontService.GetFont(16);
		let atlasTexture = mFontService.GetAtlasTexture(cachedFont);

		// FPS
		let fpsText = scope $"FPS: {mCurrentFps}";
		mDrawContext.DrawText(fpsText, cachedFont.Atlas, atlasTexture, .(screenWidth - 80, 10 + cachedFont.Font.Metrics.Ascent), Color.Lime);

		// Title with current demo and theme
		let demoName = GetDemoName(mCurrentDemo);
		let themeName = mGUIContext.Theme?.Name ?? "None";
		let titleText = scope $"Sedulous.GUI - {demoName} [{themeName}]";
		mDrawContext.DrawText(titleText, cachedFont.Atlas, atlasTexture, .(10, 10 + cachedFont.Font.Metrics.Ascent), Color.White);

		// Instructions
		mDrawContext.DrawText("0:Focus 1-6:Layout 7:Display 8:Interactive 9:TextInput | T:theme Tab:focus F2:debug", cachedFont.Atlas, atlasTexture, .(10, 35 + cachedFont.Font.Metrics.Ascent), Color(180, 180, 180, 255));

		// Focus info (only for focus demo)
		if (mCurrentDemo == .FocusAndTheme)
		{
			let focused = mGUIContext.FocusManager?.FocusedElement;
			String focusText = scope .();
			if (focused != null)
				focusText.AppendF("Focused: Element #{0}", focused.Id.Value);
			else
				focusText.Append("Focused: None (click to focus, Tab to navigate)");
			mDrawContext.DrawText(focusText, cachedFont.Atlas, atlasTexture, .(10, 55 + cachedFont.Font.Metrics.Ascent), Color(200, 200, 100, 255));
		}

		// Debug indicator
		if (mGUIContext.DebugSettings.ShowLayoutBounds)
			mDrawContext.DrawText("[DEBUG]", cachedFont.Atlas, atlasTexture, .(screenWidth - 70, 35 + cachedFont.Font.Metrics.Ascent), Color.Yellow);
	}

	private StringView GetDemoName(DemoType demo)
	{
		switch (demo)
		{
		case .FocusAndTheme: return "Focus & Theme";
		case .StackPanel: return "StackPanel";
		case .Grid: return "Grid";
		case .Canvas: return "Canvas";
		case .DockPanel: return "DockPanel";
		case .WrapPanel: return "WrapPanel";
		case .SplitPanel: return "SplitPanel";
		case .DisplayControls: return "Display Controls";
		case .InteractiveControls: return "Interactive Controls";
		case .TextInput: return "Text Input";
		case .Scrolling: return "Scrolling";
		case .ListControls: return "List Controls";
		case .TabNavigation: return "Tab Navigation";
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
