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
	case DisplayControls; // Phase 5: Display controls
}

/// GUI Sandbox sample demonstrating the Sedulous.GUI framework.
/// Phase 3: Theming, Phase 4: Layout Panels, Phase 5: Display Controls
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

	public this() : base(.()
		{
			Title = "GUI Sandbox - Phase 3, 4 & 5",
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

		Console.WriteLine("GUISandbox Phase 3, 4 & 5 initialized.");
		Console.WriteLine("  0: Focus & Theme demo (Phase 3)");
		Console.WriteLine("  1-6: Layout demos (Phase 4)");
		Console.WriteLine("    1: StackPanel  2: Grid  3: Canvas");
		Console.WriteLine("    4: DockPanel   5: WrapPanel  6: SplitPanel");
		Console.WriteLine("  7: Display Controls (Phase 5)");
		Console.WriteLine("  T: Toggle theme | Tab: Navigate focus | F2: Debug");
		Console.WriteLine("  Ctrl +/-: Adjust UI scale");
		Console.WriteLine("  ESC: Exit");
		return true;
	}

	private void CreateDemoImages()
	{
		// Create a checkerboard pattern image (64x64)
		//let checkerboard = Sedulous.Imaging.Image.CreateCheckerboard(64, Color(200, 100, 100, 255), Color(100, 100, 200, 255), 16, .RGBA8);
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
		case .DisplayControls:
			mDemoRoot = CreateDisplayControlsDemo();
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

	// === Phase 5: Display Controls Demo ===

	private Panel CreateDisplayControlsDemo()
	{
		// Main container with vertical stack
		let container = new StackPanel();
		container.Orientation = .Vertical;
		container.Spacing = 20;
		container.Margin = .(50, 80, 50, 50);
		container.HorizontalAlignment = .Left;
		container.VerticalAlignment = .Top;

		// --- TextBlock Section ---
		let textSection = new StackPanel();
		textSection.Orientation = .Vertical;
		textSection.Spacing = 8;

		let textHeader = new TextBlock("TextBlock Examples:");
		textHeader.FontSize = 18;
		textSection.AddChild(textHeader);

		// Left-aligned text
		let textLeft = new TextBlock("Left-aligned text (default)");
		textSection.AddChild(textLeft);

		// Center-aligned text
		let textCenter = new TextBlock("Center-aligned text");
		textCenter.TextAlignment = .Center;
		textCenter.Width = 300;
		textCenter.Background = Color(40, 40, 50, 128);
		textSection.AddChild(textCenter);

		// Right-aligned text
		let textRight = new TextBlock("Right-aligned text");
		textRight.TextAlignment = .Right;
		textRight.Width = 300;
		textRight.Background = Color(40, 40, 50, 128);
		textSection.AddChild(textRight);

		// Wrapped text - uses ShapeTextWrapped for proper word-aware wrapping
		let textWrapped = new TextBlock("This is a longer text that wraps at word boundaries. The TextWrapping property enables word-aware line breaking using the text shaper.");
		textWrapped.TextWrapping = .Wrap;
		textWrapped.Width = 280;
		textWrapped.Background = Color(50, 40, 40, 128);
		textSection.AddChild(textWrapped);

		container.AddChild(textSection);

		// --- Separator ---
		let sep1 = new Separator(.Horizontal);
		sep1.Width = 600;
		container.AddChild(sep1);

		// --- Label Section ---
		let labelSection = new StackPanel();
		labelSection.Orientation = .Horizontal;
		labelSection.Spacing = 20;

		// Label with target
		let targetControl = new FocusableRect();
		targetControl.Width = 100;
		targetControl.Height = 60;
		targetControl.RectColor = Color(80, 120, 180, 255);

		let label = new Label("Click me to focus target:");
		label.Target = targetControl;

		labelSection.AddChild(label);
		labelSection.AddChild(targetControl);
		container.AddChild(labelSection);

		// --- Separator ---
		let sep2 = new Separator(.Horizontal);
		sep2.Width = 600;
		container.AddChild(sep2);

		// --- Border Section ---
		let borderSection = new StackPanel();
		borderSection.Orientation = .Horizontal;
		borderSection.Spacing = 20;

		// Simple border
		let border1 = new Border();
		border1.BorderThickness = .(2);
		border1.BorderBrush = Color(100, 150, 200, 255);
		border1.CornerRadius = 0;
		let borderContent1 = new TextBlock("Simple Border");
		border1.Child = borderContent1;
		borderSection.AddChild(border1);

		// Rounded border with background (both background and stroke are rounded)
		let border2 = new Border();
		border2.BorderThickness = .(3);
		border2.BorderBrush = Color(200, 100, 100, 255);
		border2.Background = Color(60, 40, 40, 255);
		border2.CornerRadius = 10;
		border2.Padding = .(10);
		let borderContent2 = new TextBlock("Rounded Border");
		border2.Child = borderContent2;
		borderSection.AddChild(border2);

		// Non-uniform border (thick top/bottom, thin left/right)
		let border3 = new Border();
		border3.BorderThickness = .(2, 10, 2, 10); // Left, Top, Right, Bottom
		border3.BorderBrush = Color(100, 200, 100, 255);
		border3.Padding = .(8);
		let borderContent3 = new TextBlock("Thick T/B");
		border3.Child = borderContent3;
		borderSection.AddChild(border3);

		container.AddChild(borderSection);

		// --- Separator ---
		let sep3 = new Separator(.Horizontal);
		sep3.Width = 600;
		container.AddChild(sep3);

		// --- ProgressBar Section ---
		let progressSection = new StackPanel();
		progressSection.Orientation = .Vertical;
		progressSection.Spacing = 10;

		let progressHeader = new TextBlock("ProgressBar Examples:");
		progressHeader.FontSize = 18;
		progressSection.AddChild(progressHeader);

		// Determinate progress bar at 30%
		let progress1 = new ProgressBar();
		progress1.Width = 300;
		progress1.Height = 16;
		progress1.Value = 30;
		progress1.CornerRadius = 4;
		progressSection.AddChild(progress1);

		// Determinate progress bar at 75%
		let progress2 = new ProgressBar();
		progress2.Width = 300;
		progress2.Height = 16;
		progress2.Value = 75;
		progress2.FillColor = Color(100, 200, 100, 255);
		progress2.CornerRadius = 4;
		progressSection.AddChild(progress2);

		// Indeterminate progress bar (animated)
		let progressIndeterminate = new ProgressBar();
		progressIndeterminate.Width = 300;
		progressIndeterminate.Height = 16;
		progressIndeterminate.IsIndeterminate = true;
		progressIndeterminate.FillColor = Color(200, 150, 50, 255);
		progressIndeterminate.CornerRadius = 4;
		progressSection.AddChild(progressIndeterminate);

		// Vertical progress bar
		let verticalProgressStack = new StackPanel();
		verticalProgressStack.Orientation = .Horizontal;
		verticalProgressStack.Spacing = 10;

		let vertLabel = new TextBlock("Vertical:");
		verticalProgressStack.AddChild(vertLabel);

		let progressVert = new ProgressBar();
		progressVert.Orientation = .Vertical;
		progressVert.Width = 16;
		progressVert.Height = 80;
		progressVert.Value = 60;
		progressVert.CornerRadius = 4;
		verticalProgressStack.AddChild(progressVert);

		progressSection.AddChild(verticalProgressStack);

		container.AddChild(progressSection);

		// --- Separator ---
		let sep4 = new Separator(.Horizontal);
		sep4.Width = 600;
		container.AddChild(sep4);

		// --- Image Section ---
		let imageSection = new StackPanel();
		imageSection.Orientation = .Vertical;
		imageSection.Spacing = 10;

		let imageHeader = new TextBlock("Image Examples (Stretch Modes):");
		imageHeader.FontSize = 18;
		imageSection.AddChild(imageHeader);

		let imageRow = new StackPanel();
		imageRow.Orientation = .Horizontal;
		imageRow.Spacing = 20;

		// Image with Uniform stretch (default) - shown in 100x100 box
		let imageBorder1 = new Border();
		imageBorder1.BorderThickness = .(1);
		imageBorder1.BorderBrush = Color(100, 100, 100, 255);
		imageBorder1.Width = 100;
		imageBorder1.Height = 100;
		let image1 = new Sedulous.GUI.Image(mDemoCheckerboard);
		image1.Stretch = .Uniform;
		imageBorder1.Child = image1;
		imageRow.AddChild(imageBorder1);

		// Image with Fill stretch - stretches to fill
		let imageBorder2 = new Border();
		imageBorder2.BorderThickness = .(1);
		imageBorder2.BorderBrush = Color(100, 100, 100, 255);
		imageBorder2.Width = 100;
		imageBorder2.Height = 100;
		let image2 = new Sedulous.GUI.Image(mDemoGradient);
		image2.Stretch = .Fill;
		imageBorder2.Child = image2;
		imageRow.AddChild(imageBorder2);

		// Image with None stretch - original size, centered
		let imageBorder3 = new Border();
		imageBorder3.BorderThickness = .(1);
		imageBorder3.BorderBrush = Color(100, 100, 100, 255);
		imageBorder3.Width = 100;
		imageBorder3.Height = 100;
		let image3 = new Sedulous.GUI.Image(mDemoCheckerboard);
		image3.Stretch = .None;
		imageBorder3.Child = image3;
		imageRow.AddChild(imageBorder3);

		// Image with UniformToFill stretch - fills while preserving aspect
		let imageBorder4 = new Border();
		imageBorder4.BorderThickness = .(1);
		imageBorder4.BorderBrush = Color(100, 100, 100, 255);
		imageBorder4.Width = 100;
		imageBorder4.Height = 100;
		let image4 = new Sedulous.GUI.Image(mDemoGradient);
		image4.Stretch = .UniformToFill;
		imageBorder4.Child = image4;
		imageRow.AddChild(imageBorder4);

		imageSection.AddChild(imageRow);

		// Labels for stretch modes
		let stretchLabels = new StackPanel();
		stretchLabels.Orientation = .Horizontal;
		stretchLabels.Spacing = 20;

		let stretchLabel1 = new TextBlock("Uniform");
		stretchLabel1.Width = 100;
		stretchLabel1.TextAlignment = .Center;
		stretchLabels.AddChild(stretchLabel1);

		let stretchLabel2 = new TextBlock("Fill");
		stretchLabel2.Width = 100;
		stretchLabel2.TextAlignment = .Center;
		stretchLabels.AddChild(stretchLabel2);

		let stretchLabel3 = new TextBlock("None");
		stretchLabel3.Width = 100;
		stretchLabel3.TextAlignment = .Center;
		stretchLabels.AddChild(stretchLabel3);

		let stretchLabel4 = new TextBlock("UniformToFill");
		stretchLabel4.Width = 100;
		stretchLabel4.TextAlignment = .Center;
		stretchLabels.AddChild(stretchLabel4);

		imageSection.AddChild(stretchLabels);

		container.AddChild(imageSection);

		// --- Scale Info ---
		let sep5 = new Separator(.Horizontal);
		sep5.Width = 600;
		container.AddChild(sep5);

		let scaleInfo = new TextBlock("Use Ctrl +/- to adjust UI scale factor");
		scaleInfo.FontSize = 12;
		container.AddChild(scaleInfo);

		return container;
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
		mDrawContext.DrawText("0:Focus 1-6:Layout 7:Display | T:theme Tab:focus F2:debug Ctrl+/-:scale", cachedFont.Atlas, atlasTexture, .(10, 35 + cachedFont.Font.Metrics.Ascent), Color(180, 180, 180, 255));

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
