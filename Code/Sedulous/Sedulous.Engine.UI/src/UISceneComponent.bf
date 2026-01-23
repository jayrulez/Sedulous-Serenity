namespace Sedulous.Engine.UI;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Engine.Input;
using Sedulous.Engine.Renderer;
using Sedulous.Logging.Abstractions;
using Sedulous.Shell.Input;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Renderer;
using Sedulous.Serialization;
using Sedulous.Drawing;
using Sedulous.UI;
using Sedulous.UI.Shell;
using Sedulous.UI.Renderer;

// Use UI types explicitly to avoid ambiguity with Shell types
typealias UIKeyCode = Sedulous.UI.KeyCode;
typealias UIKeyModifiers = Sedulous.UI.KeyModifiers;
typealias UIMouseButton = Sedulous.UI.MouseButton;

/// Scene component that manages screen-space overlay UI for a scene.
/// Owns a UIContext for the main UI tree, DrawContext for building geometry,
/// and UIRenderer for GPU rendering.
/// Automatically routes input from InputService to the UI.
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

	// Input routing
	private delegate void(StringView) mTextInputDelegate ~ delete _;
	private bool mInputSubscribed = false;
	private float mPrevMouseX;
	private float mPrevMouseY;

	// World UI input state
	private UIComponent mHoveredWorldUI;
	private UIComponent mFocusedWorldUI;
	private Vector2 mWorldUILocalPos;  // Last local position on hovered world UI

	// Logging state (to avoid spam)
	private bool mInputServiceWarningLogged = false;

	// Cursor state
	private Sedulous.UI.CursorType mLastCursor = .Default;

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

		// Unsubscribe from text input
		UnsubscribeFromInput();

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

		// Route input from InputService
		RouteInput();

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

	// ==================== Render Graph Integration ====================

	/// Adds UI overlay pass to the render graph.
	/// Called by RenderSceneComponent.AddRenderPasses().
	public void AddUIPass(RenderGraph graph, ResourceHandle swapChain, int32 frameIndex)
	{
		if (!mRenderingInitialized || mUIRenderer == null)
			return;

		// Prepare UI geometry
		PrepareGPU(frameIndex);

		// Prepare world UI components
		PrepareWorldUIComponents(frameIndex);

		// Capture state for lambda
		let renderer = mUIRenderer;
		let width = mWidth;
		let height = mHeight;

		// Add UI overlay pass (after Scene3D)
		graph.AddGraphicsPass("UIOverlay")
			.AddDependency("Scene3D")
			.SetColorAttachment(0, swapChain, .Load, .Store, default)  // Preserve 3D content
			.SetExecute(new [=](ctx) => {
				renderer.Render(ctx.RenderPass, width, height, frameIndex);
			});
	}

	/// Adds world UI render-to-texture passes to the render graph.
	/// These render before the main scene pass so their textures can be sampled.
	/// Pass names are "WorldUI_0", "WorldUI_1", etc. for dependency declarations.
	/// Returns the resource handles for the world UI textures (caller can declare reads).
	public void AddWorldUIPasses(RenderGraph graph, int32 frameIndex, List<ResourceHandle> outHandles = null)
	{
		int32 index = 0;
		for (let component in mWorldUIComponents)
		{
			if (!component.Visible || !component.IsRenderingInitialized)
				continue;

			// Import world UI render texture
			let renderTex = component.RenderTexture;
			let renderView = component.RenderTextureView;
			if (renderTex == null || renderView == null)
				continue;

			// Use index-based naming for consistent dependency declarations
			String textureName = scope $"WorldUITex_{index}";
			let handle = graph.ImportTexture(textureName, renderTex, renderView, .Undefined);

			// Return handle to caller for read declarations
			outHandles?.Add(handle);

			// Capture for lambda
			let comp = component;
			let frame = frameIndex;

			// Pass name matches what Scene3D declares as dependency
			String passName = scope $"WorldUI_{index}";
			graph.AddGraphicsPass(passName)
				.SetColorAttachment(0, handle, .Clear, .Store, Color(0, 0, 0, 0))
				.Write(handle, .ColorAttachment)  // Mark as written for barrier management
				.SetExecute(new [=](ctx) => {
					// Render within the graph's render pass
					comp.RenderWithinPass(ctx.RenderPass, frame);
				});

			index++;
		}
	}

	// ==================== Frame Rendering (Legacy) ====================

	/// Prepares UI geometry for GPU rendering.
	/// Call this in OnPrepareFrame after layout is complete.
	/// Note: When using RenderGraph, this is called automatically by AddUIPass.
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
	public void OnMouseMove(float x, float y, UIKeyModifiers modifiers = .None)
	{
		if (mUIContext == null)
			return;

		mLastMouseX = x;
		mLastMouseY = y;
		mUIContext.InputManager?.ProcessMouseMove(x, y, modifiers);
	}

	/// Routes mouse button press events to the UI.
	public void OnMouseDown(UIMouseButton button, float x, float y, UIKeyModifiers modifiers = .None)
	{
		if (mUIContext == null)
			return;

		mLastMouseX = x;
		mLastMouseY = y;
		mUIContext.InputManager?.ProcessMouseDown(button, x, y, modifiers);
	}

	/// Routes mouse button release events to the UI.
	public void OnMouseUp(UIMouseButton button, float x, float y, UIKeyModifiers modifiers = .None)
	{
		if (mUIContext == null)
			return;

		mLastMouseX = x;
		mLastMouseY = y;
		mUIContext.InputManager?.ProcessMouseUp(button, x, y, modifiers);
	}

	/// Routes mouse wheel events to the UI.
	public void OnMouseWheel(float deltaX, float deltaY, UIKeyModifiers modifiers = .None)
	{
		if (mUIContext == null)
			return;

		mUIContext.InputManager?.ProcessMouseWheel(deltaX, deltaY, mLastMouseX, mLastMouseY, modifiers);
	}

	/// Routes key down events to the UI.
	public void OnKeyDown(UIKeyCode key, int32 scanCode = 0, UIKeyModifiers modifiers = .None, bool isRepeat = false)
	{
		if (mUIContext == null)
			return;

		mUIContext.InputManager?.ProcessKeyDown(key, scanCode, modifiers, isRepeat);
	}

	/// Routes key up events to the UI.
	public void OnKeyUp(UIKeyCode key, int32 scanCode = 0, UIKeyModifiers modifiers = .None)
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

	// ==================== Automatic Input Routing ====================

	/// Routes input from InputService to the UI.
	/// Called automatically during OnUpdate.
	private void RouteInput()
	{
		// Get InputService from Context
		let context = mScene?.Context;
		if (context == null)
			return;

		let inputService = context.GetService<InputService>();
		if (inputService == null)
		{
			if (!mInputServiceWarningLogged)
			{
				context.Logger?.LogWarning("UISceneComponent: InputService not registered. UI input routing disabled. Register InputService with Context before creating scenes.");
				mInputServiceWarningLogged = true;
			}
			return;
		}

		let inputManager = inputService.InputManager;
		if (inputManager == null)
			return;

		// Subscribe to text input on first use
		if (!mInputSubscribed)
			SubscribeToInput(inputManager);

		let mouse = inputManager.Mouse;
		let keyboard = inputManager.Keyboard;

		// Get current modifiers
		let mods = InputMapping.MapModifiers(keyboard.Modifiers);

		// Route mouse movement
		let mouseX = mouse.X;
		let mouseY = mouse.Y;
		if (mouseX != mPrevMouseX || mouseY != mPrevMouseY)
		{
			OnMouseMove(mouseX, mouseY, mods);
			mPrevMouseX = mouseX;
			mPrevMouseY = mouseY;
		}

		// Route mouse buttons
		if (mouse.IsButtonPressed(.Left))
			OnMouseDown(.Left, mouseX, mouseY, mods);
		if (mouse.IsButtonReleased(.Left))
			OnMouseUp(.Left, mouseX, mouseY, mods);

		if (mouse.IsButtonPressed(.Right))
			OnMouseDown(.Right, mouseX, mouseY, mods);
		if (mouse.IsButtonReleased(.Right))
			OnMouseUp(.Right, mouseX, mouseY, mods);

		if (mouse.IsButtonPressed(.Middle))
			OnMouseDown(.Middle, mouseX, mouseY, mods);
		if (mouse.IsButtonReleased(.Middle))
			OnMouseUp(.Middle, mouseX, mouseY, mods);

		// Route mouse wheel
		if (mouse.ScrollX != 0 || mouse.ScrollY != 0)
			OnMouseWheel(mouse.ScrollX, mouse.ScrollY, mods);

		// Route keyboard - check common UI keys
		RouteKeyboard(keyboard, mods);

		// Route input to world-space UI components
		RouteWorldUIInput(mouse, keyboard, mods);

		// Update cursor based on what's under the mouse
		UpdateCursor(mouse);
	}

	/// Updates the shell cursor based on the UI element under the mouse.
	private void UpdateCursor(IMouse mouse)
	{
		Sedulous.UI.CursorType uiCursor = .Default;

		// Check screen-space UI first (ignore transparent root element)
		let screenHitElement = mUIContext?.HitTest(mouse.X, mouse.Y);
		if (screenHitElement != null && screenHitElement != mUIContext.RootElement)
		{
			uiCursor = mUIContext.CurrentCursor;
		}
		else if (mHoveredWorldUI != null && mHoveredWorldUI.UIContext != null)
		{
			// Use world UI cursor if hovering over one
			uiCursor = mHoveredWorldUI.UIContext.CurrentCursor;
		}

		if (uiCursor != mLastCursor)
		{
			mLastCursor = uiCursor;
			mouse.Cursor = InputMapping.MapCursor(uiCursor);
		}
	}

	/// Routes keyboard input for common UI keys.
	private void RouteKeyboard(IKeyboard keyboard, UIKeyModifiers mods)
	{
		// Check all mappable keys
		Sedulous.Shell.Input.KeyCode[?] keysToCheck = .(
			.A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M,
			.N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z,
			.Num0, .Num1, .Num2, .Num3, .Num4, .Num5, .Num6, .Num7, .Num8, .Num9,
			.Return, .Escape, .Backspace, .Tab, .Space,
			.Left, .Right, .Up, .Down,
			.Home, .End, .PageUp, .PageDown, .Delete, .Insert
		);

		for (let shellKey in keysToCheck)
		{
			if (keyboard.IsKeyPressed(shellKey))
				OnKeyDown(InputMapping.MapKey(shellKey), 0, mods);
			if (keyboard.IsKeyReleased(shellKey))
				OnKeyUp(InputMapping.MapKey(shellKey), 0, mods);
		}
	}

	/// Subscribes to text input events from the keyboard.
	private void SubscribeToInput(IInputManager inputManager)
	{
		if (mInputSubscribed)
			return;

		mTextInputDelegate = new (text) => {
			for (let c in text.DecodedChars)
				OnTextInput(c);
		};
		inputManager.Keyboard.OnTextInput.Subscribe(mTextInputDelegate);
		mInputSubscribed = true;
	}

	/// Unsubscribes from text input events.
	private void UnsubscribeFromInput()
	{
		if (!mInputSubscribed || mTextInputDelegate == null)
			return;

		// Get InputService to unsubscribe
		let context = mScene?.Context;
		if (context != null)
		{
			let inputService = context.GetService<InputService>();
			if (inputService?.InputManager != null)
				inputService.InputManager.Keyboard.OnTextInput.Unsubscribe(mTextInputDelegate, false);
		}

		mInputSubscribed = false;
	}

	// ==================== World UI Input Routing ====================

	/// Routes input to world-space UI components via raycasting.
	/// Called automatically during RouteInput after screen-space UI.
	private void RouteWorldUIInput(IMouse mouse, IKeyboard keyboard, UIKeyModifiers mods)
	{
		// Skip if no world UI components
		if (mWorldUIComponents.Count == 0)
			return;

		// Get RenderSceneComponent for camera access
		let renderScene = mScene?.GetSceneComponent<RenderSceneComponent>();
		if (renderScene == null)
			return;

		// Get main camera
		let camera = renderScene.GetMainCameraProxy();
		if (camera == null)
			return;

		// Create ray from mouse position
		let mouseX = mouse.X;
		let mouseY = mouse.Y;
		let ray = ScreenPointToRay(mouseX, mouseY, camera);

		// Find closest world UI hit
		UIComponent closestHit = null;
		Vector2 closestLocalPos = .Zero;
		float closestDist = float.MaxValue;

		for (let component in mWorldUIComponents)
		{
			if (!component.Interactive || !component.Visible)
				continue;

			Vector2 localHit;
			if (component.Raycast(ray, out localHit))
			{
				// Calculate distance to hit point
				let entity = component.Entity;
				if (entity != null)
				{
					let dist = Vector3.Distance(camera.Position, entity.Transform.WorldPosition);
					if (dist < closestDist)
					{
						closestDist = dist;
						closestHit = component;
						closestLocalPos = localHit;
					}
				}
			}
		}

		// Handle hover changes
		if (closestHit != mHoveredWorldUI)
		{
			// Mouse left previous world UI
			if (mHoveredWorldUI != null)
			{
				// Send mouse leave event
				mHoveredWorldUI.UIContext?.InputManager?.ProcessMouseMove(-1, -1, mods);
			}

			mHoveredWorldUI = closestHit;
		}

		// Route input to hovered world UI
		if (mHoveredWorldUI != null)
		{
			mWorldUILocalPos = closestLocalPos;
			let worldUIContext = mHoveredWorldUI.UIContext;
			if (worldUIContext == null)
				return;

			// Route mouse movement
			worldUIContext.InputManager?.ProcessMouseMove(closestLocalPos.X, closestLocalPos.Y, mods);

			// Route mouse buttons
			if (mouse.IsButtonPressed(.Left))
			{
				mFocusedWorldUI = mHoveredWorldUI;  // Click gives focus
				worldUIContext.InputManager?.ProcessMouseDown(.Left, closestLocalPos.X, closestLocalPos.Y, mods);
			}
			if (mouse.IsButtonReleased(.Left))
				worldUIContext.InputManager?.ProcessMouseUp(.Left, closestLocalPos.X, closestLocalPos.Y, mods);

			if (mouse.IsButtonPressed(.Right))
				worldUIContext.InputManager?.ProcessMouseDown(.Right, closestLocalPos.X, closestLocalPos.Y, mods);
			if (mouse.IsButtonReleased(.Right))
				worldUIContext.InputManager?.ProcessMouseUp(.Right, closestLocalPos.X, closestLocalPos.Y, mods);

			if (mouse.IsButtonPressed(.Middle))
				worldUIContext.InputManager?.ProcessMouseDown(.Middle, closestLocalPos.X, closestLocalPos.Y, mods);
			if (mouse.IsButtonReleased(.Middle))
				worldUIContext.InputManager?.ProcessMouseUp(.Middle, closestLocalPos.X, closestLocalPos.Y, mods);

			// Route scroll wheel
			if (mouse.ScrollX != 0 || mouse.ScrollY != 0)
				worldUIContext.InputManager?.ProcessMouseWheel(mouse.ScrollX, mouse.ScrollY, closestLocalPos.X, closestLocalPos.Y, mods);
		}

		// Route keyboard to focused world UI
		if (mFocusedWorldUI != null)
		{
			let focusedContext = mFocusedWorldUI.UIContext;
			if (focusedContext != null)
				RouteKeyboardToContext(keyboard, mods, focusedContext);
		}
	}

	/// Routes keyboard input to a specific UIContext.
	private void RouteKeyboardToContext(IKeyboard keyboard, UIKeyModifiers mods, UIContext targetContext)
	{
		Sedulous.Shell.Input.KeyCode[?] keysToCheck = .(
			.A, .B, .C, .D, .E, .F, .G, .H, .I, .J, .K, .L, .M,
			.N, .O, .P, .Q, .R, .S, .T, .U, .V, .W, .X, .Y, .Z,
			.Num0, .Num1, .Num2, .Num3, .Num4, .Num5, .Num6, .Num7, .Num8, .Num9,
			.Return, .Escape, .Backspace, .Tab, .Space,
			.Left, .Right, .Up, .Down,
			.Home, .End, .PageUp, .PageDown, .Delete, .Insert
		);

		for (let shellKey in keysToCheck)
		{
			if (keyboard.IsKeyPressed(shellKey))
				targetContext.InputManager?.ProcessKeyDown(InputMapping.MapKey(shellKey), 0, mods, false);
			if (keyboard.IsKeyReleased(shellKey))
				targetContext.InputManager?.ProcessKeyUp(InputMapping.MapKey(shellKey), 0, mods);
		}
	}

	/// Creates a ray from screen coordinates using the camera's inverse matrices.
	private Ray ScreenPointToRay(float screenX, float screenY, CameraProxy* camera)
	{
		// Convert screen coords to normalized device coordinates (-1 to 1)
		float ndcX = (screenX / (float)camera.ViewportWidth) * 2.0f - 1.0f;
		float ndcY = 1.0f - (screenY / (float)camera.ViewportHeight) * 2.0f;  // Flip Y

		// Near point in NDC space
		Vector4 nearPoint = .(ndcX, ndcY, 0.0f, 1.0f);
		// Far point in NDC space
		Vector4 farPoint = .(ndcX, ndcY, 1.0f, 1.0f);

		// Compute inverse view-projection matrix
		let invViewProj = Matrix.Invert(camera.ViewProjectionMatrix);

		// Unproject to world space
		Vector4 nearWorld = Vector4.Transform(nearPoint, invViewProj);
		Vector4 farWorld = Vector4.Transform(farPoint, invViewProj);

		// Perspective divide
		if (Math.Abs(nearWorld.W) > 0.0001f)
			nearWorld /= nearWorld.W;
		if (Math.Abs(farWorld.W) > 0.0001f)
			farWorld /= farWorld.W;

		Vector3 rayPos = .(nearWorld.X, nearWorld.Y, nearWorld.Z);
		Vector3 rayDir = Vector3.Normalize(.(
			farWorld.X - nearWorld.X,
			farWorld.Y - nearWorld.Y,
			farWorld.Z - nearWorld.Z
		));

		return .(rayPos, rayDir);
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

		// Clear input state if this component was hovered/focused
		if (mHoveredWorldUI == component)
			mHoveredWorldUI = null;
		if (mFocusedWorldUI == component)
			mFocusedWorldUI = null;
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
