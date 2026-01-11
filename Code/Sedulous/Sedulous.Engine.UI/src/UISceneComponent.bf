namespace Sedulous.Engine.UI;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;
using Sedulous.Drawing;
using Sedulous.UI;
using Sedulous.UI.Renderer;

/// Scene component that manages screen-space overlay UI for a scene.
/// Owns a UIContext for the main UI tree, DrawContext for building geometry,
/// and UIRenderer for GPU rendering.
class UISceneComponent : ISceneComponent
{
	private Scene mScene;

	// UI system
	private UIContext mUIContext ~ delete _;
	private DrawContext mDrawContext ~ delete _;

	// GPU rendering
	private UIRenderer mUIRenderer ~ delete _;
	private bool mRenderingInitialized = false;

	// Viewport state
	private uint32 mWidth;
	private uint32 mHeight;

	// Texture atlas for fonts/icons
	private ITextureView mAtlasTextureView;

	// World-space UI components (managed by this scene component)
	private List<UIComponent> mWorldUIComponents = new .() ~ delete _;

	// ==================== Properties ====================

	/// Gets the UI context for this scene.
	public UIContext UIContext => mUIContext;

	/// Gets the root element of the UI tree.
	public UIElement RootElement
	{
		get => mUIContext?.RootElement;
		set
		{
			if (mUIContext != null)
				mUIContext.RootElement = value;
		}
	}

	/// Gets the current viewport width.
	public uint32 Width => mWidth;

	/// Gets the current viewport height.
	public uint32 Height => mHeight;

	/// Gets whether rendering has been initialized.
	public bool IsRenderingInitialized => mRenderingInitialized;

	/// Gets the scene this component is attached to.
	public Scene Scene => mScene;

	// ==================== ISceneComponent Implementation ====================

	public void OnAttach(Scene scene)
	{
		mScene = scene;

		// Create UI context
		mUIContext = new UIContext();

		// Create draw context for building geometry
		mDrawContext = new DrawContext();
	}

	public void OnDetach()
	{
		Console.WriteLine("UISceneComponent.OnDetach() called");

		// Notify all world UI components that we're going away.
		// This prevents them from trying to unregister during their OnDetach
		// (which would access deleted memory).
		for (let component in mWorldUIComponents)
			component.ClearUISceneReference();
		mWorldUIComponents.Clear();

		CleanupRendering();
		mScene = null;
	}

	public void OnUpdate(float deltaTime)
	{
		if (mUIContext == null)
			return;

		// Get total time from system if available
		double totalTime = 0;
		if (mUIContext.SystemServices != null)
			totalTime = mUIContext.SystemServices.CurrentTime;

		// Update UI context (layout, animations, etc.)
		mUIContext.Update(deltaTime, totalTime);

		// Update world-space UI components
		for (let component in mWorldUIComponents)
		{
			if (component.Visible)
				component.OnUpdate(deltaTime);
		}
	}

	public void OnSceneStateChanged(SceneState oldState, SceneState newState)
	{
		Console.WriteLine(scope $"UISceneComponent.OnSceneStateChanged({oldState} -> {newState})");
		if (newState == .Unloaded)
		{
			CleanupRendering();
		}
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// UISceneComponent doesn't serialize its UI state - it's recreated at runtime
		return .Ok;
	}

	// ==================== Rendering Initialization ====================

	/// Initializes GPU rendering resources.
	/// Call this after the swap chain is created.
	public Result<void> InitializeRendering(IDevice device, TextureFormat format, int32 frameCount)
	{
		if (mRenderingInitialized)
			return .Ok;

		// Create UI renderer
		mUIRenderer = new UIRenderer();
		if (mUIRenderer.Initialize(device, format, frameCount) case .Err)
		{
			delete mUIRenderer;
			mUIRenderer = null;
			return .Err;
		}

		mRenderingInitialized = true;
		return .Ok;
	}

	/// Sets the texture atlas for UI rendering (fonts, icons, etc.).
	public void SetAtlasTexture(ITextureView atlasTextureView)
	{
		mAtlasTextureView = atlasTextureView;
	}

	/// Sets the white pixel UV coordinates for solid color rendering.
	/// These coordinates should point to a white pixel in the atlas texture.
	public void SetWhitePixelUV(Vector2 uv)
	{
		if (mDrawContext != null)
			mDrawContext.WhitePixelUV = uv;
	}

	/// Sets the viewport size for UI layout.
	public void SetViewportSize(uint32 width, uint32 height)
	{
		if (mWidth != width || mHeight != height)
		{
			mWidth = width;
			mHeight = height;

			if (mUIContext != null)
				mUIContext.SetViewportSize((float)width, (float)height);
		}
	}

	private void CleanupRendering()
	{
		Console.WriteLine("UISceneComponent.CleanupRendering() called");
		if (mUIRenderer != null)
		{
			Console.WriteLine("  Calling mUIRenderer.Dispose()");
			mUIRenderer.Dispose();
			Console.WriteLine("  Deleting mUIRenderer");
			delete mUIRenderer;
			mUIRenderer = null;
		}
		mRenderingInitialized = false;
		Console.WriteLine("UISceneComponent.CleanupRendering() done");
	}

