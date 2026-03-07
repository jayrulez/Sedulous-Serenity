namespace Sedulous.Engine.UI;

using System;
using System.Collections;
using Sedulous.Runtime;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Input;
using Sedulous.GUI;
using Sedulous.GUI.Shell;
using Sedulous.Drawing;
using Sedulous.Drawing.Renderer;
using Sedulous.Drawing.Fonts;
using Sedulous.Fonts;
using Sedulous.RHI;
using Sedulous.Render;
using Sedulous.Shell.Input;
using Sedulous.Profiler;
using Sedulous.Shaders;

/// Engine-layer subsystem for world-space UI panels.
/// Manages UISceneModule per scene and WorldSpaceUIFeature.
/// Optionally shares FontService/Theme/ShaderSystem from GUI.Runtime.UISubsystem if registered.
public class WorldUISubsystem : Subsystem, ISceneAware
{
	/// Updates after screen UI (400).
	public override int32 UpdateOrder => 401;

	// World-space UI
	private WorldSpaceUIFeature mWorldSpaceUIFeature;
	private RenderSystem mRenderSystem;
	private int32 mFrameCount;
	private List<UISceneModule> mSceneModules = new .() ~ delete _;
	private uint32 mViewportWidth;
	private uint32 mViewportHeight;

	// Resources (shared from UISubsystem or owned)
	private IDevice mDevice;
	private IFontService mFontService;
	private bool mOwnsFontService;
	private ShaderSystem mShaderSystem;
	private ITheme mTheme;
	private bool mOwnsTheme;

	// Dependencies
	private InputSubsystem mInputSubsystem;

	/// The GPU device.
	public IDevice Device => mDevice;

	/// The font service (shared from UISubsystem or owned).
	public IFontService FontService => mFontService;

	/// The shader system.
	public ShaderSystem ShaderSystem => mShaderSystem;

	/// The theme.
	public ITheme Theme => mTheme;

	/// The render system.
	public RenderSystem RenderSystem => mRenderSystem;

	/// The world-space UI render feature.
	public WorldSpaceUIFeature WorldSpaceUIFeature => mWorldSpaceUIFeature;

	/// Number of in-flight frames.
	public int32 FrameCount => mFrameCount;

	public this()
	{
	}

	/// Initialize world-space UI rendering.
	/// Call after the device and render system are ready.
	public Result<void> InitializeRendering(IDevice device, TextureFormat targetFormat, int32 frameCount, RenderSystem renderSystem)
	{
		mDevice = device;
		mFrameCount = frameCount;
		mRenderSystem = renderSystem;

		// Register WorldSpaceUIFeature with the render system
		if (renderSystem != null)
		{
			mWorldSpaceUIFeature = new WorldSpaceUIFeature();
			renderSystem.RegisterFeature(mWorldSpaceUIFeature);
		}

		return .Ok;
	}

	protected override void OnInit()
	{
		mInputSubsystem = Context.GetSubsystem<InputSubsystem>();

		// Try to share resources from screen-space UISubsystem
		let screenUI = Context.GetSubsystem<Sedulous.GUI.Runtime.UISubsystem>();
		if (screenUI != null)
		{
			mFontService = screenUI.FontService;
			mShaderSystem = screenUI.ShaderSystem;
			mTheme = screenUI.Theme;
		}
		else
		{
			// Create own resources for world-only scenarios
			let ownedFont = new FontService();
			mFontService = ownedFont;
			mOwnsFontService = true;

			mTheme = new DarkTheme();
			mOwnsTheme = true;

			// Use RenderSystem's ShaderSystem if available
			mShaderSystem = mRenderSystem?.ShaderSystem;
		}
	}

	public override void Update(float deltaTime)
	{
		using (SProfiler.Begin("WorldUI.Update"))
		{
			// Bridge input consumption from screen UI to InputSubsystem
			if (mInputSubsystem != null)
			{
				let screenUI = Context.GetSubsystem<Sedulous.GUI.Runtime.UISubsystem>();
				if (screenUI != null && screenUI.UIConsumedInput)
				{
					mInputSubsystem.UIConsumedInput = true;
				}
				else
				{
					// Route input to world-space panels if screen UI didn't consume it
					RouteWorldPanelInput();

					// Check if any world panel is hovered
					bool worldConsumed = false;
					for (let module in mSceneModules)
					{
						if (module.HoveredPanel != null)
						{
							worldConsumed = true;
							break;
						}
					}
					if (worldConsumed)
						mInputSubsystem.UIConsumedInput = true;
				}

				// Update cursor for world panels
				UpdateCursor();
			}
		}
	}

	protected override void OnShutdown()
	{
		// RenderSystem owns the feature and deletes it during Shutdown.
		mWorldSpaceUIFeature = null;
		mRenderSystem = null;

		if (mOwnsFontService && mFontService != null)
		{
			delete (FontService)mFontService;
			mFontService = null;
		}

		if (mOwnsTheme && mTheme != null)
		{
			delete mTheme;
			mTheme = null;
		}
	}

	// ==================== Input Routing ====================

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

		// Check world panels for hover cursor
		for (let module in mSceneModules)
		{
			if (module.HoveredPanel != null)
			{
				let cursor = module.HoveredPanel.GUIContext.CurrentCursor;
				let shellCursor = InputMapping.MapCursor(cursor);
				mouse.Cursor = shellCursor;
				return;
			}
		}
	}

	/// Sets the viewport dimensions used for world panel raycasting.
	public void SetViewportSize(uint32 width, uint32 height)
	{
		mViewportWidth = width;
		mViewportHeight = height;
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
