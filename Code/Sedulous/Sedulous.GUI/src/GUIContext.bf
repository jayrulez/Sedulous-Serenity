using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.GUI;

/// Debug visualization settings for the GUI system.
public struct DebugSettings
{
	/// Draw bounds around each element (blue).
	public bool ShowLayoutBounds;
	/// Visualize margin areas (orange).
	public bool ShowMargins;
	/// Visualize padding areas (green).
	public bool ShowPadding;
	/// Highlight the focused element (yellow).
	public bool ShowFocused;
	/// Highlight hovered element (cyan).
	public bool ShowHovered;
	/// Show hit test regions (magenta).
	public bool ShowHitTestBounds;

	/// Default settings with all debug options disabled.
	public static DebugSettings Default => .();

	/// Settings with layout bounds enabled.
	public static DebugSettings WithBounds => .() { ShowLayoutBounds = true };

	/// Settings with all options enabled.
	public static DebugSettings All => .()
	{
		ShowLayoutBounds = true,
		ShowMargins = true,
		ShowPadding = true,
		ShowFocused = true,
		ShowHovered = true,
		ShowHitTestBounds = true
	};
}

/// Central context that owns and manages the UI system.
/// All UI elements belong to a context, and services are registered here.
public class GUIContext
{
	// Element registry - maps IDs to elements for safe handle resolution
	private Dictionary<UIElementId, UIElement> mElementRegistry = new .() ~ delete _;

	// Root element of the UI tree
	private UIElement mRootElement;

	// Mutation queue for deferred tree modifications
	private MutationQueue mMutationQueue = new .() ~ delete _;

	// Input and focus management
	private InputManager mInputManager ~ delete _;
	private FocusManager mFocusManager ~ delete _;

	// Layout state
	private bool mLayoutDirty = true;
	private float mViewportWidth;
	private float mViewportHeight;

	// Timing
	private double mTotalTime;
	private float mDeltaTime;

	// Debug settings
	private DebugSettings mDebugSettings;

	/// Creates a new GUIContext.
	public this()
	{
		mInputManager = new InputManager(this);
		mFocusManager = new FocusManager(this);
	}

	/// The root element of the UI tree.
	public UIElement RootElement
	{
		get => mRootElement;
		set
		{
			if (mRootElement == value)
				return;

			// Detach old root
			if (mRootElement != null)
			{
				mRootElement.OnDetachedFromContext();
			}

			mRootElement = value;

			// Attach new root
			if (mRootElement != null)
			{
				mRootElement.OnAttachedToContext(this);
			}

			InvalidateLayout();
		}
	}

	/// The mutation queue for deferred tree modifications.
	public MutationQueue MutationQueue => mMutationQueue;

	/// The input manager for this context.
	public InputManager InputManager => mInputManager;

	/// The focus manager for this context.
	public FocusManager FocusManager => mFocusManager;

	/// The current viewport width.
	public float ViewportWidth => mViewportWidth;

	/// The current viewport height.
	public float ViewportHeight => mViewportHeight;

	/// Total elapsed time in seconds.
	public double TotalTime => mTotalTime;

	/// Time since last frame in seconds.
	public float DeltaTime => mDeltaTime;

	/// Debug visualization settings.
	public ref DebugSettings DebugSettings => ref mDebugSettings;

	// === Element Registry ===

	/// Registers an element in the registry.
	/// Called automatically when elements are attached to the context.
	public void RegisterElement(UIElement element)
	{
		if (element == null)
			return;
		mElementRegistry[element.Id] = element;
	}

	/// Unregisters an element from the registry.
	/// Called automatically when elements are detached or deleted.
	public void UnregisterElement(UIElement element)
	{
		if (element == null)
			return;
		mElementRegistry.Remove(element.Id);
	}

	/// Gets an element by its ID.
	/// Returns null if the element doesn't exist.
	public UIElement GetElementById(UIElementId id)
	{
		if (mElementRegistry.TryGetValue(id, let element))
			return element;
		return null;
	}

