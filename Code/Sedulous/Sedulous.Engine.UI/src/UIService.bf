namespace Sedulous.Engine.UI;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Engine.Input;
using Sedulous.RHI;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Shaders;
using Sedulous.Shell.Input;

/// Context service for UI management across all scenes.
/// Holds shared UI configuration and automatically creates UISceneComponent for each scene.
///
/// Required dependencies (must be registered before UIService):
/// - RendererService: For GPU device access and rendering
/// - InputService: For input routing to UI (optional but recommended)
class UIService : ContextService
{
	/// UI should process input and layout after game logic, before rendering.
	public override int32 UpdateOrder => 450;

	private Context mContext;

	// Dependencies (looked up on Startup)
	private RendererService mRendererService;
	private InputService mInputService;

	// Shared configuration
	private IFontService mFontService;
	private ITheme mTheme;
	private IClipboard mClipboard;
	private ITextureView mAtlasTexture;
	private Vector2 mWhitePixelUV;
	private NewShaderSystem mShaderSystem;

	// Track created scene components
	private List<UISceneComponent> mSceneComponents = new .() ~ delete _;

	// ==================== Properties ====================

	/// Gets the font service for UI text rendering.
	public IFontService FontService => mFontService;

	/// Gets the UI theme.
	public ITheme Theme => mTheme;

	/// Gets the clipboard service.
	public IClipboard Clipboard => mClipboard;

	/// Gets the atlas texture for fonts/icons.
	public ITextureView AtlasTexture => mAtlasTexture;

	/// Gets the white pixel UV for solid color rendering.
	public Vector2 WhitePixelUV => mWhitePixelUV;

	/// Gets the input manager from InputService.
	public IInputManager InputManager => mInputService?.InputManager;

	/// Gets the graphics device from RendererService.
	public IDevice Device => mRendererService?.Device;

	/// Gets all UISceneComponents created by this service.
	public Span<UISceneComponent> SceneComponents => mSceneComponents;

	// ==================== Configuration ====================

	/// Sets the font service (shared across all scenes).
	public void SetFontService(IFontService fontService)
	{
		mFontService = fontService;
	}

	/// Sets the UI theme (shared across all scenes).
	public void SetTheme(ITheme theme)
	{
		mTheme = theme;
	}

	/// Sets the clipboard service (shared across all scenes).
	public void SetClipboard(IClipboard clipboard)
	{
		mClipboard = clipboard;
	}

	/// Sets the atlas texture for fonts/icons.
	public void SetAtlasTexture(ITextureView atlas, Vector2 whitePixelUV)
	{
		mAtlasTexture = atlas;
		mWhitePixelUV = whitePixelUV;

		// Update existing components
		for (let component in mSceneComponents)
		{
			component.SetAtlasTexture(atlas);
			component.SetWhitePixelUV(whitePixelUV);
		}
	}

	/// Sets the shader system for drawing shader loading.
	public void SetShaderSystem(NewShaderSystem shaderSystem)
	{
		mShaderSystem = shaderSystem;
	}

	/// Sets the UI scale for all scenes based on display content scale (DPI).
	/// Call this at startup with window.ContentScale and again when
	/// DisplayScaleChanged events are received.
	/// @param contentScale The display content scale (1.0 = 100%, 1.5 = 150%, 2.0 = 200%)
	public void SetContentScale(float contentScale)
	{
		for (let component in mSceneComponents)
		{
			component.UIContext.Scale = contentScale;
		}
	}

	/// Convenience method to apply content scale from a window.
	/// Call at startup and when DisplayScaleChanged events occur.
	public void ApplyContentScaleFromWindow(Sedulous.Shell.IWindow window)
	{
		SetContentScale(window.ContentScale);
	}

	// ==================== ContextService Implementation ====================

	public override void OnRegister(Context context)
	{
		mContext = context;
	}

	public override void OnUnregister()
	{
		mContext = null;
		mRendererService = null;
		mInputService = null;
	}

	public override void Startup()
	{
		// Look up dependencies
		mRendererService = mContext?.GetService<RendererService>();
		mInputService = mContext?.GetService<InputService>();

		if (mRendererService == null)
			mContext?.Logger?.LogWarning("UIService: RendererService not found - UI rendering will not work");

		if (mInputService == null)
			mContext?.Logger?.LogWarning("UIService: InputService not found - UI input will not work");
	}

	public override void Shutdown()
	{
		// Scene components are cleaned up by Scene destruction
		mSceneComponents.Clear();
	}

	public override void Update(float deltaTime)
	{
		// Per-frame updates are handled by UISceneComponent
	}

	public override void OnSceneCreated(Scene scene)
	{
		// Check renderer dependency
		if (mRendererService == null || !mRendererService.IsInitialized)
		{
			mContext?.Logger?.LogWarning("UIService: RendererService not available, skipping UISceneComponent for scene '{}'", scene.Name);
			return;
		}

		// Create UISceneComponent
		let uiComponent = new UISceneComponent();
		scene.AddSceneComponent(uiComponent);
		mSceneComponents.Add(uiComponent);

		// Initialize rendering (use renderer's color format, double-buffered)
		if (uiComponent.InitializeRendering(mRendererService.Device, mRendererService.ColorFormat, 2, mShaderSystem) case .Err)
		{
			mContext?.Logger?.LogError("UIService: Failed to initialize UI rendering for scene '{}'", scene.Name);
			scene.RemoveSceneComponent<UISceneComponent>();
			mSceneComponents.Remove(uiComponent);
			return;
		}

		// Apply shared configuration
		if (mAtlasTexture != null)
		{
			uiComponent.SetAtlasTexture(mAtlasTexture);
			uiComponent.SetWhitePixelUV(mWhitePixelUV);
		}

		// Register services with UIContext
		let uiContext = uiComponent.UIContext;
		if (mFontService != null)
			uiContext.RegisterService<IFontService>(mFontService);
		if (mTheme != null)
			uiContext.RegisterService<ITheme>(mTheme);
		if (mClipboard != null)
			uiContext.RegisterClipboard(mClipboard);

		mContext?.Logger?.LogDebug("UIService: Added UISceneComponent to scene '{}'", scene.Name);
	}

	public override void OnSceneDestroyed(Scene scene)
	{
		// Find and remove component belonging to this scene
		for (int i = mSceneComponents.Count - 1; i >= 0; i--)
		{
			let component = mSceneComponents[i];
			if (component.Scene == scene)
			{
				mSceneComponents.RemoveAt(i);
				// Note: Scene will delete the component
				break;
			}
		}
	}
}
