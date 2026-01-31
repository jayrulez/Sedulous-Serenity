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

	public this() : base(.()
		{
			Title = "GUI Sandbox - Phase 3, 4, 5 & 6",
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

		Console.WriteLine("GUISandbox Phase 3, 4, 5 & 6 initialized.");
		Console.WriteLine("  0: Focus & Theme demo (Phase 3)");
		Console.WriteLine("  1-6: Layout demos (Phase 4)");
		Console.WriteLine("    1: StackPanel  2: Grid  3: Canvas");
		Console.WriteLine("    4: DockPanel   5: WrapPanel  6: SplitPanel");
		Console.WriteLine("  7: Display Controls (Phase 5)");
		Console.WriteLine("  8: Interactive Controls (Phase 6)");
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
		}

		mGUIContext.RootElement = mDemoRoot;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		// Switch demos with number keys
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

		// UI Scale with Ctrl+/Ctrl-
		bool ctrlDown = keyboard.IsKeyDown(.LeftCtrl) || keyboard.IsKeyDown(.RightCtrl);
		if (ctrlDown && keyboard.IsKeyPressed(.Equals)) // Ctrl + (=/+)
		{
			mGUIContext.ScaleFactor = mGUIContext.ScaleFactor + 0.1f;
			Console.WriteLine(scope $"UI Scale: {mGUIContext.ScaleFactor:0.0}x");
		}
		if (ctrlDown && keyboard.IsKeyPressed(.Minus)) // Ctrl -
		{
			mGUIContext.ScaleFactor = mGUIContext.ScaleFactor - 0.1f;
			Console.WriteLine(scope $"UI Scale: {mGUIContext.ScaleFactor:0.0}x");
		}

		// Toggle theme with T
		if (keyboard.IsKeyPressed(.T))
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

		// Route mouse input to GUI
		float mouseX = mouse.X;
		float mouseY = mouse.Y;
		mGUIContext.InputManager.ProcessMouseMove(mouseX, mouseY);

		if (mouse.IsButtonPressed(.Left))
			mGUIContext.InputManager.ProcessMouseDown(mouseX, mouseY, .Left);
		if (mouse.IsButtonReleased(.Left))
			mGUIContext.InputManager.ProcessMouseUp(mouseX, mouseY, .Left);

		if (mouse.IsButtonPressed(.Right))
			mGUIContext.InputManager.ProcessMouseDown(mouseX, mouseY, .Right);
		if (mouse.IsButtonReleased(.Right))
			mGUIContext.InputManager.ProcessMouseUp(mouseX, mouseY, .Right);

		// Route keyboard input to GUI
		Sedulous.GUI.KeyModifiers modifiers = .None;
		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
			modifiers |= .Shift;
		if (keyboard.IsKeyDown(.LeftCtrl) || keyboard.IsKeyDown(.RightCtrl))
			modifiers |= .Ctrl;
		if (keyboard.IsKeyDown(.LeftAlt) || keyboard.IsKeyDown(.RightAlt))
			modifiers |= .Alt;

		if (keyboard.IsKeyPressed(.Tab))
			mGUIContext.InputManager.ProcessKeyDown(.Tab, modifiers);
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
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
		mDrawContext.DrawText("0:Focus 1-6:Layout 7:Display 8:Interactive | T:theme Tab:focus F2:debug Ctrl+/-:scale", cachedFont.Atlas, atlasTexture, .(10, 35 + cachedFont.Font.Metrics.Ascent), Color(180, 180, 180, 255));

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