	/// Gets an element by ID and casts to the specified type.
	/// Returns null if not found or wrong type.
	public T GetElementById<T>(UIElementId id) where T : UIElement
	{
		return GetElementById(id) as T;
	}

	// === Viewport ===

	/// Sets the viewport size.
	public void SetViewportSize(float width, float height)
	{
		if (mViewportWidth != width || mViewportHeight != height)
		{
			mViewportWidth = width;
			mViewportHeight = height;
			InvalidateLayout();
		}
	}

	// === Layout ===

	/// Marks the layout as needing recalculation.
	public void InvalidateLayout()
	{
		mLayoutDirty = true;
	}

	/// Updates the layout if needed.
	private void UpdateLayout()
	{
		if (!mLayoutDirty || mRootElement == null)
			return;

		// Measure pass
		let constraints = SizeConstraints.FromMaximum(mViewportWidth, mViewportHeight);
		mRootElement.Measure(constraints);

		// Arrange pass
		let viewport = RectangleF(0, 0, mViewportWidth, mViewportHeight);
		mRootElement.Arrange(viewport);

		mLayoutDirty = false;
	}

	// === Update ===

	/// Updates the UI system. Call once per frame.
	/// @param deltaTime Time since last frame in seconds.
	/// @param totalTime Total elapsed time in seconds.
	public void Update(float deltaTime, double totalTime)
	{
		mDeltaTime = deltaTime;
		mTotalTime = totalTime;

		// Update layout
		UpdateLayout();

		// Process any pending mutations
		mMutationQueue.Process(this);
	}

	// === Rendering ===

	/// Renders the UI tree.
	public void Render(DrawContext ctx)
	{
		if (mRootElement == null)
			return;

		mRootElement.Render(ctx);

		// Debug visualization
		if (mDebugSettings.ShowLayoutBounds || mDebugSettings.ShowMargins ||
			mDebugSettings.ShowPadding || mDebugSettings.ShowFocused ||
			mDebugSettings.ShowHovered || mDebugSettings.ShowHitTestBounds)
		{
			RenderDebugOverlay(ctx);
		}
	}

	/// Renders debug visualization overlay.
	private void RenderDebugOverlay(DrawContext ctx)
	{
		if (mRootElement == null)
			return;

		RenderElementDebug(ctx, mRootElement);
	}

