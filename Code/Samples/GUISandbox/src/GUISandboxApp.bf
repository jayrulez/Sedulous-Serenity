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

/// A focusable colored rectangle control for testing input and focus.
class FocusableRect : Control
{
	public Color RectColor = Color(100, 150, 200, 255);

	public this()
	{
		// All FocusableRects are focusable by default
		IsFocusable = true;
		IsTabStop = true;
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Default size if not explicitly set
		return .(100, 80);
	}

	protected override void RenderOverride(DrawContext ctx)
	{
		// Draw background with state-aware color
		let bgColor = GetStateBackground();
		ctx.FillRect(ArrangedBounds, bgColor);

		// Draw border (thicker when focused)
		let borderColor = GetStateBorderColor();
		let borderThickness = GetStateBorderThickness();
		if (borderThickness > 0)
		{
			ctx.DrawRect(ArrangedBounds, borderColor, borderThickness);
		}
	}

	protected override Color GetStateBackground()
	{
		// Apply state-based color modifications
		switch (CurrentState)
		{
		case .Disabled:
			return Color((uint8)(RectColor.R / 2), (uint8)(RectColor.G / 2), (uint8)(RectColor.B / 2), RectColor.A);
		case .Pressed:
			return Color(
				(uint8)Math.Min(255, (int)(RectColor.R * 0.7f)),
				(uint8)Math.Min(255, (int)(RectColor.G * 0.7f)),
				(uint8)Math.Min(255, (int)(RectColor.B * 0.7f)),
				RectColor.A);
		case .Hover:
			return Color(
				(uint8)Math.Min(255, RectColor.R + 30),
				(uint8)Math.Min(255, RectColor.G + 30),
				(uint8)Math.Min(255, RectColor.B + 30),
				RectColor.A);
		case .Focused:
			return Color(
				(uint8)Math.Min(255, RectColor.R + 15),
				(uint8)Math.Min(255, RectColor.G + 15),
				(uint8)Math.Min(255, RectColor.B + 15),
				RectColor.A);
		default:
			return RectColor;
		}
	}
}

/// A focusable rectangle that uses theme colors (no explicit colors set).
class ThemedRect : Control
{
	public this()
	{
		IsFocusable = true;
		IsTabStop = true;
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		return .(100, 80);
	}

	protected override void RenderOverride(DrawContext ctx)
	{
		// Uses theme colors via base GetStateBackground/GetStateBorderColor
		let bgColor = GetStateBackground();
		ctx.FillRect(ArrangedBounds, bgColor);

		let borderColor = GetStateBorderColor();
		let borderThickness = GetStateBorderThickness();
		if (borderThickness > 0)
		{
			ctx.DrawRect(ArrangedBounds, borderColor, borderThickness);
		}
	}
}

/// A simple panel for Phase 3 demo.
class DemoPanel : Panel
{
	public this()
	{
		// Don't set explicit background - use theme
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		// Simple horizontal layout
		float x = contentBounds.X + 20;
		float y = contentBounds.Y + 20;
		float spacing = 20;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChild(i);
			if (child == null || child.Visibility == .Collapsed)
				continue;

			let desiredSize = child.DesiredSize;
			child.Arrange(.(x, y, desiredSize.Width, desiredSize.Height));
			x += desiredSize.Width + spacing;
		}
	}
}

