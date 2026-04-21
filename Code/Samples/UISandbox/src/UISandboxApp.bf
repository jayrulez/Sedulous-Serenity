namespace UISandbox;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Runtime.Client;
using Sedulous.Runtime;
using Sedulous.Drawing;
using Sedulous.Fonts;
using Sedulous.Imaging;
using Sedulous.UI;
using Sedulous.UI.Toolkit;
using Sedulous.UI.Shell;
using Sedulous.Drawing.Renderer;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.Shell.SDL3;
using Sedulous.Shaders;
using SDL3;
using Sedulous.ImageData;
using Sedulous.Fonts.TTF;

/// Per-secondary-window rendering data (stored in SecondaryWindowContext.UserData).
class SecondaryWindowRenderData
{
	public DrawContext DrawContext;
	public DrawingRenderer DrawingRenderer;
	public RootView RootView;
	public View FloatingView;
	public delegate void(View) OnViewCloseRequested ~ delete _;

	public void Dispose(IDevice device)
	{
		if (DrawContext != null)
		{
			delete DrawContext;
			DrawContext = null;
		}

		if (DrawingRenderer != null)
		{
			DrawingRenderer.Dispose();
			delete DrawingRenderer;
			DrawingRenderer = null;
		}
	}
}

/// UISandbox sample demonstrating the Sedulous.UI framework via Runtime.Client.
/// Implements IFloatingWindowHost for multi-window docking via RHI.
class UISandboxApp : Application, IFloatingWindowHost
{
	private FrameLayout mRoot;

	// Owned image data for ImageView demos
	private OwnedImageData mCheckerImage ~ delete _;
	private OwnedImageData mGradientImage ~ delete _;

	// TurboBadger skin images (Public Domain)
	private OwnedImageData mTBButton ~ delete _;
	private OwnedImageData mTBButtonPressed ~ delete _;
	private OwnedImageData mTBButtonFlatOutline ~ delete _;
	private OwnedImageData mTBCheckbox ~ delete _;
	private OwnedImageData mTBCheckboxMark ~ delete _;
	private OwnedImageData mTBCheckboxPressed ~ delete _;
	private OwnedImageData mTBRadio ~ delete _;
	private OwnedImageData mTBRadioMark ~ delete _;
	private OwnedImageData mTBRadioPressed ~ delete _;
	private OwnedImageData mTBSliderBgX ~ delete _;
	private OwnedImageData mTBSliderHandle ~ delete _;
	private OwnedImageData mTBContainer ~ delete _;
	private OwnedImageData mTBSeparatorX ~ delete _;
	private OwnedImageData mTBSelection ~ delete _;
	private OwnedImageData mTBEditField ~ delete _;
	private OwnedImageData mTBScrollBgX ~ delete _;
	private OwnedImageData mTBScrollBgY ~ delete _;
	private OwnedImageData mTBScrollFgX ~ delete _;
	private OwnedImageData mTBScrollFgY ~ delete _;
	private OwnedImageData mTBFocusR4 ~ delete _;
	private OwnedImageData mTBArrowDown ~ delete _;
	private OwnedImageData mTBArrowRight ~ delete _;
	private OwnedImageData mTBWindow ~ delete _;
	private OwnedImageData mTBWindowActive ~ delete _;
	private OwnedImageData mTBItemHover ~ delete _;
	private OwnedImageData mTBItemSelected ~ delete _;
	private OwnedImageData mTBArrowUp ~ delete _;
	private OwnedImageData mTBTabTopActive ~ delete _;
	private OwnedImageData mTBTabTopInactive ~ delete _;
	private OwnedImageData mTBTabBottomActive ~ delete _;
	private OwnedImageData mTBTabBottomInactive ~ delete _;
	private OwnedImageData mTBTabLeftActive ~ delete _;
	private OwnedImageData mTBTabLeftInactive ~ delete _;
	private OwnedImageData mTBTabRightActive ~ delete _;
	private OwnedImageData mTBTabRightInactive ~ delete _;

	// Adapters (owned by us, not by ListView/TreeView)
	private DemoListAdapter mListAdapter ~ delete _;
	private DemoTreeAdapter mTreeAdapter ~ delete _;
	private ReorderableListAdapter mReorderAdapter ~ delete _;

	// Controls we need to update per-frame or reference from callbacks
	private ProgressBar mProgressBar;
	private Label mSliderValueLabel;
	private Label mProgressLabel;
	private Label mClickLabel;
	private Label mEditMirrorLabel;
	private Label mConfirmResultLabel;
	private Label mComboLabel;
	private Label mNumberLabel;
	private TabView mTabView;

	// ICommand demo state
	private RelayCommand mDemoCommand ~ delete _;
	private Label mDemoCommandLabel;
	private bool mCommandEnabled;

	// UI system
	private UIContext mUIContext;
	private RootView mMainRoot;

	// Font service
	private FontService mFontService ~ delete _;

	// Drawing
	private DrawContext mDrawContext ~ delete _;
	private DrawingRenderer mDrawingRenderer;
	private ShaderSystem mShaderSystem;

	// Input
	private ShellClipboardAdapter mClipboard ~ delete _;
	private UIInputHelper mInputHelper = new .() ~ delete _;
	private float mFrameDelta = 0;
	private Sedulous.UI.CursorType mLastCursor = .Default;

	// Multi-window: map from floating View to its SecondaryWindowContext
	private Dictionary<View, SecondaryWindowContext> mFloatingWindowMap = new .() ~ delete _;

	// Cross-window drag tracking
	private SDL_Window* mDragSourceSDLWindow;
	private float mDragWindowOffsetX;
	private float mDragWindowOffsetY;

	public this() : base()
	{
	}

	//==========================================================================
	// Lifecycle
	//==========================================================================

	protected override void OnInitialize(Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		// Initialize fonts
		mFontService = new FontService();

		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		float[?] sizes = .(11, 12, 14, 16, 20, 24, 32);
		for (let size in sizes)
		{
			FontLoadOptions options = .ExtendedLatin;
			options.PixelHeight = size;
			if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
			{
				Console.WriteLine(scope $"Failed to load font at size {size}: {fontPath}");
				return;
			}
		}

		// Initialize shader system
		mShaderSystem = new ShaderSystem();
		String shaderPath = scope .();
		GetAssetPath("Render/shaders", shaderPath);
		if (mShaderSystem.Initialize(Device, scope StringView[](shaderPath)) case .Err)
		{
			Console.WriteLine("Failed to initialize shader system");
			return;
		}

		// Create draw context
		mDrawContext = new DrawContext(mFontService);

		// Initialize drawing renderer
		mDrawingRenderer = new DrawingRenderer();
		if (mDrawingRenderer.Initialize(Device, SwapChain.Format, (int32)SwapChain.BufferCount, mShaderSystem) case .Err)
		{
			Console.WriteLine("Failed to initialize drawing renderer");
			return;
		}

		// Initialize clipboard
		mClipboard = new ShellClipboardAdapter(mShell.Clipboard);

		// Generate test images and load assets
		GenerateTestImages();
		LoadTBAssets();

		// Initialize UI
		InitializeUI();

		Console.WriteLine("Sedulous.UI Sandbox initialized.");
		Console.WriteLine("  T=toggle theme, Tab=navigate, F2=debug | ESC: Exit");
	}