	/// Recursively renders debug visualization for an element and its children.
	private void RenderElementDebug(DrawContext ctx, UIElement element)
	{
		if (element.Visibility == .Collapsed)
			return;

		let bounds = element.ArrangedBounds;

		// Layout bounds (blue)
		if (mDebugSettings.ShowLayoutBounds)
		{
			ctx.DrawRect(bounds, Color(0, 120, 215, 255), 2.0f);
		}

		// Margins (orange)
		if (mDebugSettings.ShowMargins && !element.Margin.IsZero)
		{
			let margin = element.Margin;
			// Top margin
			if (margin.Top > 0)
				ctx.FillRect(.(bounds.X, bounds.Y - margin.Top, bounds.Width, margin.Top), Color(255, 165, 0, 80));
			// Bottom margin
			if (margin.Bottom > 0)
				ctx.FillRect(.(bounds.X, bounds.Y + bounds.Height, bounds.Width, margin.Bottom), Color(255, 165, 0, 80));
			// Left margin
			if (margin.Left > 0)
				ctx.FillRect(.(bounds.X - margin.Left, bounds.Y, margin.Left, bounds.Height), Color(255, 165, 0, 80));
			// Right margin
			if (margin.Right > 0)
				ctx.FillRect(.(bounds.X + bounds.Width, bounds.Y, margin.Right, bounds.Height), Color(255, 165, 0, 80));
		}

		// Padding (green)
		if (mDebugSettings.ShowPadding && !element.Padding.IsZero)
		{
			let padding = element.Padding;
			let inner = RectangleF(
				bounds.X + padding.Left,
				bounds.Y + padding.Top,
				bounds.Width - padding.TotalHorizontal,
				bounds.Height - padding.TotalVertical
			);
			// Top padding
			if (padding.Top > 0)
				ctx.FillRect(.(bounds.X, bounds.Y, bounds.Width, padding.Top), Color(0, 200, 0, 80));
			// Bottom padding
			if (padding.Bottom > 0)
				ctx.FillRect(.(bounds.X, inner.Y + inner.Height, bounds.Width, padding.Bottom), Color(0, 200, 0, 80));
			// Left padding
			if (padding.Left > 0)
				ctx.FillRect(.(bounds.X, inner.Y, padding.Left, inner.Height), Color(0, 200, 0, 80));
			// Right padding
			if (padding.Right > 0)
				ctx.FillRect(.(inner.X + inner.Width, inner.Y, padding.Right, inner.Height), Color(0, 200, 0, 80));
		}

		// Focused highlight (yellow)
		if (mDebugSettings.ShowFocused && element == mFocusManager?.FocusedElement)
		{
			ctx.DrawRect(bounds, Color(255, 255, 0, 255), 2.0f);
		}

		// Hovered highlight (cyan)
		if (mDebugSettings.ShowHovered && element == mInputManager?.HoveredElement)
		{
			ctx.DrawRect(bounds, Color(0, 255, 255, 200), 2.0f);
		}

		// Hit test bounds (magenta)
		if (mDebugSettings.ShowHitTestBounds)
		{
			ctx.DrawRect(bounds, Color(255, 0, 255, 150), 1.0f);
		}

		// Recurse to children
		let childCount = element.VisualChildCount;
		for (int i = 0; i < childCount; i++)
		{
			let child = element.GetVisualChild(i);
			if (child != null)
				RenderElementDebug(ctx, child);
		}
	}

	// === Hit Testing ===

	/// Performs hit testing at the given screen coordinates.
	/// Returns the topmost element at that position, or null.
	public UIElement HitTest(float x, float y)
	{
		if (mRootElement == null)
			return null;

		return mRootElement.HitTest(.(x, y));
	}

	// === Deletion ===

	/// Queues an element for deletion.
	/// The element will be removed from its parent and deleted at the end of the frame.
	/// Safe to call from event handlers.
	public void QueueDelete(UIElement element)
	{
		mMutationQueue.QueueDelete(element);
	}

	/// Called when an element is about to be deleted.
	/// Notifies input and focus managers to clear references.
	public void OnElementDeleted(UIElement element)
	{
		mInputManager?.OnElementDeleted(element);
		mFocusManager?.OnElementDeleted(element);
	}

	// === Input Processing ===

	/// Process a mouse move event.
	public void ProcessMouseMove(float x, float y)
	{
		mInputManager?.ProcessMouseMove(x, y);
	}

	/// Process a mouse button down event.
	public void ProcessMouseDown(float x, float y, MouseButton button)
	{
		mInputManager?.ProcessMouseDown(x, y, button);
	}

	/// Process a mouse button up event.
	public void ProcessMouseUp(float x, float y, MouseButton button)
	{
		mInputManager?.ProcessMouseUp(x, y, button);
	}

	/// Process a mouse wheel event.
	public void ProcessMouseWheel(float x, float y, float delta)
	{
		mInputManager?.ProcessMouseWheel(x, y, delta);
	}

	/// Process a key down event.
	public void ProcessKeyDown(KeyCode key, KeyModifiers modifiers = .None)
	{
		mInputManager?.ProcessKeyDown(key, modifiers);
	}

	/// Process a key up event.
	public void ProcessKeyUp(KeyCode key, KeyModifiers modifiers = .None)
	{
		mInputManager?.ProcessKeyUp(key, modifiers);
	}

	/// Process a text input event.
	public void ProcessTextInput(char32 character)
	{
		mInputManager?.ProcessTextInput(character);
	}
}
