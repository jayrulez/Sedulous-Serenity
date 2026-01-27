namespace Sedulous.Framework.UI;

using System;
using System.Collections;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Input;
using Sedulous.UI;
using Sedulous.UI.Shell;
using Sedulous.Drawing.Renderer;
using Sedulous.Drawing;
using Sedulous.RHI;
using Sedulous.Render;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.Mathematics;
using Sedulous.Profiler;

/// UI subsystem for managing user interface.
/// Owns a global UIContext for screen-space UI overlays.
/// Implements ISceneAware to automatically create UISceneModule for each scene.
public class UISubsystem : Subsystem, ISceneAware
{
	/// UI updates after game logic but before rendering.
	public override int32 UpdateOrder => 400;

	// Core UI
	private UIContext mUIContext;
	private DrawContext mDrawContext;
	private DrawingRenderer mDrawingRenderer;

	// Services
	private IFontService mFontService;
	private ShellClipboardAdapter mClipboardAdapter;
	private ITheme mTheme;

	// World-space UI
	private WorldSpaceUIFeature mWorldSpaceUIFeature;
	private RenderSystem mRenderSystem;
	private int32 mFrameCount;
	private List<UISceneModule> mSceneModules = new .() ~ delete _;
	private uint32 mViewportWidth;
	private uint32 mViewportHeight;

	// Dependencies
	private InputSubsystem mInputSubsystem;
	private IDevice mDevice;
	private bool mRenderingInitialized;

	// Total time accumulator
	private float mTotalTime;

	// Keyboard event delegates
	private delegate void(Sedulous.Shell.Input.KeyCode, bool) mKeyEventDelegate;
	private delegate void(StringView) mTextInputDelegate;

	/// The global UI context for screen-space overlays.
	public UIContext UIContext => mUIContext;

	/// The UI renderer.
	public DrawingRenderer DrawingRenderer => mDrawingRenderer;

	/// The font service for loading and managing fonts.
	public IFontService FontService => mFontService;

	/// The GPU device.
	public IDevice Device => mDevice;

	/// The render system (set during InitializeRendering).
	public RenderSystem RenderSystem => mRenderSystem;

	/// The world-space UI render feature.
	public WorldSpaceUIFeature WorldSpaceUIFeature => mWorldSpaceUIFeature;

	/// Number of in-flight frames.
	public int32 FrameCount => mFrameCount;

	public this(IFontService fontService)
	{
		mFontService = fontService;
	}

	/// Called during the main update phase for UI updates.
	public override void Update(float deltaTime)
	{
		if (!mRenderingInitialized)
			return;

		using (SProfiler.Begin("UI.Update"))
		{
			mTotalTime += deltaTime;
			RouteMouseInput();
			mUIContext.Update(deltaTime, (double)mTotalTime);

			// Check if screen-space UI consumed input
			// Ignore transparent root element - only block if a real child element is hit
			bool screenUIConsumed = mUIContext.FocusedElement != null;
			if (!screenUIConsumed && mInputSubsystem?.InputManager?.Mouse != null)
			{
				let mouse = mInputSubsystem.InputManager.Mouse;
				let hitElement = mUIContext.HitTest(mouse.X, mouse.Y);
				screenUIConsumed = hitElement != null && hitElement != mUIContext.RootElement;
			}

			if (screenUIConsumed)
			{
				if (mInputSubsystem != null)
					mInputSubsystem.UIConsumedInput = true;
			}
			else
			{
				// Route input to world-space panels if screen UI didn't consume it
				RouteWorldPanelInput();
			}

			// Update cursor
			UpdateCursor();
		}
	}

	/// Override to perform UI subsystem initialization.
	protected override void OnInit()
	{
		mInputSubsystem = Context.GetSubsystem<InputSubsystem>();
		SubscribeKeyboardEvents();
	}

	/// Override to perform UI subsystem shutdown.
	protected override void OnShutdown()
	{
		UnsubscribeKeyboardEvents();

		// RenderSystem owns the feature and deletes it during Shutdown.
		// Just null our reference.
		mWorldSpaceUIFeature = null;
		mRenderSystem = null;

		if (mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
			mDrawingRenderer = null;
		}

		if (mDrawContext != null)
		{
			delete mDrawContext;
			mDrawContext = null;
		}

		if (mTheme != null)
		{
			delete mTheme;
			mTheme = null;
		}

		if (mClipboardAdapter != null)
		{
			delete mClipboardAdapter;
			mClipboardAdapter = null;
		}

		if (mUIContext != null)
		{
			delete mUIContext;
			mUIContext = null;
		}

		if (mKeyEventDelegate != null)
		{
			delete mKeyEventDelegate;
			mKeyEventDelegate = null;
		}

		if (mTextInputDelegate != null)
		{
			delete mTextInputDelegate;
			mTextInputDelegate = null;
		}

		mRenderingInitialized = false;
	}