	private void InitializeUI()
	{
		// Register toolkit theme extension before UIContext creates its default theme
		Theme.RegisterExtension(new ToolkitThemeExtension());

		mUIContext = new UIContext(mFontService, mClipboard);

		mMainRoot = new RootView();
		mRoot = new FrameLayout();
		mRoot.Padding = .(20);
		mRoot.ClipToBounds = true;
		mMainRoot.AddView(mRoot);
		mUIContext.AddRootView(mMainRoot);

		BuildDemo();
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		// Toggle debug
		if (keyboard.IsKeyPressed(.F2) && mUIContext != null)
			mUIContext.DebugDraw = !mUIContext.DebugDraw;

		// Theme toggle
		if (keyboard.IsKeyPressed(.T) && mUIContext != null)
			CycleTheme();

		// Escape - let UI handle it first (closes popups/dialogs), then exit
		if (keyboard.IsKeyPressed(.Escape))
		{
			if (mUIContext == null || !mUIContext.ProcessKeyDown(.Escape, .None))
				Exit();
		}

		// Route UI input (with multi-window awareness)
		ProcessUIInput();

		// Update cursor
		UpdateCursor(mouse);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mFrameDelta = frame.DeltaTime;

		// Animate progress bar
		if (mProgressBar != null && mUIContext != null)
		{
			float progress = (Math.Sin(mUIContext.TotalTime * 0.8f) + 1.0f) * 0.5f;
			mProgressBar.Progress = progress;

			if (mProgressLabel != null)
			{
				let str = scope String();
				((int)(progress * 100)).ToString(str);
				str.Append("%");
				mProgressLabel.Text = str;
			}
		}

		// Update UI
		if (mUIContext != null)
		{
			mMainRoot.SetSize((float)Window.Width, (float)Window.Height);
			mUIContext.BeginFrame(frame.DeltaTime);
			mUIContext.UpdateRootView(mMainRoot, frame.DeltaTime);

			// Update secondary window root views
			for (let ctx in mSecondaryWindows)
			{
				if (ctx.UserData == null) continue;
				let data = ctx.UserData as SecondaryWindowRenderData;
				if (data?.RootView != null)
				{
					data.RootView.SetSize((float)ctx.Window.Width, (float)ctx.Window.Height);
					mUIContext.UpdateRootView(data.RootView, frame.DeltaTime);
				}
			}
		}
	}

	protected override void OnPrepareFrame(FrameContext frame)
	{
		if (mDrawContext == null || mDrawingRenderer == null)
			return;

		BuildDrawCommands();
		mDrawingRenderer.UpdateProjection(SwapChain.Width, SwapChain.Height, frame.FrameIndex);
		mDrawingRenderer.Prepare(mDrawContext.GetBatch(), frame.FrameIndex);
	}

	private void BuildDrawCommands()
	{
		mDrawContext.Clear();

		if (mUIContext != null)
			mUIContext.DrawRootView(mMainRoot, mDrawContext);

		// Status bar text
		if (mUIContext != null)
		{
			let themeName = mUIContext.Theme?.Name ?? "None";
			let status = scope String();
			status.AppendF("T=toggle theme, Tab=navigate, F2=debug [Theme: {}]", themeName);
			mDrawContext.DrawText(status, 16, .(20, (float)Window.Height - 40), .(1.0f, 1.0f, 1.0f, 0.8f));
		}
	}

	protected override void OnRender(IRenderPassEncoder renderPass, FrameContext frame)
	{
		if (mDrawingRenderer == null)
			return;

		mDrawingRenderer.Render(renderPass, SwapChain.Width, SwapChain.Height, frame.FrameIndex, useMsaa: false);
	}

	protected override void OnResize(int32 width, int32 height)
	{
	}

	//==========================================================================
	// Secondary Window Rendering
	//==========================================================================

	protected override void OnPrepareSecondaryFrame(SecondaryWindowContext ctx, FrameContext frame)
	{
		if (ctx.UserData == null) return;
		let data = ctx.UserData as SecondaryWindowRenderData;
		if (data == null) return;

		data.DrawContext.Clear();
		if (mUIContext != null && data.RootView != null)
			mUIContext.DrawRootView(data.RootView, data.DrawContext);

		data.DrawingRenderer.UpdateProjection(ctx.SwapChain.Width, ctx.SwapChain.Height, frame.FrameIndex);
		data.DrawingRenderer.Prepare(data.DrawContext.GetBatch(), frame.FrameIndex);
	}

	protected override void OnRenderSecondaryWindow(SecondaryWindowContext ctx, IRenderPassEncoder renderPass, FrameContext frame)
	{
		if (ctx.UserData == null) return;
		let data = ctx.UserData as SecondaryWindowRenderData;
		if (data == null) return;

		data.DrawingRenderer.Render(renderPass, ctx.SwapChain.Width, ctx.SwapChain.Height, frame.FrameIndex, useMsaa: false);
	}

	protected override void OnSecondaryWindowResized(SecondaryWindowContext ctx, int32 width, int32 height)
	{
		if (ctx.UserData == null) return;
		let data = ctx.UserData as SecondaryWindowRenderData;
		if (data?.RootView != null)
			data.RootView.SetSize((float)width, (float)height);
	}

	//==========================================================================
	// IFloatingWindowHost
	//==========================================================================

	public bool SupportsOSWindows => true;

	public void CreateFloatingWindow(View floatingWindow, float width, float height,
		float screenX = -1, float screenY = -1,
		delegate void(View) onCloseRequested = null)
	{
		String title = scope .("Float");
		let windowSettings = WindowSettings()
		{
			Title = title,
			Width = (int32)width,
			Height = (int32)height,
			Resizable = true,
			Bordered = false
		};

		if (CreateSecondaryWindow(windowSettings) not case .Ok(let ctx))
		{
			Console.WriteLine("Failed to create floating OS window");
			return;
		}

		// Create per-window drawing infrastructure
		let drawingRenderer = new DrawingRenderer();
		if (drawingRenderer.Initialize(Device, ctx.SwapChain.Format, (int32)ctx.SwapChain.BufferCount, mShaderSystem) case .Err)
		{
			Console.WriteLine("Failed to initialize secondary DrawingRenderer");
			delete drawingRenderer;
			DestroySecondaryWindow(ctx);
			return;
		}

		let drawContext = new DrawContext(mFontService);

		// Create RootView for this window
		let rootView = new RootView();
		rootView.AddView(floatingWindow);
		rootView.SetSize((float)ctx.Window.Width, (float)ctx.Window.Height);
		mUIContext.AddRootView(rootView);

		// Build render data
		let data = new SecondaryWindowRenderData();
		data.DrawContext = drawContext;
		data.DrawingRenderer = drawingRenderer;
		data.RootView = rootView;
		data.FloatingView = floatingWindow;
		data.OnViewCloseRequested = onCloseRequested;
		ctx.UserData = data;

		// Set close callback on the secondary window context
		ctx.OnCloseRequested = new (secCtx) =>
		{
			if (secCtx.UserData == null) return;
			let rd = secCtx.UserData as SecondaryWindowRenderData;
			if (rd?.OnViewCloseRequested != null && rd.FloatingView != null)
				rd.OnViewCloseRequested(rd.FloatingView);
		};

		mFloatingWindowMap[floatingWindow] = ctx;

		// Position the window
		if (screenX >= 0 && screenY >= 0)
		{
			if (let sdlWindow = ctx.Window as SDL3Window)
				SDL_SetWindowPosition(sdlWindow.Handle, (int32)screenX, (int32)screenY);
		}
	}

	public void DestroyFloatingWindow(View floatingWindow)
	{
		SecondaryWindowContext ctx;
		if (!mFloatingWindowMap.TryGetValue(floatingWindow, out ctx))
			return;

		mFloatingWindowMap.Remove(floatingWindow);

		let data = ctx.UserData as SecondaryWindowRenderData;

		// Clear ActiveInputRoot if it points to the RootView being destroyed
		if (mUIContext != null && data != null && mUIContext.ActiveInputRoot == data.RootView)
			mUIContext.ActiveInputRoot = mMainRoot;

		// Remove RootView from shared UIContext
		if (mUIContext != null && data?.RootView != null)
			mUIContext.RemoveRootView(data.RootView);

		// Detach the floating window from the RootView before deleting
		if (data?.RootView != null && floatingWindow.Parent == data.RootView)
			data.RootView.DetachView(floatingWindow);

		// Delete RootView
		if (data?.RootView != null)
		{
			delete data.RootView;
			data.RootView = null;
		}

		// Cleanup render data
		if (data != null)
		{
			data.Dispose(Device);
			delete data;
			ctx.UserData = null;
		}

		DestroySecondaryWindow(ctx);
	}

	//==========================================================================
	// UI Input Routing (multi-window aware)
	//==========================================================================

