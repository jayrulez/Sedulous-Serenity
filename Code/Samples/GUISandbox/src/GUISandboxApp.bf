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

/// A simple colored box control for layout demos.
class ColorBox : Control
{
	public Color BoxColor = Color(100, 150, 200, 255);
	public String Label ~ delete _;

	public this(Color color, StringView label = "")
	{
		BoxColor = color;
		if (!label.IsEmpty)
			Label = new String(label);
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Default size - can be overridden by Width/Height
		return .(80, 60);
	}

	protected override void RenderOverride(DrawContext ctx)
	{
		ctx.FillRect(ArrangedBounds, BoxColor);
		ctx.DrawRect(ArrangedBounds, Color(40, 40, 40, 255), 1);
	}
}

/// Enumeration of demos.
enum DemoType
{
	case FocusAndTheme;  // Phase 3: Focus navigation and theming
	case StackPanel;     // Phase 4: Layout panels
	case Grid;
	case Canvas;
	case DockPanel;
	case WrapPanel;
	case SplitPanel;
}

/// GUI Sandbox sample demonstrating the Sedulous.GUI framework.
/// Phase 3: Theming, Phase 4: Layout Panels
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

	public this() : base(.()
		{
			Title = "GUI Sandbox - Phase 3 & 4",
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

		Console.WriteLine("GUISandbox Phase 3 & 4 initialized.");
		Console.WriteLine("  0: Focus & Theme demo (Phase 3)");
		Console.WriteLine("  1-6: Layout demos (Phase 4)");
		Console.WriteLine("    1: StackPanel  2: Grid  3: Canvas");
		Console.WriteLine("    4: DockPanel   5: WrapPanel  6: SplitPanel");
		Console.WriteLine("  T: Toggle theme | Tab: Navigate focus | F2: Debug");
		Console.WriteLine("  ESC: Exit");
		return true;
	}

	private void InitializeGUI()
	{
		mGUIContext = new GUIContext();
		mGUIContext.SetViewportSize((float)SwapChain.Width, (float)SwapChain.Height);

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

		// Create new demo
		switch (demo)
		{
		case .FocusAndTheme:
			mDemoRoot = CreateFocusAndThemeDemo();
		case .StackPanel:
			mDemoRoot = CreateStackPanelDemo();
		case .Grid:
			mDemoRoot = CreateGridDemo();
		case .Canvas:
			mDemoRoot = CreateCanvasDemo();
		case .DockPanel:
			mDemoRoot = CreateDockPanelDemo();
		case .WrapPanel:
			mDemoRoot = CreateWrapPanelDemo();
		case .SplitPanel:
			mDemoRoot = CreateSplitPanelDemo();
		}

		mGUIContext.RootElement = mDemoRoot;
	}

	// === Phase 3: Focus and Theme Demo ===

	private Panel CreateFocusAndThemeDemo()
	{
		let rootPanel = new DemoPanel();
		rootPanel.Width = 800;
		rootPanel.Height = 200;
		rootPanel.Margin = .(50, 100, 50, 50);

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
		rootPanel.AddChild(rect1);

		let rect2 = new FocusableRect();
		rect2.Width = 120;
		rect2.Height = 100;
		rect2.RectColor = Color(80, 180, 80, 255);  // Green
		rect2.TabIndex = 1;
		rect2.BorderThickness = 2;
		rect2.BorderColor = Color(60, 140, 60, 255);
		rect2.FocusBorderColor = Color(255, 200, 100, 255);
		rect2.FocusBorderThickness = 4;
		rootPanel.AddChild(rect2);

		let rect3 = new FocusableRect();
		rect3.Width = 120;
		rect3.Height = 100;
		rect3.RectColor = Color(80, 120, 200, 255);  // Blue
		rect3.TabIndex = 2;
		rect3.BorderThickness = 2;
		rect3.BorderColor = Color(60, 90, 160, 255);
		rect3.FocusBorderColor = Color(255, 200, 100, 255);
		rect3.FocusBorderThickness = 4;
		rootPanel.AddChild(rect3);

		// Fourth rectangle uses theme colors (no explicit colors)
		let rect4 = new ThemedRect();
		rect4.Width = 120;
		rect4.Height = 100;
		rect4.TabIndex = 3;
		rootPanel.AddChild(rect4);

		return rootPanel;
	}

	// === Phase 4: Layout Panel Demos ===

	private Panel CreateStackPanelDemo()
	{
		// Outer container
		let container = new Panel();
		container.Margin = .(50, 80, 50, 50);
		container.Background = Color(30, 30, 35, 255);

		// Vertical StackPanel
		let vStack = new StackPanel();
		vStack.Orientation = .Vertical;
		vStack.Spacing = 10;
		vStack.Margin = .(20, 20, 20, 20);
		vStack.HorizontalAlignment = .Left;
		vStack.VerticalAlignment = .Top;

		// Label row
		let labelBox = new ColorBox(Color(60, 60, 80, 255), "Vertical Stack");
		labelBox.Width = 200;
		labelBox.Height = 30;
		vStack.AddChild(labelBox);

		// Horizontal StackPanel inside
		let hStack = new StackPanel();
		hStack.Orientation = .Horizontal;
		hStack.Spacing = 15;

		let boxA = new ColorBox(Color(200, 80, 80, 255), "A");
		boxA.Width = 80;
		boxA.Height = 80;
		hStack.AddChild(boxA);

		let boxB = new ColorBox(Color(80, 200, 80, 255), "B");
		boxB.Width = 100;
		boxB.Height = 80;
		hStack.AddChild(boxB);

		let boxC = new ColorBox(Color(80, 80, 200, 255), "C");
		boxC.Width = 60;
		boxC.Height = 80;
		hStack.AddChild(boxC);

		let boxD = new ColorBox(Color(200, 200, 80, 255), "D");
		boxD.Width = 90;
		boxD.Height = 80;
		hStack.AddChild(boxD);

		vStack.AddChild(hStack);

		// Another horizontal stack
		let hStack2 = new StackPanel();
		hStack2.Orientation = .Horizontal;
		hStack2.Spacing = 10;

		let box2A = new ColorBox(Color(200, 100, 150, 255));
		box2A.Width = 120;
		box2A.Height = 50;
		hStack2.AddChild(box2A);

		let box2B = new ColorBox(Color(100, 200, 150, 255));
		box2B.Width = 120;
		box2B.Height = 50;
		hStack2.AddChild(box2B);

		let box2C = new ColorBox(Color(150, 100, 200, 255));
		box2C.Width = 120;
		box2C.Height = 50;
		hStack2.AddChild(box2C);

		vStack.AddChild(hStack2);

		// More items
		let boxWide1 = new ColorBox(Color(180, 180, 180, 255));
		boxWide1.Width = 400;
		boxWide1.Height = 40;
		vStack.AddChild(boxWide1);

		let boxWide2 = new ColorBox(Color(140, 140, 140, 255));
		boxWide2.Width = 350;
		boxWide2.Height = 40;
		vStack.AddChild(boxWide2);

		container.AddChild(vStack);
		return container;
	}

	private Panel CreateGridDemo()
	{
		// Grid panel
		let grid = new Grid();
		grid.Margin = .(50, 80, 50, 50);
		grid.Background = Color(30, 30, 35, 255);

		// Define 3 columns: 100px, 1*, 2*
		let col1 = new ColumnDefinition();
		col1.Width = GridLength.Pixels(100);
		grid.ColumnDefinitions.Add(col1);

		let col2 = new ColumnDefinition();
		col2.Width = GridLength.Star;
		grid.ColumnDefinitions.Add(col2);

		let col3 = new ColumnDefinition();
		col3.Width = GridLength.StarN(2);
		grid.ColumnDefinitions.Add(col3);

		// Define 3 rows: Auto, 1*, 80px
		let row1 = new RowDefinition();
		row1.Height = GridLength.Auto;
		grid.RowDefinitions.Add(row1);

		let row2 = new RowDefinition();
		row2.Height = GridLength.Star;
		grid.RowDefinitions.Add(row2);

		let row3 = new RowDefinition();
		row3.Height = GridLength.Pixels(80);
		grid.RowDefinitions.Add(row3);

		// Row 0: Header cells
		let header1 = new ColorBox(Color(80, 80, 120, 255), "100px");
		header1.Height = 40;
		GridProperties.SetRow(header1, 0);
		GridProperties.SetColumn(header1, 0);
		grid.AddChild(header1);

		let header2 = new ColorBox(Color(80, 100, 120, 255), "1*");
		header2.Height = 40;
		GridProperties.SetRow(header2, 0);
		GridProperties.SetColumn(header2, 1);
		grid.AddChild(header2);

		let header3 = new ColorBox(Color(80, 120, 120, 255), "2*");
		header3.Height = 40;
		GridProperties.SetRow(header3, 0);
		GridProperties.SetColumn(header3, 2);
		grid.AddChild(header3);

		// Row 1: Content cells with spanning
		let sidebar = new ColorBox(Color(120, 80, 80, 255), "Sidebar");
		GridProperties.SetRow(sidebar, 1);
		GridProperties.SetColumn(sidebar, 0);
		grid.AddChild(sidebar);

		// Content spans 2 columns
		let content = new ColorBox(Color(80, 120, 80, 255), "Content (spans 2 cols)");
		GridProperties.SetRow(content, 1);
		GridProperties.SetColumn(content, 1);
		GridProperties.SetColumnSpan(content, 2);
		grid.AddChild(content);

		// Row 2: Footer spans all 3 columns
		let footer = new ColorBox(Color(100, 100, 140, 255), "Footer (spans 3 cols, 80px height)");
		GridProperties.SetRow(footer, 2);
		GridProperties.SetColumn(footer, 0);
		GridProperties.SetColumnSpan(footer, 3);
		grid.AddChild(footer);

		return grid;
	}

	private Panel CreateCanvasDemo()
	{
		// Container with Canvas inside
		let container = new Panel();
		container.Margin = .(50, 80, 50, 50);
		container.Background = Color(30, 30, 35, 255);

		let canvas = new Canvas();

		// Absolutely positioned elements
		let box1 = new ColorBox(Color(200, 80, 80, 255), "Left:20, Top:20");
		box1.Width = 150;
		box1.Height = 80;
		CanvasProperties.SetLeft(box1, 20);
		CanvasProperties.SetTop(box1, 20);
		canvas.AddChild(box1);

		let box2 = new ColorBox(Color(80, 200, 80, 255), "Left:200, Top:50");
		box2.Width = 120;
		box2.Height = 100;
		CanvasProperties.SetLeft(box2, 200);
		CanvasProperties.SetTop(box2, 50);
		canvas.AddChild(box2);

		let box3 = new ColorBox(Color(80, 80, 200, 255), "Right:20, Top:20");
		box3.Width = 140;
		box3.Height = 90;
		CanvasProperties.SetRight(box3, 20);
		CanvasProperties.SetTop(box3, 20);
		canvas.AddChild(box3);

		let box4 = new ColorBox(Color(200, 200, 80, 255), "Left:100, Bottom:30");
		box4.Width = 180;
		box4.Height = 70;
		CanvasProperties.SetLeft(box4, 100);
		CanvasProperties.SetBottom(box4, 30);
		canvas.AddChild(box4);

		let box5 = new ColorBox(Color(200, 80, 200, 255), "Right:50, Bottom:50");
		box5.Width = 100;
		box5.Height = 100;
		CanvasProperties.SetRight(box5, 50);
		CanvasProperties.SetBottom(box5, 50);
		canvas.AddChild(box5);

		// Stretched element (both Left and Right set)
		let stretched = new ColorBox(Color(80, 200, 200, 255), "Stretched (L:20, R:20)");
		stretched.Height = 40;
		CanvasProperties.SetLeft(stretched, 20);
		CanvasProperties.SetRight(stretched, 20);
		CanvasProperties.SetBottom(stretched, 150);
		canvas.AddChild(stretched);

		container.AddChild(canvas);
		return container;
	}

	private Panel CreateDockPanelDemo()
	{
		// DockPanel
		let dock = new DockPanel();
		dock.Margin = .(50, 80, 50, 50);
		dock.Background = Color(30, 30, 35, 255);
		dock.LastChildFill = true;

		// Top header
		let header = new ColorBox(Color(80, 80, 140, 255), "Header (Top)");
		header.Height = 60;
		DockPanelProperties.SetDock(header, .Top);
		dock.AddChild(header);

		// Bottom footer
		let footer = new ColorBox(Color(80, 100, 140, 255), "Footer (Bottom)");
		footer.Height = 50;
		DockPanelProperties.SetDock(footer, .Bottom);
		dock.AddChild(footer);

		// Left sidebar
		let leftSidebar = new ColorBox(Color(140, 80, 80, 255), "Left");
		leftSidebar.Width = 120;
		DockPanelProperties.SetDock(leftSidebar, .Left);
		dock.AddChild(leftSidebar);

		// Right panel
		let rightPanel = new ColorBox(Color(140, 100, 80, 255), "Right");
		rightPanel.Width = 100;
		DockPanelProperties.SetDock(rightPanel, .Right);
		dock.AddChild(rightPanel);

		// Center content (fills remaining - last child)
		let content = new ColorBox(Color(80, 140, 80, 255), "Content (Fill)");
		dock.AddChild(content);

		return dock;
	}

	private void AddWrapItem(WrapPanel wrap, Color color, float width, float height)
	{
		let item = new ColorBox(color);
		item.Width = width;
		item.Height = height;
		item.Margin = .(5, 5, 5, 5);
		wrap.AddChild(item);
	}

	private Panel CreateWrapPanelDemo()
	{
		// Container
		let container = new Panel();
		container.Margin = .(50, 80, 50, 50);
		container.Background = Color(30, 30, 35, 255);

		let wrap = new WrapPanel();
		wrap.Orientation = .Horizontal;
		wrap.Margin = .(10, 10, 10, 10);

		// Add items to demonstrate wrapping
		AddWrapItem(wrap, Color(200, 80, 80, 255), 80, 60);
		AddWrapItem(wrap, Color(80, 200, 80, 255), 110, 80);
		AddWrapItem(wrap, Color(80, 80, 200, 255), 140, 60);
		AddWrapItem(wrap, Color(200, 200, 80, 255), 80, 80);
		AddWrapItem(wrap, Color(200, 80, 200, 255), 110, 60);
		AddWrapItem(wrap, Color(80, 200, 200, 255), 140, 80);
		AddWrapItem(wrap, Color(180, 120, 80, 255), 80, 60);
		AddWrapItem(wrap, Color(120, 180, 80, 255), 110, 80);
		AddWrapItem(wrap, Color(80, 120, 180, 255), 140, 60);
		AddWrapItem(wrap, Color(180, 80, 120, 255), 80, 80);
		AddWrapItem(wrap, Color(120, 80, 180, 255), 110, 60);
		AddWrapItem(wrap, Color(80, 180, 120, 255), 140, 80);
		AddWrapItem(wrap, Color(160, 160, 80, 255), 80, 60);
		AddWrapItem(wrap, Color(160, 80, 160, 255), 110, 80);
		AddWrapItem(wrap, Color(80, 160, 160, 255), 140, 60);

		container.AddChild(wrap);
		return container;
	}

	private Panel CreateSplitPanelDemo()
	{
		// Outer SplitPanel (horizontal)
		let outerSplit = new SplitPanel();
		outerSplit.Margin = .(50, 80, 50, 50);
		outerSplit.Orientation = .Horizontal;
		outerSplit.SplitRatio = 0.3f;
		outerSplit.SplitterSize = 8;
		outerSplit.MinFirstSize = 100;
		outerSplit.MinSecondSize = 200;
		outerSplit.SplitterColor = Color(60, 60, 70, 255);
		outerSplit.SplitterHoverColor = Color(80, 80, 100, 255);
		outerSplit.SplitterDragColor = Color(100, 100, 140, 255);

		// Left panel
		let leftPanel = new ColorBox(Color(100, 80, 80, 255), "Left Panel");
		outerSplit.AddChild(leftPanel);

		// Right side: nested vertical SplitPanel
		let innerSplit = new SplitPanel();
		innerSplit.Orientation = .Vertical;
		innerSplit.SplitRatio = 0.6f;
		innerSplit.SplitterSize = 8;
		innerSplit.MinFirstSize = 80;
		innerSplit.MinSecondSize = 80;
		innerSplit.SplitterColor = Color(60, 60, 70, 255);
		innerSplit.SplitterHoverColor = Color(80, 80, 100, 255);
		innerSplit.SplitterDragColor = Color(100, 100, 140, 255);

		let topRight = new ColorBox(Color(80, 100, 80, 255), "Top Right");
		innerSplit.AddChild(topRight);

		let bottomRight = new ColorBox(Color(80, 80, 100, 255), "Bottom Right");
		innerSplit.AddChild(bottomRight);

		outerSplit.AddChild(innerSplit);

		return outerSplit;
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
		mDrawContext.DrawText("0:Focus 1:Stack 2:Grid 3:Canvas 4:Dock 5:Wrap 6:Split | T:theme | Tab:focus | F2:debug", cachedFont.Atlas, atlasTexture, .(10, 35 + cachedFont.Font.Metrics.Ascent), Color(180, 180, 180, 255));

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