	/// Initialize rendering resources. Call this after the device is ready.
	/// Creates the DrawingRenderer, DrawContext, FontService, and default theme.
	/// Automatically sets up clipboard from the shell.
	/// If renderSystem is provided, registers the WorldSpaceUIFeature for world-space UI panels.
	public Result<void> InitializeRendering(IDevice device, TextureFormat targetFormat, int32 frameCount, IShell shell, RenderSystem renderSystem = null)
	{
		mDevice = device;
		mFrameCount = frameCount;
		mRenderSystem = renderSystem;
		mUIContext = new UIContext();

		mDrawingRenderer = new DrawingRenderer();
		if (mDrawingRenderer.Initialize(device, targetFormat, frameCount, renderSystem?.ShaderSystem) case .Err)
		{
			delete mDrawingRenderer;
			mDrawingRenderer = null;
			return .Err;
		}

		mDrawContext = new DrawContext(mFontService);
		mUIContext.RegisterService<IFontService>(mFontService);

		// Create and register default theme
		mTheme = new DefaultTheme();
		mUIContext.RegisterService<ITheme>(mTheme);

		// Set up clipboard from shell
		if (shell.Clipboard != null)
		{
			mClipboardAdapter = new ShellClipboardAdapter(shell.Clipboard);
			mUIContext.RegisterClipboard(mClipboardAdapter);
		}

		// Register world-space UI feature with the render system
		if (renderSystem != null)
		{
			mWorldSpaceUIFeature = new WorldSpaceUIFeature();
			renderSystem.RegisterFeature(mWorldSpaceUIFeature);
		}

		mRenderingInitialized = true;
		return .Ok;
	}

	/// Render UI overlay. Call this after the 3D scene has been rendered.
	/// Creates a render pass with Load attachment to preserve existing content.
	public void RenderUI(ICommandEncoder encoder, ITextureView targetView, uint32 width, uint32 height, int32 frameIndex)
	{
		mViewportWidth = width;
		mViewportHeight = height;

		if (!mRenderingInitialized || mUIContext.RootElement == null)
			return;

		using (SProfiler.Begin("UI.RenderScreen"))
		{
			mUIContext.SetViewportSize((float)width, (float)height);

			// Build geometry
			mDrawContext.Clear();
			mUIContext.Render(mDrawContext);
			let batch = mDrawContext.GetBatch();
			if (batch == null || batch.Commands.Count == 0)
				return;

			// Upload to GPU
			mDrawingRenderer.UpdateProjection(width, height, frameIndex);
			mDrawingRenderer.Prepare(batch, frameIndex);

			// Create overlay render pass (Load = preserve 3D scene)
			RenderPassColorAttachment[1] colorAttachments = .(.()
			{
				View = targetView,
				ResolveTarget = null,
				LoadOp = .Load,
				StoreOp = .Store,
				ClearValue = .(0, 0, 0, 1)
			});
			RenderPassDescriptor passDesc = .(colorAttachments);

			let renderPass = encoder.BeginRenderPass(&passDesc);
			if (renderPass != null)
			{
				mDrawingRenderer.Render(renderPass, width, height, frameIndex);
				renderPass.End();
				delete renderPass;
			}
		}
	}

	// ==================== Input Routing ====================

	private void RouteMouseInput()
	{
		using (SProfiler.Begin("UI.RouteInput"))
		{
		if (mInputSubsystem == null)
			return;

		let inputManager = mInputSubsystem.InputManager;
		if (inputManager == null)
			return;

		let mouse = inputManager.Mouse;
		if (mouse == null)
			return;

		let keyboard = inputManager.Keyboard;
		let mods = keyboard != null ? InputMapping.MapModifiers(keyboard.Modifiers) : Sedulous.UI.KeyModifiers.None;

		let mx = mouse.X;
		let my = mouse.Y;

		// Mouse movement
		if (mouse.DeltaX != 0 || mouse.DeltaY != 0)
			mUIContext.ProcessMouseMove(mx, my, mods);

		// Mouse buttons
		CheckMouseButton(mouse, .Left, mx, my, mods);
		CheckMouseButton(mouse, .Right, mx, my, mods);
		CheckMouseButton(mouse, .Middle, mx, my, mods);

		// Scroll
		if (mouse.ScrollX != 0 || mouse.ScrollY != 0)
			mUIContext.ProcessMouseWheel(mouse.ScrollX, mouse.ScrollY, mx, my, mods);
		}
	}