	private void ProcessUIInput()
	{
		if (mUIContext == null)
			return;

		let mouse = mShell.InputManager.Mouse;
		let keyboard = mShell.InputManager.Keyboard;

		// Determine which window has mouse focus
		let focusedSDLWindow = SDL_GetMouseFocus();
		RootView inputRoot = mMainRoot;

		SDL_Window* mainSDLWindow = null;
		if (let sdlWin = mWindow as SDL3Window)
			mainSDLWindow = sdlWin.Handle;

		if (focusedSDLWindow != null && focusedSDLWindow != mainSDLWindow)
		{
			for (let ctx in mSecondaryWindows)
			{
				let data = ctx.UserData as SecondaryWindowRenderData;
				if (data?.RootView != null)
				{
					if (let sdlWin = ctx.Window as SDL3Window)
					{
						if (sdlWin.Handle == focusedSDLWindow)
						{
							inputRoot = data.RootView;
							break;
						}
					}
				}
			}
		}

		// Track global mouse during drag for floating window placement
		if (mUIContext.DragDrop.IsDragging)
		{
			float globalX = 0, globalY = 0;
			SDL_GetGlobalMouseState(&globalX, &globalY);
			mUIContext.DragDrop.LastGlobalX = globalX;
			mUIContext.DragDrop.LastGlobalY = globalY;
		}
		else if (mDragSourceSDLWindow != null)
		{
			SDL_SetWindowOpacity(mDragSourceSDLWindow, 1.0f);
			mDragSourceSDLWindow = null;
		}

		// Cross-window drag: move OS window to follow cursor, route input to main window
		if (mUIContext.DragDrop.IsDragging && inputRoot != mMainRoot)
		{
			if (mDragSourceSDLWindow == null)
			{
				for (let ctx in mSecondaryWindows)
				{
					let data = ctx.UserData as SecondaryWindowRenderData;
					if (data?.RootView == inputRoot)
					{
						if (let sdlWin = ctx.Window as SDL3Window)
						{
							mDragSourceSDLWindow = sdlWin.Handle;
							int32 winX = 0, winY = 0;
							SDL_GetWindowPosition(mDragSourceSDLWindow, &winX, &winY);
							mDragWindowOffsetX = mUIContext.DragDrop.LastGlobalX - (float)winX;
							mDragWindowOffsetY = mUIContext.DragDrop.LastGlobalY - (float)winY;
						}
						break;
					}
				}
			}

			if (mDragSourceSDLWindow != null)
			{
				SDL_SetWindowPosition(mDragSourceSDLWindow,
					(int32)(mUIContext.DragDrop.LastGlobalX - mDragWindowOffsetX),
					(int32)(mUIContext.DragDrop.LastGlobalY - mDragWindowOffsetY));

				float opacity = (mUIContext.DragDrop.CurrentEffect != .None) ? 0.5f : 1.0f;
				SDL_SetWindowOpacity(mDragSourceSDLWindow, opacity);
			}

			// Route to main window for dock zone hit-testing
			mUIContext.ActiveInputRoot = mMainRoot;

			if (mainSDLWindow != null)
			{
				int32 mainWinX = 0, mainWinY = 0;
				SDL_GetWindowPosition(mainSDLWindow, &mainWinX, &mainWinY);

				float relX = mUIContext.DragDrop.LastGlobalX - (float)mainWinX;
				float relY = mUIContext.DragDrop.LastGlobalY - (float)mainWinY;

				UIInputHelper.ProcessMouseInput(mouse, keyboard, mUIContext, relX, relY);
				mInputHelper.ProcessKeyboardInput(keyboard, mUIContext, mFrameDelta);
			}
			return;
		}

		mUIContext.ActiveInputRoot = inputRoot;
		UIInputHelper.ProcessMouseInput(mouse, keyboard, mUIContext);
		mInputHelper.ProcessKeyboardInput(keyboard, mUIContext, mFrameDelta);
	}

	private void UpdateCursor(IMouse mouse)
	{
		if (mUIContext?.ActiveInputRoot == null)
			return;

		let cursor = mUIContext.ActiveInputRoot.RequestedCursor;
		if (cursor != mLastCursor)
		{
			mLastCursor = cursor;
			mouse.Cursor = InputMapping.MapCursor(cursor);
		}
	}

	//==========================================================================
	// Theme Cycling
	//==========================================================================

	private void CycleTheme()
	{
		let currentName = (mUIContext.Theme?.Name != null) ? StringView(mUIContext.Theme.Name) : "Dark";

		if (currentName == "Dark")
		{
			mUIContext.Theme = LightTheme.Create();
		}
		else if (currentName == "Light")
		{
			mUIContext.Theme = Sandbox.TurboBadgerTheme.Create(
				mTBButton, mTBButtonPressed, mTBButtonFlatOutline,
				mTBCheckbox, mTBCheckboxMark, mTBCheckboxPressed,
				mTBRadio, mTBRadioMark, mTBRadioPressed,
				mTBSliderBgX, mTBSliderHandle,
				mTBContainer, mTBSeparatorX,
				mTBSelection, mTBEditField,
				mTBScrollBgX, mTBScrollBgY,
				mTBScrollFgX, mTBScrollFgY,
				mTBFocusR4,
				mTBArrowDown, mTBArrowRight,
				mTBWindow, mTBWindowActive,
				mTBItemHover, mTBItemSelected,
				mTBArrowUp,
				mTBTabTopActive, mTBTabTopInactive,
				mTBTabBottomActive, mTBTabBottomInactive,
				mTBTabLeftActive, mTBTabLeftInactive,
				mTBTabRightActive, mTBTabRightInactive);
		}
		else
		{
			mUIContext.Theme = DarkTheme.Create();
		}
	}

	//==========================================================================
	// Asset Loading
	//==========================================================================

	private void GenerateTestImages()
	{
		let checker = Sedulous.Imaging.Image.CreateCheckerboard(64,
			.(0.9f, 0.9f, 0.9f, 1.0f), .(0.4f, 0.4f, 0.5f, 1.0f), 8);
		mCheckerImage = new OwnedImageData((.)checker.Width, (.)checker.Height, .RGBA8, checker.Data);
		delete checker;

		let gradient = Sedulous.Imaging.Image.CreateGradient(64, 64,
			.(0.2f, 0.5f, 0.9f, 1.0f), .(0.9f, 0.3f, 0.5f, 1.0f));
		mGradientImage = new OwnedImageData((.)gradient.Width, (.)gradient.Height, .RGBA8, gradient.Data);
		delete gradient;
	}

	private OwnedImageData LoadPngImage(StringView path)
	{
		if (ImageLoaderFactory.LoadImage(path) case .Ok(let img))
		{
			let result = new OwnedImageData((.)img.Width, (.)img.Height, .RGBA8, img.Data);
			delete img;
			return result;
		}
		return null;
	}

	private void LoadTBAssets()
	{
		StringView basePath = GetAssetPath("UI/default_skin", .. scope .());
		mTBButton = LoadPngImage(scope $"{basePath}/button.png");
		if (mTBButton == null)
		{
			basePath = "../../../Assets/UI/default_skin";
			mTBButton = LoadPngImage(scope $"{basePath}/button.png");
		}
		if (mTBButton == null)
			return;

		mTBButtonPressed = LoadPngImage(scope $"{basePath}/button_pressed.png");
		mTBButtonFlatOutline = LoadPngImage(scope $"{basePath}/button_flat_outline.png");
		mTBCheckbox = LoadPngImage(scope $"{basePath}/checkbox.png");
		mTBCheckboxMark = LoadPngImage(scope $"{basePath}/checkbox_mark.png");
		mTBCheckboxPressed = LoadPngImage(scope $"{basePath}/checkbox_pressed.png");
		mTBRadio = LoadPngImage(scope $"{basePath}/radio.png");
		mTBRadioMark = LoadPngImage(scope $"{basePath}/radio_mark.png");
		mTBRadioPressed = LoadPngImage(scope $"{basePath}/radio_pressed.png");
		mTBSliderBgX = LoadPngImage(scope $"{basePath}/slider_bg_x.png");
		mTBSliderHandle = LoadPngImage(scope $"{basePath}/slider_handle.png");
		mTBContainer = LoadPngImage(scope $"{basePath}/container.png");
		mTBSeparatorX = LoadPngImage(scope $"{basePath}/item_separator_x.png");
		mTBSelection = LoadPngImage(scope $"{basePath}/selection.png");
		mTBEditField = LoadPngImage(scope $"{basePath}/editfield.png");
		mTBScrollBgX = LoadPngImage(scope $"{basePath}/scroll_bg_x.png");
		mTBScrollBgY = LoadPngImage(scope $"{basePath}/scroll_bg_y.png");
		mTBScrollFgX = LoadPngImage(scope $"{basePath}/scroll_fg_x.png");
		mTBScrollFgY = LoadPngImage(scope $"{basePath}/scroll_fg_y.png");
		mTBFocusR4 = LoadPngImage(scope $"{basePath}/focus_r4.png");
		mTBArrowDown = LoadPngImage(scope $"{basePath}/arrow_down.png");
		mTBArrowRight = LoadPngImage(scope $"{basePath}/arrow_right.png");
		mTBWindow = LoadPngImage(scope $"{basePath}/window.png");
		mTBWindowActive = LoadPngImage(scope $"{basePath}/window_active.png");
		mTBItemHover = LoadPngImage(scope $"{basePath}/item_hover.png");
		mTBItemSelected = LoadPngImage(scope $"{basePath}/item_selected.png");
		mTBArrowUp = LoadPngImage(scope $"{basePath}/arrow_up.png");
		mTBTabTopActive = LoadPngImage(scope $"{basePath}/tab_button_top_active.png");
		mTBTabTopInactive = LoadPngImage(scope $"{basePath}/tab_button_top_inactive.png");
		mTBTabBottomActive = LoadPngImage(scope $"{basePath}/tab_button_bottom_active.png");
		mTBTabBottomInactive = LoadPngImage(scope $"{basePath}/tab_button_bottom_inactive.png");
		mTBTabLeftActive = LoadPngImage(scope $"{basePath}/tab_button_left_active.png");
		mTBTabLeftInactive = LoadPngImage(scope $"{basePath}/tab_button_left_inactive.png");
		mTBTabRightActive = LoadPngImage(scope $"{basePath}/tab_button_right_active.png");
		mTBTabRightInactive = LoadPngImage(scope $"{basePath}/tab_button_right_inactive.png");
	}

