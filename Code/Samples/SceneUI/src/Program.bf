namespace SceneUI;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;
using Sedulous.Drawing;
using Sedulous.Fonts;
using Sedulous.Fonts.TTF;
using Sedulous.UI;
using Sedulous.UI.Renderer;
using Sedulous.Engine.Core;
using Sedulous.Engine.UI;
using Sedulous.Shell.SDL3;

// Type aliases to resolve ambiguity - use specific types from each namespace
typealias ShellKeyCode = Sedulous.Shell.Input.KeyCode;
typealias ShellKeyModifiers = Sedulous.Shell.Input.KeyModifiers;
typealias UIKeyCode = Sedulous.UI.KeyCode;
typealias UIKeyModifiers = Sedulous.UI.KeyModifiers;
typealias DrawingTexture = Sedulous.Drawing.ITexture;

/// Clipboard adapter that wraps Shell clipboard for UI use.
class UIClipboardAdapter : Sedulous.UI.IClipboard
{
	private Sedulous.Shell.IClipboard mShellClipboard ~ delete _;

	public this()
	{
		mShellClipboard = new SDL3Clipboard();
	}

	public Result<void> GetText(String outText)
	{
		return mShellClipboard.GetText(outText);
	}

	public Result<void> SetText(StringView text)
	{
		return mShellClipboard.SetText(text);
	}

	public bool HasText => mShellClipboard.HasText;
}

/// Font service that provides access to loaded fonts.
class SceneUIFontService : IFontService
{
	private CachedFont mCachedFont;
	private DrawingTexture mFontTexture;
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

	public CachedFont GetFont(float pixelHeight)
	{
		return mCachedFont;
	}

	public CachedFont GetFont(StringView familyName, float pixelHeight)
	{
		return mCachedFont;
	}

	public DrawingTexture GetAtlasTexture(CachedFont font)
	{
		return mFontTexture;
	}

	public DrawingTexture GetAtlasTexture(StringView familyName, float pixelHeight)
	{
		return mFontTexture;
	}

	public void ReleaseFont(CachedFont font)
	{
	}
}

/// Scene UI sample demonstrating Sedulous.Engine.UI integration.
/// Uses UISceneComponent for screen-space overlay UI.
class SceneUISample : RHISampleApp
{
	// Scene and UI Scene Component
	// Note: These must be cleaned up in OnCleanup() before device destruction
	private ComponentRegistry mComponentRegistry;
	private Scene mScene;
	private UISceneComponent mUIScene;

	// Services for UI
	private UIClipboardAdapter mClipboard /*~ delete _*/;
	private SceneUIFontService mFontService /*~ delete _*/;
	private TooltipService mTooltipService /*~ delete _*/;
	private delegate void(StringView) mTextInputDelegate /*~ delete _*/;

	// Font resources
	private IFont mFont;
	private IFontAtlas mFontAtlas;
	private TextureRef mFontTextureRef ~ delete _;

	// GPU resources for font atlas
	private Sedulous.RHI.ITexture mAtlasTexture;
	private ITextureView mAtlasTextureView;

	// Animation state
	private float mAnimationTime = 0;
	private ProgressBar mAnimatedProgress;
	private TextBlock mFpsLabel;
	private TextBlock mStatusLabel;

	// FPS tracking
	private int mFrameCount = 0;
	private float mFpsTimer = 0;
	private int mCurrentFps = 0;

	// Cursor tracking
	private Sedulous.UI.CursorType mLastUICursor = .Default;

	// Click counter
	private int mClickCount = 0;


	public this() : base(.()
		{
			Title = "Scene UI - Engine.UI Integration Demo",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.08f, 0.1f, 0.12f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!InitializeFont())
			return false;

		if (!CreateAtlasTexture())
			return false;

		if (!InitializeScene())
			return false;

		// Subscribe to text input events
		mTextInputDelegate = new => OnTextInput;
		Shell.InputManager.Keyboard.OnTextInput.Subscribe(mTextInputDelegate);

		Console.WriteLine("Scene UI sample initialized.");
		Console.WriteLine("Demonstrating UISceneComponent for screen-space overlay UI.");
		return true;
	}