	private void CheckMouseButton(IMouse mouse, Sedulous.Shell.Input.MouseButton shellButton, float x, float y, Sedulous.UI.KeyModifiers mods)
	{
		let uiButton = InputMapping.MapMouseButton(shellButton);
		if (mouse.IsButtonPressed(shellButton))
			mUIContext.ProcessMouseDown(uiButton, x, y, mods);
		else if (mouse.IsButtonReleased(shellButton))
			mUIContext.ProcessMouseUp(uiButton, x, y, mods);
	}

	private void UpdateCursor()
	{
		if (mInputSubsystem == null)
			return;

		let inputManager = mInputSubsystem.InputManager;
		if (inputManager == null)
			return;

		let mouse = inputManager.Mouse;
		if (mouse == null)
			return;

		// Check world panels first - if a world panel is hovered, use its cursor
		var cursor = Sedulous.UI.CursorType.Default;
		bool worldPanelHovered = false;
		for (let module in mSceneModules)
		{
			if (module.HoveredPanel != null)
			{
				cursor = module.HoveredPanel.UIContext.CurrentCursor;
				worldPanelHovered = true;
				break;
			}
		}

		// If no world panel is hovered, use screen-space UI cursor
		if (!worldPanelHovered)
			cursor = mUIContext.CurrentCursor;

		let shellCursor = InputMapping.MapCursor(cursor);
		mouse.Cursor = shellCursor;
	}

	// ==================== Keyboard Events ====================

	private void SubscribeKeyboardEvents()
	{
		if (mInputSubsystem == null)
			return;

		let inputManager = mInputSubsystem.InputManager;
		if (inputManager == null)
			return;

		let keyboard = inputManager.Keyboard;
		if (keyboard == null)
			return;

		mKeyEventDelegate = new => OnKeyEvent;
		keyboard.OnKeyEvent.Subscribe(mKeyEventDelegate);

		mTextInputDelegate = new => OnTextInput;
		keyboard.OnTextInput.Subscribe(mTextInputDelegate);
	}

	private void UnsubscribeKeyboardEvents()
	{
		if (mInputSubsystem == null)
			return;

		let inputManager = mInputSubsystem.InputManager;
		if (inputManager == null)
			return;

		let keyboard = inputManager.Keyboard;
		if (keyboard == null)
			return;

		if (mKeyEventDelegate != null)
			keyboard.OnKeyEvent.Unsubscribe(mKeyEventDelegate, false);

		if (mTextInputDelegate != null)
			keyboard.OnTextInput.Unsubscribe(mTextInputDelegate, false);
	}

	private void OnKeyEvent(Sedulous.Shell.Input.KeyCode key, bool down)
	{
		if (!mRenderingInitialized)
			return;

		let uiKey = InputMapping.MapKey(key);
		let keyboard = mInputSubsystem?.InputManager?.Keyboard;
		let mods = keyboard != null ? InputMapping.MapModifiers(keyboard.Modifiers) : Sedulous.UI.KeyModifiers.None;

		if (down)
			mUIContext.ProcessKeyDown(uiKey, 0, mods, false);
		else
			mUIContext.ProcessKeyUp(uiKey, 0, mods);
	}

	private void OnTextInput(StringView text)
	{
		if (!mRenderingInitialized)
			return;

		for (let c in text.DecodedChars)
			mUIContext.ProcessTextInput(c);
	}

	// ==================== World Panel Input ====================

	private void RouteWorldPanelInput()
	{
		if (mInputSubsystem == null || mViewportWidth == 0 || mViewportHeight == 0)
			return;

		let inputManager = mInputSubsystem.InputManager;
		if (inputManager == null)
			return;

		let mouse = inputManager.Mouse;
		if (mouse == null)
			return;

		let keyboard = inputManager.Keyboard;

		for (let module in mSceneModules)
			module.ProcessWorldInput(mouse, keyboard, mViewportWidth, mViewportHeight);
	}

	// ==================== ISceneAware ====================

	public void OnSceneCreated(Scene scene)
	{
		let module = new UISceneModule(this);
		scene.AddModule(module);
		mSceneModules.Add(module);
	}

	public void OnSceneDestroyed(Scene scene)
	{
		// Remove module reference (scene owns and deletes the module)
		let module = scene.GetModule<UISceneModule>();
		if (module != null)
			mSceneModules.Remove(module);
	}
}