	//==========================================================================
	// Demo UI Building
	//==========================================================================

	private void BuildDemo()
	{
		let outerLayout = new LinearLayout();
		outerLayout.Orientation = .Vertical;
		mRoot.AddView(outerLayout, new FrameLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.MatchParent));

		BuildMenuBarDemo(outerLayout);

		let scrollView = new ScrollView();
		scrollView.AllowVerticalScroll = true;
		scrollView.AllowHorizontalScroll = false;
		outerLayout.AddView(scrollView, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 0, 1));

		let topRow = new LinearLayout();
		topRow.Orientation = .Horizontal;
		topRow.Spacing = 16;
		topRow.Padding = .(8);
		scrollView.SetContent(topRow);

		let leftColumn = new LinearLayout();
		leftColumn.Orientation = .Vertical;
		leftColumn.Spacing = 16;
		let leftLp = new LinearLayout.LayoutParams(0, LayoutParams.WrapContent);
		leftLp.Weight = 1;
		topRow.AddView(leftColumn, leftLp);

		let rightColumn = new LinearLayout();
		rightColumn.Orientation = .Vertical;
		rightColumn.Spacing = 16;
		let rightLp = new LinearLayout.LayoutParams(0, LayoutParams.WrapContent);
		rightLp.Weight = 1;
		topRow.AddView(rightColumn, rightLp);

		BuildLabelSection(leftColumn);
		BuildButtonSection(leftColumn);
		BuildToggleSection(leftColumn);
		BuildSliderSection(leftColumn);
		BuildAnimationSection(leftColumn);
		BuildOverlaySection(leftColumn);
		BuildDragDropSection(leftColumn);
		BuildTabViewSection(leftColumn);

		BuildPanelAndImageSection(rightColumn);
		BuildTextEditSection(rightColumn);
		BuildListViewSection(rightColumn);
		BuildTreeViewSection(rightColumn);
		BuildToolkitSection(rightColumn);
		BuildAdvancedToolkitSection(leftColumn);
		BuildPhase15Section(rightColumn);
	}

	private void BuildLabelSection(LinearLayout parent)
	{
		let section = new Label("Labels");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let row = new LinearLayout();
		row.Orientation = .Horizontal;
		row.Spacing = 20;
		parent.AddView(row, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let label1 = new Label("Default (16px)");
		row.AddView(label1, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let label2 = new Label("Large (24px)", 24);
		row.AddView(label2, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let label3 = new Label("Colored");
		label3.TextColor = .(0.3f, 0.8f, 0.4f, 1.0f);
		row.AddView(label3, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let label4 = new Label("Disabled");
		label4.Enabled = false;
		row.AddView(label4, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildButtonSection(LinearLayout parent)
	{
		let section = new Label("Buttons");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let row = new LinearLayout();
		row.Orientation = .Horizontal;
		row.Spacing = 10;
		parent.AddView(row, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let btn1 = new Button("Click Me");
		mClickLabel = new Label("Not clicked yet");
		btn1.OnClick.Subscribe(new => OnDemoButtonClicked);
		row.AddView(btn1, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let btn2 = new Button("Disabled");
		btn2.Enabled = false;
		row.AddView(btn2, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let toggle = new ToggleButton("Toggle");
		row.AddView(toggle, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		row.AddView(mClickLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildToggleSection(LinearLayout parent)
	{
		let section = new Label("CheckBoxes & Radio Buttons");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let row = new LinearLayout();
		row.Orientation = .Horizontal;
		row.Spacing = 30;
		parent.AddView(row, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let cbCol = new LinearLayout();
		cbCol.Orientation = .Vertical;
		cbCol.Spacing = 4;
		row.AddView(cbCol, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let cb1 = new CheckBox("Enable audio");
		cb1.IsChecked = true;
		cbCol.AddView(cb1);

		let cb2 = new CheckBox("Fullscreen");
		cbCol.AddView(cb2);

		let cb3 = new CheckBox("VSync");
		cb3.IsChecked = true;
		cbCol.AddView(cb3);

		let cbDisabled = new CheckBox("Locked option");
		cbDisabled.Enabled = false;
		cbDisabled.IsChecked = true;
		cbCol.AddView(cbDisabled);

		let radioGroup = new RadioGroup();
		row.AddView(radioGroup, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let rb1 = new RadioButton("Low quality");
		radioGroup.AddRadioButton(rb1);

		let rb2 = new RadioButton("Medium quality");
		radioGroup.AddRadioButton(rb2);

		let rb3 = new RadioButton("High quality");
		radioGroup.AddRadioButton(rb3);

		radioGroup.CheckAt(1);

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildSliderSection(LinearLayout parent)
	{
		let section = new Label("Slider & Progress Bar");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let sliderRow = new LinearLayout();
		sliderRow.Orientation = .Horizontal;
		sliderRow.Spacing = 10;
		parent.AddView(sliderRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 24));

		let sliderLabel = new Label("Value:");
		sliderRow.AddView(sliderLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		let slider = new Slider();
		slider.Min = 0;
		slider.Max = 100;
		slider.Step = 1;
		slider.Value = 50;
		sliderRow.AddView(slider, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		mSliderValueLabel = new Label("50");
		mSliderValueLabel.MinWidth = 40;
		sliderRow.AddView(mSliderValueLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		slider.OnValueChanged.Subscribe(new => OnSliderValueChanged);

		let progressRow = new LinearLayout();
		progressRow.Orientation = .Horizontal;
		progressRow.Spacing = 10;
		parent.AddView(progressRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		mProgressBar = new ProgressBar();
		mProgressBar.Progress = 0;
		progressRow.AddView(mProgressBar, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		mProgressLabel = new Label("0%");
		mProgressLabel.FontSize = 12;
		mProgressLabel.MinWidth = 40;
		progressRow.AddView(mProgressLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildPanelAndImageSection(LinearLayout parent)
	{
		let section = new Label("Panel & ImageView");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let row = new LinearLayout();
		row.Orientation = .Horizontal;
		row.Spacing = 16;
		parent.AddView(row, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 150));

		let panel = new Panel();
		panel.BorderWidth = 2;
		panel.CornerRadius = 8;
		panel.Padding = .(12);
		row.AddView(panel, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		let panelContent = new LinearLayout();
		panelContent.Orientation = .Vertical;
		panelContent.Spacing = 8;
		panel.AddView(panelContent, new FrameLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.MatchParent));

		let panelTitle = new Label("Bordered Panel");
		panelContent.AddView(panelTitle, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let panelDesc = new Label("Panel extends FrameLayout");
		panelDesc.FontSize = 12;
		panelContent.AddView(panelDesc, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let innerBtn = new Button("Nested Button");
		panelContent.AddView(innerBtn, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let imgPanel = new Panel();
		imgPanel.BorderWidth = 1;
		imgPanel.CornerRadius = 4;
		imgPanel.Padding = .(4);
		row.AddView(imgPanel, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		let imgCol = new LinearLayout();
		imgCol.Orientation = .Vertical;
		imgCol.Spacing = 4;
		imgPanel.AddView(imgCol, new FrameLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.MatchParent));

		let imgLabel = new Label("Checkerboard (FitCenter)");
		imgLabel.FontSize = 11;
		imgCol.AddView(imgLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let imageView1 = new ImageView();
		imageView1.Source = mCheckerImage;
		imageView1.ScaleType = .FitCenter;
		imgCol.AddView(imageView1, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 0, 1));

		let imgPanel2 = new Panel();
		imgPanel2.BorderWidth = 1;
		imgPanel2.CornerRadius = 4;
		imgPanel2.Padding = .(4);
		row.AddView(imgPanel2, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		let imgCol2 = new LinearLayout();
		imgCol2.Orientation = .Vertical;
		imgCol2.Spacing = 4;
		imgPanel2.AddView(imgCol2, new FrameLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.MatchParent));

		let imgLabel2 = new Label("Gradient (FillBounds)");
		imgLabel2.FontSize = 11;
		imgCol2.AddView(imgLabel2, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let imageView2 = new ImageView();
		imageView2.Source = mGradientImage;
		imageView2.ScaleType = .FillBounds;
		imgCol2.AddView(imageView2, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 0, 1));
	}

	private void BuildTextEditSection(LinearLayout parent)
	{
		let section = new Label("Text Editing");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let col = new LinearLayout();
		col.Orientation = .Vertical;
		col.Spacing = 8;
		parent.AddView(col, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let edit1 = new EditText("Type here...");
		col.AddView(edit1, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 32));

		mEditMirrorLabel = new Label("(text will appear here)");
		mEditMirrorLabel.FontSize = 12;
		col.AddView(mEditMirrorLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
		edit1.OnTextChanged.Subscribe(new (ed) =>
		{
			if (mEditMirrorLabel != null)
				mEditMirrorLabel.Text = ed.Text;
		});

		let numRow = new LinearLayout();
		numRow.Orientation = .Horizontal;
		numRow.Spacing = 8;
		col.AddView(numRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 32));

		let numLabel = new Label("Digits only:");
		numLabel.VerticalAlignment = .Middle;
		numRow.AddView(numLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		let numEdit = new EditText("0-9");
		numEdit.Filter = InputFilter.Digits();
		numEdit.MaxLength = 10;
		numRow.AddView(numEdit, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		let pwRow = new LinearLayout();
		pwRow.Orientation = .Horizontal;
		pwRow.Spacing = 8;
		col.AddView(pwRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 32));

		let pwLabel = new Label("Password:");
		pwLabel.VerticalAlignment = .Middle;
		pwRow.AddView(pwLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		let pwEdit = new PasswordBox("Enter password");
		pwRow.AddView(pwEdit, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));

		let roRow = new LinearLayout();
		roRow.Orientation = .Horizontal;
		roRow.Spacing = 8;
		col.AddView(roRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 32));

		let roLabel = new Label("Read-only:");
		roLabel.VerticalAlignment = .Middle;
		roRow.AddView(roLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		let roEdit = new EditText();
		roEdit.Text = "This text cannot be edited";
		roEdit.ReadOnly = true;
		roRow.AddView(roEdit, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));
	}

	private void BuildListViewSection(LinearLayout parent)
	{
		let section = new Label("ListView (10,000 items)");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let listView = new ListView();
		listView.FixedItemHeight = 22;
		parent.AddView(listView, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 200));

		mListAdapter = new DemoListAdapter(10000);
		listView.SetAdapter(mListAdapter);
	}

	private void BuildTreeViewSection(LinearLayout parent)
	{
		let section = new Label("TreeView");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let treeView = new TreeView();
		treeView.FixedItemHeight = 22;
		parent.AddView(treeView, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 180));

		mTreeAdapter = new DemoTreeAdapter();
		treeView.SetAdapter(mTreeAdapter);
	}

	private void BuildDragDropSection(LinearLayout parent)
	{
		let section = new Label("Drag & Drop");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let desc = new Label("Drag panels to reorder:");
		desc.FontSize = 11;
		parent.AddView(desc, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let container = new ReorderContainer();
		parent.AddView(container, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 60));

		Color[?] colors = .(
			Color(0.8f, 0.2f, 0.2f, 1.0f),
			Color(0.2f, 0.7f, 0.2f, 1.0f),
			Color(0.2f, 0.4f, 0.9f, 1.0f),
			Color(0.9f, 0.7f, 0.1f, 1.0f),
			Color(0.7f, 0.3f, 0.8f, 1.0f)
		);
		StringView[?] names = .("Red", "Green", "Blue", "Yellow", "Purple");

		for (int i = 0; i < 5; i++)
		{
			let dpanel = new DraggablePanel(names[i], colors[i]);
			container.AddView(dpanel, new LinearLayout.LayoutParams(0, LayoutParams.MatchParent, 1));
		}
	}

	private void BuildAnimationSection(LinearLayout parent)
	{
		let section = new Label("Animations");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let row = new LinearLayout();
		row.Orientation = .Horizontal;
		row.Spacing = 10;
		row.Gravity = .CenterV;
		parent.AddView(row, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let fadeBtn = new Button("Fade");
		row.AddView(fadeBtn, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));
		fadeBtn.OnClick.Subscribe(new (btn) =>
			{
				let sb = new Storyboard(.Sequential);
				sb.Add(ViewAnimator.FadeOut(btn, 0.4f, Easings.EaseInQuadratic));
				sb.Add(ViewAnimator.FadeIn(btn, 0.4f, Easings.EaseOutQuadratic));
				mUIContext.Animations.Add(sb);
			});

		let slideBtn = new Button("Slide");
		row.AddView(slideBtn, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));
		slideBtn.OnClick.Subscribe(new (btn) =>
			{
				let sb = new Storyboard(.Sequential);
				sb.Add(ViewAnimator.TranslateX(btn, 0, 80, 0.3f, Easings.EaseOutBack));
				sb.Add(ViewAnimator.TranslateX(btn, 80, 0, 0.3f, Easings.EaseInOutCubic));
				mUIContext.Animations.Add(sb);
			});

		let scaleBtn = new Button("Bounce");
		row.AddView(scaleBtn, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));
		scaleBtn.OnClick.Subscribe(new (btn) =>
			{
				let sb = new Storyboard(.Sequential);
				sb.Add(ViewAnimator.ScaleTo(btn, 1, 1.3f, 0.15f, Easings.EaseOutQuadratic));
				sb.Add(ViewAnimator.ScaleTo(btn, 1.3f, 1, 0.3f, Easings.EaseOutElastic));
				mUIContext.Animations.Add(sb);
			});

		let pulsePanel = new Panel();
		pulsePanel.BorderWidth = 1;
		pulsePanel.CornerRadius = 4;
		row.AddView(pulsePanel, new LinearLayout.LayoutParams(60, 30));

		let pulseLabel = new Label("Pulse");
		pulseLabel.FontSize = 11;
		pulseLabel.TextAlignment = .Center;
		pulseLabel.VerticalAlignment = .Middle;
		pulsePanel.AddView(pulseLabel, new FrameLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.MatchParent));

		let colorAnim = new ColorAnimation(
			.(0.2f, 0.5f, 0.9f, 1.0f), .(0.9f, 0.3f, 0.5f, 1.0f),
			1.5f,
			new (c) => { pulsePanel.FillColor = c; },
			Easings.EaseInOutSin);
		colorAnim.AutoReverse = true;
		colorAnim.RepeatCount = -1;
		colorAnim.Target = pulsePanel;
		mUIContext.Animations.Add(colorAnim);

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildOverlaySection(LinearLayout parent)
	{
		let section = new Label("Overlays");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let row = new LinearLayout();
		row.Orientation = .Horizontal;
		row.Spacing = 10;
		row.Gravity = .CenterV;
		parent.AddView(row, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let alertBtn = new Button("Alert");
		alertBtn.TooltipText = new .("Show an alert dialog");
		row.AddView(alertBtn, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));
		alertBtn.OnClick.Subscribe(new (btn) =>
			{
				let dialog = Dialog.Alert("Alert", "This is a simple alert dialog.");
				mUIContext.ShowModalPopup(dialog);
			});

		let confirmBtn = new Button("Confirm");
		confirmBtn.TooltipText = new .("Show a confirm dialog");
		row.AddView(confirmBtn, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));
		confirmBtn.OnClick.Subscribe(new (btn) =>
			{
				let dialog = Dialog.Confirm("Confirm", "Do you want to proceed?");
				dialog.OnResult.Subscribe(new (d, r) =>
					{
						if (mConfirmResultLabel != null)
						{
							if (r == .Yes)
								mConfirmResultLabel.Text = "Result: Yes";
							else if (r == .No)
								mConfirmResultLabel.Text = "Result: No";
							else
								mConfirmResultLabel.Text = "Result: Cancelled";
						}
					});
				mUIContext.ShowModalPopup(dialog);
			});

		mConfirmResultLabel = new Label("Result: -");
		mConfirmResultLabel.FontSize = 13;
		row.AddView(mConfirmResultLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let row2 = new LinearLayout();
		row2.Orientation = .Horizontal;
		row2.Spacing = 10;
		row2.Gravity = .CenterV;
		parent.AddView(row2, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let menuBtn = new Button("Menu");
		menuBtn.TooltipText = new .("Click for a context menu");
		row2.AddView(menuBtn, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));
		menuBtn.OnClick.Subscribe(new (btn) =>
			{
				let screenPos = btn.ToScreen(.(0, btn.Height));
				let menu = new ContextMenu();
				menu.AddItem("Cut", new () => { if (mConfirmResultLabel != null) mConfirmResultLabel.Text = "Cut!"; });
				menu.AddItem("Copy", new () => { if (mConfirmResultLabel != null) mConfirmResultLabel.Text = "Copy!"; });
				menu.AddSeparator();
				menu.AddItem("Paste", new () => { if (mConfirmResultLabel != null) mConfirmResultLabel.Text = "Paste!"; });
				let sub = menu.AddSubmenu("More Options");
				sub.AddItem("Option A", new () => { if (mConfirmResultLabel != null) mConfirmResultLabel.Text = "Option A!"; });
				sub.AddItem("Option B", new () => { if (mConfirmResultLabel != null) mConfirmResultLabel.Text = "Option B!"; });
				sub.AddSeparator();
				let nested = sub.AddSubmenu("Even More");
				nested.AddItem("Deep Item", new () => { if (mConfirmResultLabel != null) mConfirmResultLabel.Text = "Deep Item!"; });
				ContextMenu.Show(mUIContext, screenPos.X, screenPos.Y, menu);
			});

		let tooltipLabel = new Label("Hover for tooltip");
		tooltipLabel.FontSize = 13;
		tooltipLabel.TooltipText = new .("This is a tooltip!");
		row2.AddView(tooltipLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildTabViewSection(LinearLayout parent)
	{
		let section = new Label("TabView");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		mTabView = new TabView();
		parent.AddView(mTabView, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 120));

		let infoContent = new Label("This is the Info tab content.\nTabView switches between content views.");
		infoContent.Padding = .(8);
		mTabView.AddTab("Info", infoContent);

		let settingsContent = new LinearLayout();
		settingsContent.Orientation = .Vertical;
		settingsContent.Spacing = 4;
		settingsContent.Padding = .(8);
		let settingsCb = new CheckBox("Enable notifications");
		settingsCb.IsChecked = true;
		settingsContent.AddView(settingsCb);
		let settingsCb2 = new CheckBox("Dark mode");
		settingsContent.AddView(settingsCb2);
		mTabView.AddTab("Settings", settingsContent);

		let aboutContent = new Label("Sedulous.UI.Toolkit v1.0\nPhase 12 controls demo.");
		aboutContent.Padding = .(8);
		mTabView.AddTab("About", aboutContent);

		let placementRow = new LinearLayout();
		placementRow.Orientation = .Horizontal;
		placementRow.Spacing = 8;
		placementRow.BaselineAligned = false;
		placementRow.Gravity = .CenterV;
		parent.AddView(placementRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let placementLabel = new Label("Tab Placement:");
		placementLabel.FontSize = 11;
		placementRow.AddView(placementLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let placementGroup = new RadioGroup();
		placementGroup.Orientation = .Horizontal;
		placementGroup.Spacing = 6;
		placementRow.AddView(placementGroup, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let rbTop = new RadioButton("Top");
		placementGroup.AddRadioButton(rbTop);
		let rbBottom = new RadioButton("Bottom");
		placementGroup.AddRadioButton(rbBottom);
		let rbLeft = new RadioButton("Left");
		placementGroup.AddRadioButton(rbLeft);
		let rbRight = new RadioButton("Right");
		placementGroup.AddRadioButton(rbRight);
		placementGroup.CheckAt(0);

		placementGroup.OnSelectionChanged.Subscribe(new (group, btn) =>
		{
			if (mTabView == null) return;
			if (btn == rbTop) mTabView.Placement = .Top;
			else if (btn == rbBottom) mTabView.Placement = .Bottom;
			else if (btn == rbLeft) mTabView.Placement = .Left;
			else if (btn == rbRight) mTabView.Placement = .Right;
		});

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildToolkitSection(LinearLayout parent)
	{
		let section = new Label("Toolkit Controls");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let splitLabel = new Label("SplitView (drag divider):");
		splitLabel.FontSize = 11;
		parent.AddView(splitLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let splitView = new SplitView(.Horizontal);
		parent.AddView(splitView, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 80));

		let leftPane = new Panel();
		leftPane.FillColor = .(0.2f, 0.4f, 0.6f, 1.0f);
		leftPane.CornerRadius = 4;
		let leftPaneLabel = new Label("Left Pane");
		leftPaneLabel.TextAlignment = .Center;
		leftPaneLabel.VerticalAlignment = .Middle;
		leftPane.AddView(leftPaneLabel, new FrameLayout.LayoutParams(-1, -1));

		let rightPane = new Panel();
		rightPane.FillColor = .(0.6f, 0.3f, 0.4f, 1.0f);
		rightPane.CornerRadius = 4;
		let rightPaneLabel = new Label("Right Pane");
		rightPaneLabel.TextAlignment = .Center;
		rightPaneLabel.VerticalAlignment = .Middle;
		rightPane.AddView(rightPaneLabel, new FrameLayout.LayoutParams(-1, -1));

		splitView.SetPanes(leftPane, rightPane);

		let comboRow = new LinearLayout();
		comboRow.Orientation = .Horizontal;
		comboRow.Spacing = 10;
		comboRow.Gravity = .CenterV;
		parent.AddView(comboRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let comboLabel2 = new Label("ComboBox:");
		comboLabel2.FontSize = 11;
		comboRow.AddView(comboLabel2, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let comboBox = new ComboBox();
		comboBox.AddItem("Red");
		comboBox.AddItem("Green");
		comboBox.AddItem("Blue");
		comboBox.AddItem("Yellow");
		comboBox.AddItem("Purple");
		comboBox.SelectedIndex = 0;
		comboBox.MinWidth = 120;
		comboRow.AddView(comboBox, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		mComboLabel = new Label("Selected: Red");
		mComboLabel.FontSize = 11;
		comboRow.AddView(mComboLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		comboBox.OnSelectionChanged.Subscribe(new (cb, idx) =>
		{
			if (mComboLabel != null)
			{
				let text = scope String();
				text.AppendF("Selected: {}", cb.SelectedText);
				mComboLabel.Text = text;
			}
		});

		let nfRow = new LinearLayout();
		nfRow.Orientation = .Horizontal;
		nfRow.Spacing = 10;
		nfRow.Gravity = .CenterV;
		parent.AddView(nfRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 32));

		let numFieldLabel = new Label("NumberField:");
		numFieldLabel.FontSize = 11;
		numFieldLabel.VerticalAlignment = .Middle;
		nfRow.AddView(numFieldLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		let numField = new NumberField(50, 0, 100);
		numField.Step = 5;
		numField.DecimalPlaces = 0;
		nfRow.AddView(numField, new LinearLayout.LayoutParams(120, LayoutParams.MatchParent));

		mNumberLabel = new Label("Value: 50");
		mNumberLabel.FontSize = 11;
		mNumberLabel.VerticalAlignment = .Middle;
		nfRow.AddView(mNumberLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));

		numField.OnValueChanged.Subscribe(new (nf, val) =>
		{
			if (mNumberLabel != null)
			{
				let text = scope String();
				text.AppendF("Value: {}", (int)val);
				mNumberLabel.Text = text;
			}
		});

		let toolbarLabel = new Label("Toolbar:");
		toolbarLabel.FontSize = 11;
		parent.AddView(toolbarLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let toolbar = new Toolbar();
		parent.AddView(toolbar, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let tbNew = toolbar.AddButton("New");
		tbNew.OnClick.Subscribe(new (btn) => { if (mConfirmResultLabel != null) mConfirmResultLabel.Text = "New!"; });
		let tbOpen = toolbar.AddButton("Open");
		tbOpen.OnClick.Subscribe(new (btn) => { if (mConfirmResultLabel != null) mConfirmResultLabel.Text = "Open!"; });
		toolbar.AddSeparator();
		let tbSave = toolbar.AddButton("Save");
		tbSave.OnClick.Subscribe(new (btn) => { if (mConfirmResultLabel != null) mConfirmResultLabel.Text = "Save!"; });

		let statusLabel = new Label("StatusBar:");
		statusLabel.FontSize = 11;
		parent.AddView(statusLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let statusBar = new StatusBar();
		statusBar.SetText("Ready");
		statusBar.AddSection("Ln 1, Col 1");
		parent.AddView(statusBar, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let expander = new Expander("Expander (click to toggle)");
		parent.AddView(expander, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let expanderContent = new LinearLayout();
		expanderContent.Orientation = .Vertical;
		expanderContent.Spacing = 4;
		expanderContent.Padding = .(8);
		let expanderLabel = new Label("This content is inside the Expander.");
		expanderContent.AddView(expanderLabel);
		let expanderBtn = new Button("A button inside");
		expanderContent.AddView(expanderBtn, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));
		expander.SetContent(expanderContent);

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildAdvancedToolkitSection(LinearLayout parent)
	{
		let section = new Label("Advanced Toolkit Controls");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let bcLabel = new Label("Breadcrumb:");
		bcLabel.FontSize = 11;
		parent.AddView(bcLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let breadcrumb = new Breadcrumb();
		StringView[?] bcPath = .("Root", "Assets", "Textures");
		breadcrumb.SetPath(bcPath);
		parent.AddView(breadcrumb, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 28));

		let bcResultLabel = new Label("Path: Root > Assets > Textures");
		bcResultLabel.FontSize = 11;
		parent.AddView(bcResultLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		breadcrumb.OnNavigate.Subscribe(new (bc, level) =>
		{
			if (bcResultLabel != null)
			{
				let path = scope String("Path:");
				for (int i = 0; i <= level; i++)
				{
					if (i > 0) path.Append(" >");
					path.Append(" ");
					path.Append(bc.GetSegment(i));
				}
				bcResultLabel.Text = path;
			}
		});

		let logLabel = new Label("LogView:");
		logLabel.FontSize = 11;
		parent.AddView(logLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let logView = new LogView();
		parent.AddView(logView, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 120));

		logView.AddEntry(.Info, "Application started");
		logView.AddEntry(.Debug, "Loading configuration...");
		logView.AddEntry(.Info, "Config loaded successfully");
		logView.AddEntry(.Warning, "Deprecated API used in module X");
		logView.AddEntry(.Error, "Failed to connect to server");
		logView.AddEntry(.Info, "Retrying connection...");
		logView.AddEntry(.Debug, "Connection attempt 2/3");
		logView.AddEntry(.Info, "Connected successfully");

		let logFilterRow = new LinearLayout();
		logFilterRow.Orientation = .Horizontal;
		logFilterRow.Spacing = 6;
		parent.AddView(logFilterRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let cbDebug = new CheckBox("Debug");
		cbDebug.IsChecked = true;
		cbDebug.OnCheckedChanged.Subscribe(new (cb, val) => { logView.ShowDebug = val; });
		logFilterRow.AddView(cbDebug);

		let cbInfo = new CheckBox("Info");
		cbInfo.IsChecked = true;
		cbInfo.OnCheckedChanged.Subscribe(new (cb, val) => { logView.ShowInfo = val; });
		logFilterRow.AddView(cbInfo);

		let cbWarn = new CheckBox("Warning");
		cbWarn.IsChecked = true;
		cbWarn.OnCheckedChanged.Subscribe(new (cb, val) => { logView.ShowWarning = val; });
		logFilterRow.AddView(cbWarn);

		let cbError = new CheckBox("Error");
		cbError.IsChecked = true;
		cbError.OnCheckedChanged.Subscribe(new (cb, val) => { logView.ShowError = val; });
		logFilterRow.AddView(cbError);

		let cpLabel = new Label("ColorPicker:");
		cpLabel.FontSize = 11;
		parent.AddView(cpLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let colorPicker = new ColorPicker();
		parent.AddView(colorPicker, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 190));

		let colorResultLabel = new Label("Color: #FFFFFF");
		colorResultLabel.FontSize = 11;
		parent.AddView(colorResultLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		colorPicker.OnColorChanged.Subscribe(new (cp, color) =>
		{
			if (colorResultLabel != null)
			{
				let text = scope String();
				text.AppendF("Color: #{0:X2}{1:X2}{2:X2} A={3}", (int)color.R, (int)color.G, (int)color.B, (int)color.A);
				colorResultLabel.Text = text;
			}
		});

		let pgLabel = new Label("PropertyGrid:");
		pgLabel.FontSize = 11;
		parent.AddView(pgLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let propGrid = new PropertyGrid();
		parent.AddView(propGrid, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 320));

		propGrid.AddProperty(new FloatEditor("Speed", 10.0f, 0, 100, 0.5f, "Physics"));
		propGrid.AddProperty(new IntEditor("Health", 100, 0, 999, 1, "Stats"));
		propGrid.AddProperty(new BoolEditor("IsActive", true, "General"));
		propGrid.AddProperty(new StringEditor("Name", "Player1", "General"));
		propGrid.AddProperty(new ColorEditor("Tint", Color(0.2f, 0.6f, 1.0f, 1.0f), "Appearance"));
		StringView[?] modes = .("Walk", "Run", "Fly", "Swim");
		propGrid.AddProperty(new EnumEditor("MoveMode", 1, modes, "Physics"));
		propGrid.AddProperty(new Vector2Editor("Position", .(128, 256), -1000, 1000, 1, "Transform"));
		propGrid.AddProperty(new RangeEditor("Volume", 0.8f, 0, 1, 0.05f, "Audio"));

		let dtLabel = new Label("DraggableTreeView:");
		dtLabel.FontSize = 11;
		parent.AddView(dtLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let dragTree = new DraggableTreeView();
		dragTree.FixedItemHeight = 22;
		parent.AddView(dragTree, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 130));

		mReorderAdapter = new ReorderableListAdapter();
		dragTree.SetAdapter(mReorderAdapter);

		let dtResultLabel = new Label("Drag items to reorder");
		dtResultLabel.FontSize = 11;
		parent.AddView(dtResultLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		dragTree.OnItemReordered.Subscribe(new (tree, from, to) =>
		{
			if (dtResultLabel != null)
			{
				let text = scope String();
				text.AppendF("Moved item {} -> {}", from, to);
				dtResultLabel.Text = text;
			}
		});

		// DockManager demo with floating window support via RHI
		let dockLabel = new Label("DockManager (drag headers/tabs to dock, double-click float title to re-dock):");
		dockLabel.FontSize = 11;
		parent.AddView(dockLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let dockManager = new DockManager();
		dockManager.FloatingWindowHost = this;
		parent.AddView(dockManager, new LinearLayout.LayoutParams(LayoutParams.MatchParent, 250));

		let scenePanel = dockManager.AddPanel("Scene", new Label("Scene viewport"));
		let propsPanel = dockManager.AddPanel("Properties", new Label("Properties panel"));
		let consolePanel = dockManager.AddPanel("Console", new Label("Console output"));
		let assetsPanel = dockManager.AddPanel("Assets", new Label("Asset browser"));

		dockManager.DockPanel(scenePanel, .Center);
		dockManager.DockPanelRelativeTo(propsPanel, .Right, scenePanel.Parent);
		dockManager.DockPanelRelativeTo(consolePanel, .Bottom, dockManager.RootNode);
		dockManager.DockPanelRelativeTo(assetsPanel, .Center, consolePanel.Parent);

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildMenuBarDemo(LinearLayout parent)
	{
		let menuBar = new MenuBar();

		let fileMenu = menuBar.AddMenu("File");
		fileMenu.AddItem("New", new () => { if (mClickLabel != null) mClickLabel.Text = "File > New"; });
		fileMenu.AddItem("Open", new () => { if (mClickLabel != null) mClickLabel.Text = "File > Open"; });
		fileMenu.AddSeparator();
		fileMenu.AddItem("Exit", new () => { if (mClickLabel != null) mClickLabel.Text = "File > Exit"; });

		let editMenu = menuBar.AddMenu("Edit");
		editMenu.AddItem("Undo", new () => { if (mClickLabel != null) mClickLabel.Text = "Edit > Undo"; });
		editMenu.AddItem("Redo", new () => { if (mClickLabel != null) mClickLabel.Text = "Edit > Redo"; });
		editMenu.AddSeparator();
		editMenu.AddItem("Cut", new () => { if (mClickLabel != null) mClickLabel.Text = "Edit > Cut"; });
		editMenu.AddItem("Copy", new () => { if (mClickLabel != null) mClickLabel.Text = "Edit > Copy"; });
		editMenu.AddItem("Paste", new () => { if (mClickLabel != null) mClickLabel.Text = "Edit > Paste"; });

		let viewMenu = menuBar.AddMenu("View");
		viewMenu.AddItem("Zoom In", new () => { if (mClickLabel != null) mClickLabel.Text = "View > Zoom In"; });
		viewMenu.AddItem("Zoom Out", new () => { if (mClickLabel != null) mClickLabel.Text = "View > Zoom Out"; });
		viewMenu.AddItem("Reset Zoom", new () => { if (mClickLabel != null) mClickLabel.Text = "View > Reset Zoom"; });

		let helpMenu = menuBar.AddMenu("Help");
		helpMenu.AddItem("About", new () => {
			let dialog = Dialog.Alert("About", "Sedulous.UI Sandbox\nPhase 15 Demo");
			mUIContext.ShowModalPopup(dialog);
		});

		parent.AddView(menuBar, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	private void BuildPhase15Section(LinearLayout parent)
	{
		let section = new Label("Phase 15 - Framework Gaps");
		section.FontSize = 12;
		parent.AddView(section, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let ellipsisLabel = new Label("TextOverflow.Ellipsis:");
		ellipsisLabel.FontSize = 11;
		parent.AddView(ellipsisLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let ellipsisDemo = new Label("This is a very long label text that should be truncated with ellipsis when it exceeds the available width");
		ellipsisDemo.TextOverflow = .Ellipsis;
		parent.AddView(ellipsisDemo, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let ellipsisShort = new Label("Short text (no ellipsis)");
		ellipsisShort.TextOverflow = .Ellipsis;
		parent.AddView(ellipsisShort, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let flowLabel = new Label("FlowLayout (wrapping):");
		flowLabel.FontSize = 11;
		parent.AddView(flowLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let flowLayout = new FlowLayout();
		flowLayout.HSpacing = 6;
		flowLayout.VSpacing = 6;
		parent.AddView(flowLayout, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		StringView[?] tags = .("Button", "Label", "CheckBox", "Slider", "EditText",
			"Panel", "ListView", "TreeView", "TabView", "ComboBox",
			"Toolbar", "MenuBar", "FlowLayout");
		for (let tag in tags)
		{
			let btn = new Button(tag);
			btn.Padding = .(8, 4, 8, 4);
			btn.FontSize = 11;
			flowLayout.AddView(btn);
		}

		let gridLabel = new Label("GridLayout star sizing (Fixed 80px | Star 1 | Star 2):");
		gridLabel.FontSize = 11;
		parent.AddView(gridLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let starGrid = new GridLayout();
		starGrid.ColumnCount = 3;
		starGrid.ColumnSpacing = 4;
		starGrid.RowSpacing = 4;
		starGrid.SetColumnSpecs(.Pixels(80), .Star(1), .Star(2));
		parent.AddView(starGrid, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let cell1 = new Panel();
		cell1.FillColor = .(0.6f, 0.3f, 0.3f, 1.0f);
		cell1.CornerRadius = 3;
		cell1.MinHeight = 30;
		let c1Label = new Label("80px");
		c1Label.FontSize = 11;
		c1Label.TextAlignment = .Center;
		c1Label.VerticalAlignment = .Middle;
		cell1.AddView(c1Label, new FrameLayout.LayoutParams(-1, -1));
		starGrid.AddView(cell1);

		let cell2 = new Panel();
		cell2.FillColor = .(0.3f, 0.6f, 0.3f, 1.0f);
		cell2.CornerRadius = 3;
		cell2.MinHeight = 30;
		let c2Label = new Label("Star(1)");
		c2Label.FontSize = 11;
		c2Label.TextAlignment = .Center;
		c2Label.VerticalAlignment = .Middle;
		cell2.AddView(c2Label, new FrameLayout.LayoutParams(-1, -1));
		starGrid.AddView(cell2);

		let cell3 = new Panel();
		cell3.FillColor = .(0.3f, 0.3f, 0.6f, 1.0f);
		cell3.CornerRadius = 3;
		cell3.MinHeight = 30;
		let c3Label = new Label("Star(2)");
		c3Label.FontSize = 11;
		c3Label.TextAlignment = .Center;
		c3Label.VerticalAlignment = .Middle;
		cell3.AddView(c3Label, new FrameLayout.LayoutParams(-1, -1));
		starGrid.AddView(cell3);

		let cmdLabel = new Label("ICommand (click toggles enabled):");
		cmdLabel.FontSize = 11;
		parent.AddView(cmdLabel, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let cmdRow = new LinearLayout();
		cmdRow.Orientation = .Horizontal;
		cmdRow.Spacing = 8;
		cmdRow.Gravity = .CenterV;
		parent.AddView(cmdRow, new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));

		let cmdResultLabel = new Label("Command not executed");
		cmdResultLabel.FontSize = 11;

		mCommandEnabled = true;
		mDemoCommand = new RelayCommand(
			new () => { mDemoCommandLabel.Text = "Command executed!"; },
			new () => mCommandEnabled);
		mDemoCommandLabel = cmdResultLabel;

		let cmdButton = new Button("Run Command");
		cmdButton.Command = mDemoCommand;
		cmdRow.AddView(cmdButton, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		let toggleBtn = new Button("Toggle Enabled");
		toggleBtn.OnClick.Subscribe(new => OnToggleCommand);
		cmdRow.AddView(toggleBtn, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		cmdRow.AddView(cmdResultLabel, new LinearLayout.LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));

		parent.AddView(new Separator(), new LinearLayout.LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
	}

	//==========================================================================
	// Callbacks
	//==========================================================================

	private void OnDemoButtonClicked(Button btn)
	{
		if (mClickLabel != null)
			mClickLabel.Text = "Clicked!";
	}

	private void OnToggleCommand(Button btn)
	{
		mCommandEnabled = !mCommandEnabled;
		mDemoCommand?.RaiseCanExecuteChanged();
	}

	private void OnSliderValueChanged(Slider slider, float value)
	{
		if (mSliderValueLabel != null)
		{
			let str = scope String();
			((int)value).ToString(str);
			mSliderValueLabel.Text = str;
		}
	}

	//==========================================================================
	// Shutdown
	//==========================================================================

	protected override void OnShutdown()
	{
		// Destroy all floating windows first (they reference shared UIContext)
		let floatingViews = scope List<View>();
		for (let kv in mFloatingWindowMap)
			floatingViews.Add(kv.key);
		for (let view in floatingViews)
			DestroyFloatingWindow(view);
		mFloatingWindowMap.Clear();

		// Cleanup UI
		if (mUIContext != null)
		{
			mUIContext.RemoveRootView(mMainRoot);
			delete mMainRoot;
			delete mUIContext;
			mUIContext = null;
		}

		Theme.ShutdownExtensions();

		// Cleanup drawing renderer
		if (mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
			mDrawingRenderer = null;
		}

		// Cleanup shader system
		if (mShaderSystem != null)
		{
			mShaderSystem.Dispose();
			delete mShaderSystem;
		}
	}
}