	// ==================== Frame Rendering ====================

	/// Prepares UI geometry for GPU rendering.
	/// Call this in OnPrepareFrame after layout is complete.
	public void PrepareGPU(int32 frameIndex)
	{
		if (!mRenderingInitialized || mUIContext == null || mUIRenderer == null)
			return;

		// Clear the draw context
		mDrawContext.Clear();

		// Render UI to draw context
		mUIContext.Render(mDrawContext);

		// Get the batch and prepare for GPU
		let batch = mDrawContext.GetBatch();

		// Set texture atlas
		if (mAtlasTextureView != null)
			mUIRenderer.SetTexture(mAtlasTextureView);

		// Update projection matrix first (matches UISandbox order)
		mUIRenderer.UpdateProjection(mWidth, mHeight, frameIndex);

		// Upload to GPU buffers
		mUIRenderer.Prepare(batch, frameIndex);
	}

	/// Renders the UI overlay to the render pass.
	/// Call this AFTER the 3D scene has been rendered.
	public void Render(IRenderPassEncoder renderPass, uint32 width, uint32 height, int32 frameIndex)
	{
		if (!mRenderingInitialized || mUIRenderer == null)
			return;

		mUIRenderer.Render(renderPass, width, height, frameIndex);
	}

	// ==================== Input Handling ====================

	// Last known mouse position for input routing
	private float mLastMouseX;
	private float mLastMouseY;

	/// Routes mouse move events to the UI.
	public void OnMouseMove(float x, float y, KeyModifiers modifiers = .None)
	{
		if (mUIContext == null)
			return;

		mLastMouseX = x;
		mLastMouseY = y;
		mUIContext.InputManager?.ProcessMouseMove(x, y, modifiers);
	}

	/// Routes mouse button press events to the UI.
	public void OnMouseDown(MouseButton button, float x, float y, KeyModifiers modifiers = .None)
	{
		if (mUIContext == null)
			return;

		mLastMouseX = x;
		mLastMouseY = y;
		mUIContext.InputManager?.ProcessMouseDown(button, x, y, modifiers);
	}

	/// Routes mouse button release events to the UI.
	public void OnMouseUp(MouseButton button, float x, float y, KeyModifiers modifiers = .None)
	{
		if (mUIContext == null)
			return;

		mLastMouseX = x;
		mLastMouseY = y;
		mUIContext.InputManager?.ProcessMouseUp(button, x, y, modifiers);
	}

	/// Routes mouse wheel events to the UI.
	public void OnMouseWheel(float deltaX, float deltaY, KeyModifiers modifiers = .None)
	{
		if (mUIContext == null)
			return;

		mUIContext.InputManager?.ProcessMouseWheel(deltaX, deltaY, mLastMouseX, mLastMouseY, modifiers);
	}

	/// Routes key down events to the UI.
	public void OnKeyDown(KeyCode key, int32 scanCode = 0, KeyModifiers modifiers = .None, bool isRepeat = false)
	{
		if (mUIContext == null)
			return;

		mUIContext.InputManager?.ProcessKeyDown(key, scanCode, modifiers, isRepeat);
	}

	/// Routes key up events to the UI.
	public void OnKeyUp(KeyCode key, int32 scanCode = 0, KeyModifiers modifiers = .None)
	{
		if (mUIContext == null)
			return;

		mUIContext.InputManager?.ProcessKeyUp(key, scanCode, modifiers);
	}

	/// Routes text input events to the UI.
	public void OnTextInput(char32 character)
	{
		if (mUIContext == null)
			return;

		mUIContext.InputManager?.ProcessTextInput(character);
	}

	// ==================== World-Space UI Management ====================

	/// Registers a world-space UI component.
	/// Called by UIComponent.OnAttach.
	public void RegisterWorldUI(UIComponent component)
	{
		if (!mWorldUIComponents.Contains(component))
			mWorldUIComponents.Add(component);
	}

	/// Unregisters a world-space UI component.
	/// Called by UIComponent.OnDetach.
	public void UnregisterWorldUI(UIComponent component)
	{
		mWorldUIComponents.Remove(component);
	}

	/// Gets the list of registered world-space UI components.
	public Span<UIComponent> WorldUIComponents => mWorldUIComponents;

	/// Prepares world-space UI components for GPU rendering.
	/// Call this during the PrepareGPU phase.
	public void PrepareWorldUIComponents(int32 frameIndex)
	{
		for (let component in mWorldUIComponents)
		{
			if (component.Visible && component.IsRenderingInitialized)
				component.PrepareGPU(frameIndex, mAtlasTextureView);
		}
	}

	/// Renders world-space UI components to their render textures.
	/// Call this before the main render pass.
	public void RenderWorldUIToTextures(ICommandEncoder encoder, int32 frameIndex)
	{
		for (let component in mWorldUIComponents)
		{
			if (component.Visible && component.IsRenderingInitialized)
				component.RenderToTexture(encoder, frameIndex);
		}
	}
}
