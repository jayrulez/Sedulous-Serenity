using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.UI;
using Sedulous.UI.FontRenderer;
using Sedulous.Framework.Core;
using Sedulous.Framework.Renderer;

namespace Sedulous.Framework.UI;

/// Scene component for rendering UI elements.
/// Manages all UIComponents in the scene and renders them.
class UISceneComponent : ISceneComponent
{
	private Scene mScene;
	private FontManager mFontManager ~ delete _;
	private GameUIBackend mBackend ~ delete _;
	private List<UIComponent> mUIComponents = new .() ~ delete _;
	private List<UIComponent> mScreenSpaceUI = new .() ~ delete _;
	private List<UIComponent> mWorldSpaceUI = new .() ~ delete _;
	private bool mInitialized = false;

	/// Gets the font manager for this scene.
	public FontManager FontManager => mFontManager;

	/// Gets the UI backend.
	public GameUIBackend Backend => mBackend;

	/// Gets the registered UI components.
	public List<UIComponent> UIComponents => mUIComponents;

	/// Gets whether the component has been initialized.
	public bool IsInitialized => mInitialized;

	// ============ ISceneComponent Implementation ============

	public void OnAttach(Scene scene)
	{
		mScene = scene;
		Initialize();
	}

	public void OnDetach()
	{
		mScene = null;
		mInitialized = false;
	}

	public void OnUpdate(float deltaTime)
	{
		// UI components update themselves via their OnUpdate
		// We just need to sort for rendering
		mScreenSpaceUI.Clear();
		mWorldSpaceUI.Clear();

		for (let ui in mUIComponents)
		{
			if (ui.IsVisible)
			{
				if (ui.ScreenSpace)
					mScreenSpaceUI.Add(ui);
				else
					mWorldSpaceUI.Add(ui);
			}
		}
	}

	public void OnSceneStateChanged(SceneState oldState, SceneState newState)
	{
		// Handle scene state changes if needed
	}

	// ============ ISerializable Implementation ============

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		// UI scene component doesn't serialize much state
		return .Ok;
	}

	// ============ Initialization ============

	private void Initialize()
	{
		if (mInitialized)
			return;

		// Create font manager
		mFontManager = new FontManager();
		mFontManager.SetAtlasSize(1024, 1024);

		// Backend is created lazily when renderer is available
		mInitialized = true;
	}

	/// Initializes with renderer service (call after renderer is available).
	public void InitializeWithRenderer(RendererService renderer)
	{
		if (mBackend != null || renderer == null)
			return;

		mBackend = new GameUIBackend(renderer, mFontManager);
	}

	// ============ Component Management ============

	/// Registers a UI component with this scene component.
	public void Register(UIComponent component)
	{
		if (!mUIComponents.Contains(component))
		{
			mUIComponents.Add(component);
		}
	}

	/// Unregisters a UI component.
	public void Unregister(UIComponent component)
	{
		mUIComponents.Remove(component);
		mScreenSpaceUI.Remove(component);
		mWorldSpaceUI.Remove(component);
	}

	// ============ Rendering ============

	/// Renders all screen-space UI elements.
	public void Render(Vector2 viewportSize)
	{
		if (!mInitialized)
			return;

		// Update and render screen-space UI
		for (let ui in mScreenSpaceUI)
		{
			RenderUI(ui, viewportSize);
		}
	}

	private void RenderUI(UIComponent ui, Vector2 viewportSize)
	{
		if (ui.UI.Root == null)
			return;

		// Set viewport size
		ui.UI.ViewportSize = viewportSize;

		// The actual rendering is done by the UI context
		// This would integrate with the GPU renderer in a full implementation
	}

	// ============ Input Handling ============

	/// Processes a mouse move event for all screen-space UI.
	public bool ProcessMouseMove(Vector2 position)
	{
		for (let ui in mScreenSpaceUI)
		{
			ui.UI.InjectMouseMove(position);
		}
		return false;
	}

	/// Processes a mouse button event for all screen-space UI.
	public bool ProcessMouseButton(MouseButton button, bool pressed)
	{
		for (let ui in mScreenSpaceUI)
		{
			ui.UI.InjectMouseButton(button, pressed);
		}
		return false;
	}

	/// Processes text input for focused UI.
	public bool ProcessTextInput(StringView text)
	{
		for (let ui in mScreenSpaceUI)
		{
			ui.UI.InjectTextInput(text);
		}
		return false;
	}
}