/// GUI Sandbox sample demonstrating the Sedulous.GUI framework.
/// Phase 2: Element hierarchy, input routing, focus management.
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

	// Root panel
	private DemoPanel mRootPanel ~ delete _;


	// FPS tracking
	private int mFrameCount = 0;
	private float mFpsTimer = 0;
	private int mCurrentFps = 0;

	// Track current theme for toggle
	private bool mUsingDarkTheme = true;

	public this() : base(.()
		{
			Title = "GUI Sandbox - Phase 3",
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

		// Initialize GUI
		InitializeGUI();

		Console.WriteLine("GUISandbox Phase 3 initialized.");
		Console.WriteLine("  Click rectangles to focus them");
		Console.WriteLine("  Tab/Shift+Tab to navigate focus");
		Console.WriteLine("  T to toggle theme (Dark/Light)");
		Console.WriteLine("  F2 to toggle debug overlay");
		Console.WriteLine("  ESC to exit");
		return true;
	}

	private void InitializeGUI()
	{
		mGUIContext = new GUIContext();
		mGUIContext.SetViewportSize((float)SwapChain.Width, (float)SwapChain.Height);

		// Create root panel
		mRootPanel = new DemoPanel();
		mRootPanel.Width = 800;
		mRootPanel.Height = 200;
		mRootPanel.Margin = .(50, 100, 50, 50);

		// Create 3 focusable rectangles with different colors
		let rect1 = new FocusableRect();
		rect1.Width = 120;
		rect1.Height = 100;
		rect1.RectColor = Color(200, 80, 80, 255);  // Red
		rect1.TabIndex = 0;
		rect1.BorderThickness = 2;
		rect1.BorderColor = Color(150, 60, 60, 255);
		rect1.FocusBorderColor = Color(255, 200, 100, 255);
		rect1.FocusBorderThickness = 4;
		mRootPanel.AddChild(rect1);

		let rect2 = new FocusableRect();
		rect2.Width = 120;
		rect2.Height = 100;
		rect2.RectColor = Color(80, 180, 80, 255);  // Green
		rect2.TabIndex = 1;
		rect2.BorderThickness = 2;
		rect2.BorderColor = Color(60, 140, 60, 255);
		rect2.FocusBorderColor = Color(255, 200, 100, 255);
		rect2.FocusBorderThickness = 4;
		mRootPanel.AddChild(rect2);

		let rect3 = new FocusableRect();
		rect3.Width = 120;
		rect3.Height = 100;
		rect3.RectColor = Color(80, 120, 200, 255);  // Blue
		rect3.TabIndex = 2;
		rect3.BorderThickness = 2;
		rect3.BorderColor = Color(60, 90, 160, 255);
		rect3.FocusBorderColor = Color(255, 200, 100, 255);
		rect3.FocusBorderThickness = 4;
		mRootPanel.AddChild(rect3);

		// Fourth rectangle uses theme colors (no explicit colors)
		let rect4 = new ThemedRect();
		rect4.Width = 120;
		rect4.Height = 100;
		rect4.TabIndex = 3;
		mRootPanel.AddChild(rect4);

		mGUIContext.RootElement = mRootPanel;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

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
			// Toggle between no debug and full debug
			if (mGUIContext.DebugSettings.ShowLayoutBounds)
				mGUIContext.DebugSettings = .Default;
			else
				mGUIContext.DebugSettings = .() { ShowLayoutBounds = true, ShowFocused = true, ShowHovered = true, ShowHitTestBounds = true  };
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

		// Route keyboard input to GUI (use GUI's KeyModifiers type)
		Sedulous.GUI.KeyModifiers modifiers = .None;
		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
			modifiers |= .Shift;
		if (keyboard.IsKeyDown(.LeftCtrl) || keyboard.IsKeyDown(.RightCtrl))
			modifiers |= .Ctrl;
		if (keyboard.IsKeyDown(.LeftAlt) || keyboard.IsKeyDown(.RightAlt))
			modifiers |= .Alt;

		// Tab navigation
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

		// FPS and theme indicator
		let fpsText = scope $"FPS: {mCurrentFps}";
		mDrawContext.DrawText(fpsText, cachedFont.Atlas, atlasTexture, .(screenWidth - 80, 10 + cachedFont.Font.Metrics.Ascent), Color.Lime);

		// Title with theme
		let themeName = mGUIContext.Theme?.Name ?? "None";
		let titleText = scope $"Sedulous.GUI Phase 3 - Theming [{themeName}]";
		mDrawContext.DrawText(titleText, cachedFont.Atlas, atlasTexture, .(10, 10 + cachedFont.Font.Metrics.Ascent), Color.White);

		// Instructions
		mDrawContext.DrawText("Click to focus | Tab navigate | T theme | F2 debug", cachedFont.Atlas, atlasTexture, .(10, 35 + cachedFont.Font.Metrics.Ascent), Color(180, 180, 180, 255));

		// Focus info
		let focused = mGUIContext.FocusManager?.FocusedElement;
		String focusText = scope .();
		if (focused != null)
			focusText.AppendF("Focused: Element #{0}", focused.Id.Value);
		else
			focusText.Append("Focused: None");
		mDrawContext.DrawText(focusText, cachedFont.Atlas, atlasTexture, .(10, 60 + cachedFont.Font.Metrics.Ascent), Color(200, 200, 100, 255));

		// Status indicators
		if (mGUIContext.DebugSettings.ShowLayoutBounds)
			mDrawContext.DrawText("[DEBUG]", cachedFont.Atlas, atlasTexture, .(screenWidth - 70, 35 + cachedFont.Font.Metrics.Ascent), Color.Yellow);
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