	private bool InitializeFont()
	{
		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		if (!File.Exists(fontPath))
		{
			Console.WriteLine(scope $"Font not found: {fontPath}");
			return false;
		}

		TrueTypeFonts.Initialize();

		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 16;

		if (FontLoaderFactory.LoadFont(fontPath, options) case .Ok(let font))
			mFont = font;
		else
		{
			Console.WriteLine("Failed to load font");
			return false;
		}

		if (FontLoaderFactory.CreateAtlas(mFont, options) case .Ok(let atlas))
		{
			mFontAtlas = atlas;
			Console.WriteLine(scope $"Font atlas created: {mFontAtlas.Width}x{mFontAtlas.Height}");
		}
		else
		{
			Console.WriteLine("Failed to create font atlas");
			return false;
		}

		return true;
	}

	private bool CreateAtlasTexture()
	{
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

		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			atlasWidth, atlasHeight, .RGBA8Unorm, .Sampled | .CopyDst
		);

		if (Device.CreateTexture(&textureDesc) not case .Ok(let texture))
		{
			Console.WriteLine("Failed to create atlas texture");
			return false;
		}
		mAtlasTexture = texture;

		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = atlasWidth * 4,
			RowsPerImage = atlasHeight
		};
		Extent3D writeSize = .(atlasWidth, atlasHeight, 1);
		Device.Queue.WriteTexture(mAtlasTexture, Span<uint8>(rgba8Data.Ptr, rgba8Data.Count), &dataLayout, &writeSize);

		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		if (Device.CreateTextureView(mAtlasTexture, &viewDesc) not case .Ok(let view))
		{
			Console.WriteLine("Failed to create atlas texture view");
			return false;
		}
		mAtlasTextureView = view;

		mFontTextureRef = new TextureRef(mAtlasTexture, atlasWidth, atlasHeight);

		return true;
	}

	private bool InitializeScene()
	{
		// Create component registry (required for scene)
		mComponentRegistry = new ComponentRegistry();

		// Create the scene
		mScene = new Scene("SceneUI", mComponentRegistry);

		// Create and attach UISceneComponent
		mUIScene = new UISceneComponent();
		mScene.AddSceneComponent(mUIScene);

		// Initialize rendering for the UI scene component
		if (mUIScene.InitializeRendering(Device, SwapChain.Format, MAX_FRAMES_IN_FLIGHT) case .Err)
		{
			Console.WriteLine("Failed to initialize UI rendering");
			return false;
		}

		// Set atlas texture for fonts
		mUIScene.SetAtlasTexture(mAtlasTextureView);

		// Set white pixel UV for solid color rendering
		let (u, v) = mFontAtlas.WhitePixelUV;
		mUIScene.SetWhitePixelUV(.(u, v));

		// Set initial viewport size
		mUIScene.SetViewportSize(SwapChain.Width, SwapChain.Height);

		// Get UIContext and configure services
		let uiContext = mUIScene.UIContext;

		// Register clipboard
		mClipboard = new UIClipboardAdapter();
		uiContext.RegisterClipboard(mClipboard);

		// Register font service
		mFontService = new SceneUIFontService(mFont, mFontAtlas, mFontTextureRef);
		uiContext.RegisterService<IFontService>(mFontService);

		// Register theme
		let theme = new DarkTheme();
		uiContext.RegisterService<ITheme>(theme);

		// Register tooltip service
		mTooltipService = new TooltipService();
		uiContext.RegisterService<ITooltipService>(mTooltipService);

		// Build UI
		BuildUI();

		// Activate the scene so Update() runs
		mScene.SetState(.Active);

		return true;
	}

	private void OnTextInput(StringView text)
	{
		for (let c in text.DecodedChars)
		{
			mUIScene.OnTextInput(c);
		}
	}

	private void BuildUI()
	{
		// Create root layout - a DockPanel
		let root = new DockPanel();
		root.Background = Color(25, 28, 32, 240);

		// === Header ===
		let header = new Border();
		header.Background = Color(45, 50, 60);
		header.Padding = Thickness(15, 10, 15, 10);
		root.SetDock(header, .Top);

		let headerContent = new StackPanel();
		headerContent.Orientation = .Horizontal;
		headerContent.Spacing = 20;
		header.Child = headerContent;  // Must use Child property, not AddChild!

		let title = new TextBlock();
		title.Text = "Sedulous.Engine.UI Demo";
		title.Foreground = Color(220, 225, 230);
		title.VerticalAlignment = .Center;
		headerContent.AddChild(title);

		// FPS counter in header
		mFpsLabel = new TextBlock();
		mFpsLabel.Text = "FPS: --";
		mFpsLabel.Foreground = Color(150, 200, 150);
		mFpsLabel.VerticalAlignment = .Center;
		mFpsLabel.HorizontalAlignment = .Right;
		headerContent.AddChild(mFpsLabel);

		root.AddChild(header);

		// === Footer / Status Bar ===
		let footer = new Border();
		footer.Background = Color(35, 40, 48);
		footer.Padding = Thickness(15, 8, 15, 8);
		root.SetDock(footer, .Bottom);

		mStatusLabel = new TextBlock();
		mStatusLabel.Text = "Using UISceneComponent for screen-space overlay UI";
		mStatusLabel.Foreground = Color(140, 145, 150);
		footer.Child = mStatusLabel;  // Must use Child property, not AddChild!

		root.AddChild(footer);

		// === Main Content ===
		let mainContent = new ScrollViewer();
		mainContent.Padding = Thickness(20);

		let content = new StackPanel();
		content.Orientation = .Vertical;
		content.Spacing = 25;
		mainContent.Content = content;  // Must use Content property, not AddChild!

		// Section: Introduction
		AddSection(content, "UISceneComponent Integration", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "This sample demonstrates integrating Sedulous.UI into the engine\nvia UISceneComponent. The UI is rendered as a screen-space overlay.";
			desc.Foreground = Color(180, 185, 190);
			panel.AddChild(desc);
		});

		// Section: Buttons
		AddSection(content, "Interactive Controls", scope (panel) => {
			let hstack = new StackPanel();
			hstack.Orientation = .Horizontal;
			hstack.Spacing = 10;

			let clickBtn = new Button();
			clickBtn.ContentText = "Click Me!";
			clickBtn.Padding = Thickness(20, 10, 20, 10);
			clickBtn.Click.Subscribe(new (sender) => {
				mClickCount++;
				mStatusLabel.Text = scope:: $"Button clicked {mClickCount} time(s)";
			});
			mTooltipService.SetTooltip(clickBtn, "Click to increment the counter");
			hstack.AddChild(clickBtn);

			let resetBtn = new Button();
			resetBtn.ContentText = "Reset";
			resetBtn.Padding = Thickness(15, 10, 15, 10);
			resetBtn.Click.Subscribe(new (sender) => {
				mClickCount = 0;
				mStatusLabel.Text = "Counter reset";
			});
			hstack.AddChild(resetBtn);

			let disabledBtn = new Button();
			disabledBtn.ContentText = "Disabled";
			disabledBtn.Padding = Thickness(15, 10, 15, 10);
			disabledBtn.IsEnabled = false;
			hstack.AddChild(disabledBtn);

			panel.AddChild(hstack);
		});

		// Section: Text Input
		AddSection(content, "Text Input", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Type in the text box below:";
			desc.Foreground = Color(150, 155, 160);
			panel.AddChild(desc);

			let textBox = new TextBox();
			textBox.Width = 350;
			textBox.Placeholder = "Enter text here...";
			panel.AddChild(textBox);
		});

		// Section: Checkboxes and Radio Buttons
		AddSection(content, "Selection Controls", scope (panel) => {
			let columns = new StackPanel();
			columns.Orientation = .Horizontal;
			columns.Spacing = 60;

			// Checkboxes column
			let cbColumn = new StackPanel();
			cbColumn.Spacing = 8;

			let cbLabel = new TextBlock();
			cbLabel.Text = "Checkboxes:";
			cbLabel.Foreground = Color(150, 155, 160);
			cbColumn.AddChild(cbLabel);

			let cb1 = new CheckBox();
			cb1.ContentText = "Enable feature A";
			cb1.IsChecked = true;
			cbColumn.AddChild(cb1);

			let cb2 = new CheckBox();
			cb2.ContentText = "Enable feature B";
			cbColumn.AddChild(cb2);

			let cb3 = new CheckBox();
			cb3.ContentText = "Enable feature C";
			cbColumn.AddChild(cb3);

			columns.AddChild(cbColumn);

			// Radio buttons column
			let rbColumn = new StackPanel();
			rbColumn.Spacing = 8;

			let rbLabel = new TextBlock();
			rbLabel.Text = "Radio Buttons:";
			rbLabel.Foreground = Color(150, 155, 160);
			rbColumn.AddChild(rbLabel);

			let rb1 = new RadioButton("Option 1", "options");
			rb1.IsChecked = true;
			rbColumn.AddChild(rb1);

			let rb2 = new RadioButton("Option 2", "options");
			rbColumn.AddChild(rb2);

			let rb3 = new RadioButton("Option 3", "options");
			rbColumn.AddChild(rb3);

			columns.AddChild(rbColumn);
			panel.AddChild(columns);
		});

		// Section: Progress and Slider
		AddSection(content, "Progress & Slider", scope (panel) => {
			let progressLabel = new TextBlock();
			progressLabel.Text = "Animated Progress:";
			progressLabel.Foreground = Color(150, 155, 160);
			panel.AddChild(progressLabel);

			mAnimatedProgress = new ProgressBar();
			mAnimatedProgress.Width = 350;
			mAnimatedProgress.Height = 20;
			mAnimatedProgress.Value = 0.0f;
			panel.AddChild(mAnimatedProgress);

			let sliderLabel = new TextBlock();
			sliderLabel.Text = "Slider Control:";
			sliderLabel.Foreground = Color(150, 155, 160);
			sliderLabel.Margin = Thickness(0, 15, 0, 0);
			panel.AddChild(sliderLabel);

			let slider = new Slider();
			slider.Width = 350;
			slider.Value = 0.5f;
			panel.AddChild(slider);
		});

		// Section: ListBox
		AddSection(content, "ListBox", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Select an item:";
			desc.Foreground = Color(150, 155, 160);
			panel.AddChild(desc);

			let listBox = new ListBox();
			listBox.Width = 350;
			listBox.Height = 120;
			listBox.AddItem("First Item");
			listBox.AddItem("Second Item");
			listBox.AddItem("Third Item");
			listBox.AddItem("Fourth Item");
			listBox.AddItem("Fifth Item");
			listBox.SelectedIndex = 0;
			listBox.SelectionChanged.Subscribe(new (lb, oldIdx, newIdx) => {
				mStatusLabel.Text = scope:: $"Selected item index: {newIdx}";
			});
			panel.AddChild(listBox);
		});

		// Section: ComboBox
		AddSection(content, "ComboBox", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Dropdown selection:";
			desc.Foreground = Color(150, 155, 160);
			panel.AddChild(desc);

			let combo = new ComboBox();
			combo.Width = 200;
			combo.PlaceholderText = "Select...";
			combo.AddItem("Apple");
			combo.AddItem("Banana");
			combo.AddItem("Cherry");
			combo.AddItem("Date");
			combo.SelectionChanged.Subscribe(new (cb, oldIdx, newIdx) => {
				mStatusLabel.Text = scope:: $"ComboBox: {cb.SelectedItem}";
			});
			panel.AddChild(combo);
		});

		root.AddChild(mainContent);

		// Set root element via UISceneComponent
		mUIScene.RootElement = root;
	}

	private void AddSection(StackPanel parent, StringView title, delegate void(StackPanel panel) buildContent)
	{
		let section = new StackPanel();
		section.Spacing = 10;

		let header = new TextBlock();
		header.Text = title;
		header.Foreground = Color(100, 180, 255);
		section.AddChild(header);

		let contentPanel = new StackPanel();
		contentPanel.Spacing = 8;
		contentPanel.Margin = Thickness(15, 0, 0, 0);
		buildContent(contentPanel);
		section.AddChild(contentPanel);

		parent.AddChild(section);
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		mUIScene?.SetViewportSize(width, height);
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mAnimationTime = totalTime;

		// FPS calculation
		mFrameCount++;
		mFpsTimer += deltaTime;
		if (mFpsTimer >= 1.0f)
		{
			mCurrentFps = mFrameCount;
			mFrameCount = 0;
			mFpsTimer -= 1.0f;

			// Update FPS label
			if (mFpsLabel != null)
				mFpsLabel.Text = scope:: $"FPS: {mCurrentFps}";
		}

		// Animate progress bar
		if (mAnimatedProgress != null)
		{
			float progress = (Math.Sin(totalTime * 0.5f) + 1.0f) * 0.5f;
			mAnimatedProgress.Value = progress;
		}

		// Route input to UI scene component
		RouteInput();

		// Update the scene (which updates UISceneComponent)
		mScene.Update(deltaTime);

		// Update tooltip system
		mTooltipService?.Update(mUIScene.UIContext, deltaTime);
	}

	private void RouteInput()
	{
		let input = Shell.InputManager;

		// Get keyboard modifiers
		let mods = GetModifiers(input.Keyboard);

		// Mouse position
		mUIScene.OnMouseMove(input.Mouse.X, input.Mouse.Y, mods);

		// Update cursor
		UpdateCursor(input.Mouse);

		// Mouse buttons
		if (input.Mouse.IsButtonPressed(.Left))
			mUIScene.OnMouseDown(.Left, input.Mouse.X, input.Mouse.Y, mods);
		if (input.Mouse.IsButtonReleased(.Left))
			mUIScene.OnMouseUp(.Left, input.Mouse.X, input.Mouse.Y, mods);

		if (input.Mouse.IsButtonPressed(.Right))
			mUIScene.OnMouseDown(.Right, input.Mouse.X, input.Mouse.Y, mods);
		if (input.Mouse.IsButtonReleased(.Right))
			mUIScene.OnMouseUp(.Right, input.Mouse.X, input.Mouse.Y, mods);

		// Mouse wheel
		if (input.Mouse.ScrollY != 0)
			mUIScene.OnMouseWheel(input.Mouse.ScrollX, input.Mouse.ScrollY, mods);

		// Keyboard
		for (int key = 0; key < (int)ShellKeyCode.Count; key++)
		{
			let shellKey = (ShellKeyCode)key;
			if (input.Keyboard.IsKeyPressed(shellKey))
				mUIScene.OnKeyDown(MapKey(shellKey), 0, mods);
			if (input.Keyboard.IsKeyReleased(shellKey))
				mUIScene.OnKeyUp(MapKey(shellKey), 0, mods);
		}
	}

	private void UpdateCursor(Sedulous.Shell.Input.IMouse mouse)
	{
		let uiCursor = mUIScene.UIContext.CurrentCursor;
		if (uiCursor != mLastUICursor)
		{
			mLastUICursor = uiCursor;
			mouse.Cursor = MapCursor(uiCursor);
		}
	}

	private static Sedulous.Shell.Input.CursorType MapCursor(Sedulous.UI.CursorType uiCursor)
	{
		switch (uiCursor)
		{
		case .Default:    return .Default;
		case .Text:       return .Text;
		case .Wait:       return .Wait;
		case .Crosshair:  return .Crosshair;
		case .Progress:   return .Progress;
		case .Move:       return .Move;
		case .NotAllowed: return .NotAllowed;
		case .Pointer:    return .Pointer;
		case .ResizeEW:   return .ResizeEW;
		case .ResizeNS:   return .ResizeNS;
		case .ResizeNWSE: return .ResizeNWSE;
		case .ResizeNESW: return .ResizeNESW;
		}
	}

	private UIKeyModifiers GetModifiers(Sedulous.Shell.Input.IKeyboard keyboard)
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

	private static UIKeyCode MapKey(ShellKeyCode shellKey)
	{
		switch (shellKey)
		{
		case .A: return .A;
		case .B: return .B;
		case .C: return .C;
		case .D: return .D;
		case .E: return .E;
		case .F: return .F;
		case .G: return .G;
		case .H: return .H;
		case .I: return .I;
		case .J: return .J;
		case .K: return .K;
		case .L: return .L;
		case .M: return .M;
		case .N: return .N;
		case .O: return .O;
		case .P: return .P;
		case .Q: return .Q;
		case .R: return .R;
		case .S: return .S;
		case .T: return .T;
		case .U: return .U;
		case .V: return .V;
		case .W: return .W;
		case .X: return .X;
		case .Y: return .Y;
		case .Z: return .Z;
		case .Num0: return .Num0;
		case .Num1: return .Num1;
		case .Num2: return .Num2;
		case .Num3: return .Num3;
		case .Num4: return .Num4;
		case .Num5: return .Num5;
		case .Num6: return .Num6;
		case .Num7: return .Num7;
		case .Num8: return .Num8;
		case .Num9: return .Num9;
		case .Return: return .Return;
		case .Escape: return .Escape;
		case .Backspace: return .Backspace;
		case .Tab: return .Tab;
		case .Space: return .Space;
		case .Left: return .Left;
		case .Right: return .Right;
		case .Up: return .Up;
		case .Down: return .Down;
		case .Home: return .Home;
		case .End: return .End;
		case .PageUp: return .PageUp;
		case .PageDown: return .PageDown;
		case .Delete: return .Delete;
		case .Insert: return .Insert;
		default: return .Unknown;
		}
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		// Prepare UI geometry for GPU
		mUIScene.PrepareGPU(frameIndex);
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		let textureView = SwapChain.CurrentTextureView;

		// Create render pass for UI
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = textureView,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = mConfig.ClearColor
		});

		RenderPassDescriptor passDesc = .(colorAttachments);

		let renderPass = encoder.BeginRenderPass(&passDesc);
		if (renderPass == null)
			return false;

		defer { renderPass.End(); delete renderPass; }

		// Render UI overlay
		mUIScene.Render(renderPass, SwapChain.Width, SwapChain.Height, frameIndex);

		return true;
	}

	protected override void OnCleanup()
	{
		Console.WriteLine("SceneUISample.OnCleanup() called");

		// Unsubscribe from text input events
		if (mTextInputDelegate != null)
		{
			Shell.InputManager.Keyboard.OnTextInput.Unsubscribe(mTextInputDelegate, false);
			delete mTextInputDelegate;
			mTextInputDelegate = null;
		}

		// Clean up services (registered with UIContext, but owned by us)
		// Must delete before Scene since UIContext is owned by UISceneComponent
		if (mUIScene?.UIContext != null)
		{
			if (mUIScene.UIContext.GetService<ITheme>() case .Ok(let theme))
				delete theme;
		}
		if (mFontService != null) { delete mFontService; mFontService = null; }
		if (mTooltipService != null) { delete mTooltipService; mTooltipService = null; }
		if (mClipboard != null) { delete mClipboard; mClipboard = null; }

		// Must clean up Scene before device destruction (UISceneComponent has GPU resources)
		if (mScene != null)
		{
			Console.WriteLine("  Deleting mScene");
			delete mScene;
			mScene = null;
		}
		if (mComponentRegistry != null)
		{
			delete mComponentRegistry;
			mComponentRegistry = null;
		}

		// Now clean up GPU resources
		if (mAtlasTextureView != null) { delete mAtlasTextureView; mAtlasTextureView = null; }
		if (mAtlasTexture != null) { delete mAtlasTexture; mAtlasTexture = null; }

		Console.WriteLine("Scene UI sample cleaned up.");
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let sample = scope SceneUISample();
		return sample.Run();
	}
}
