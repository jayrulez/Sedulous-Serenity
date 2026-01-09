using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// Debug visualization settings for the UI system.
public struct UIDebugSettings
{
	/// Draw bounds around each element.
	public bool ShowLayoutBounds;
	/// Visualize margin areas.
	public bool ShowMargins;
	/// Visualize padding areas.
	public bool ShowPadding;
	/// Highlight the focused element.
	public bool ShowFocused;
	/// Show hit test regions.
	public bool ShowHitTestBounds;
	/// Apply RenderTransform to debug overlays (shows visual bounds vs layout bounds).
	public bool TransformDebugOverlay;

	/// Default settings with all debug options disabled.
	public static UIDebugSettings Default => .();

	/// Settings with layout bounds enabled.
	public static UIDebugSettings WithBounds => .() { ShowLayoutBounds = true };
}

/// Interface for clipboard operations.
public interface IClipboard
{
	/// Gets text from the clipboard.
	Result<void> GetText(String outText);
	/// Sets text to the clipboard.
	Result<void> SetText(StringView text);
	/// Returns whether the clipboard contains text.
	bool HasText { get; }
}

/// Interface for system services required by the UI.
public interface ISystemServices
{
	/// Gets the current time in seconds.
	double CurrentTime { get; }
}

/// Central context that owns and manages the UI system.
/// All UI elements belong to a context, and services are registered here.
public class UIContext
{
	// Root element of the UI tree
	private UIElement mRootElement;

	// Currently focused element
	private UIElement mFocusedElement;

	// Element with mouse capture
	private UIElement mCapturedElement;

	// Element currently under mouse
	private UIElement mHoveredElement;

	// Services
	private IClipboard mClipboard;
	private ISystemServices mSystemServices;

	// Input manager
	private InputManager mInputManager ~ delete _;

	// Animation manager
	private AnimationManager mAnimationManager ~ delete _;

	// Drag-drop manager
	private DragDropManager mDragDropManager ~ delete _;

	// Generic service registry
	private Dictionary<Type, Object> mServices = new .() ~ delete _;

	// Theme (accessed via service registry)
	private Object mTheme;

	// Timing
	private double mTotalTime;
	private float mDeltaTime;

	// Layout state
	private bool mLayoutDirty = true;
	private bool mVisualDirty = true;

	// Debug settings
	private UIDebugSettings mDebugSettings;

	// Viewport size (physical pixels)
	private float mViewportWidth;
	private float mViewportHeight;

	// UI scale factor (1.0 = 100%, 2.0 = 200% for HiDPI)
	private float mScale = 1.0f;

	// Popup management
	private List<Popup> mActivePopups = new .() ~ delete _;
	private Popup mModalPopup; // Currently active modal popup (blocks input to lower layers)
	private float mLastMouseX;
	private float mLastMouseY;

	// Deferred deletion queue - elements added here are deleted at end of Update()
	// This prevents use-after-free when an element deletes itself during event handling
	private List<UIElement> mDeferredDeletions = new .() ~ delete _;

	/// The root element of the UI tree.
	public UIElement RootElement
	{
		get => mRootElement;
		set
		{
			if (mRootElement != value)
			{
				if (mRootElement != null)
					mRootElement.[Friend]mContext = null;

				mRootElement = value;

				if (mRootElement != null)
					mRootElement.[Friend]mContext = this;

				InvalidateLayout();
			}
		}
	}

	/// The currently focused element, or null if no element has focus.
	public UIElement FocusedElement => mFocusedElement;

	/// The element that has captured mouse input, or null.
	public UIElement CapturedElement => mCapturedElement;

	/// The element currently under the mouse, or null.
	public UIElement HoveredElement => mHoveredElement;

	/// The cursor that should be displayed based on the hovered element.
	public CursorType CurrentCursor => mHoveredElement?.EffectiveCursor ?? .Default;

	/// The registered clipboard service.
	public IClipboard Clipboard => mClipboard;

	/// The registered system services.
	public ISystemServices SystemServices => mSystemServices;

	/// Debug visualization settings.
	public ref UIDebugSettings DebugSettings => ref mDebugSettings;

	/// Total time elapsed since the UI started.
	public double TotalTime => mTotalTime;

	/// Time elapsed since the last update.
	public float DeltaTime => mDeltaTime;

	/// Current viewport width (physical pixels).
	public float ViewportWidth => mViewportWidth;

	/// Current viewport height (physical pixels).
	public float ViewportHeight => mViewportHeight;

	/// Logical viewport width (ViewportWidth / Scale).
	public float LogicalWidth => mViewportWidth / mScale;

	/// Logical viewport height (ViewportHeight / Scale).
	public float LogicalHeight => mViewportHeight / mScale;

	/// The UI scale factor. Default is 1.0.
	/// Values > 1.0 make UI elements larger (e.g., 2.0 for HiDPI/Retina displays).
	public float Scale
	{
		get => mScale;
		set
		{
			let newScale = Math.Max(0.1f, value); // Clamp to reasonable minimum
			if (mScale != newScale)
			{
				mScale = newScale;
				InvalidateLayout();
			}
		}
	}

	/// Whether layout needs to be recalculated.
	public bool IsLayoutDirty => mLayoutDirty;

	/// Whether visual rendering needs to be updated.
	public bool IsVisualDirty => mVisualDirty;

	public this()
	{
		mDebugSettings = .Default;
		mInputManager = new InputManager(this);
		mAnimationManager = new AnimationManager();
		mDragDropManager = new DragDropManager(this);
	}

	/// The input manager for this context.
	public InputManager InputManager => mInputManager;

	/// The animation manager for this context.
	public AnimationManager Animations => mAnimationManager;

	/// The drag-drop manager for this context.
	public DragDropManager DragDrop => mDragDropManager;

	/// Active popups (read-only view).
	public Span<Popup> ActivePopups => mActivePopups;

	/// Whether any popup is currently open.
	public bool HasOpenPopups => mActivePopups.Count > 0;

	/// Whether a modal popup is blocking input.
	public bool IsModalActive => mModalPopup != null;

	/// Last known mouse position (logical coordinates).
	public (float X, float Y) LastMousePosition => (mLastMouseX, mLastMouseY);

	public ~this()
	{
		if (mRootElement != null)
		{
			mRootElement.[Friend]mContext = null;
			delete mRootElement;
		}
	}

	/// Registers the clipboard service.
	public void RegisterClipboard(IClipboard clipboard)
	{
		mClipboard = clipboard;
	}

	/// Registers system services.
	public void RegisterSystemServices(ISystemServices services)
	{
		mSystemServices = services;
	}

	/// Registers a service of type T.
	public void RegisterService<T>(T service) where T : class
	{
		mServices[typeof(T)] = service;
	}

	/// Gets a service of type T.
	public Result<T> GetService<T>() where T : class
	{
		if (mServices.TryGetValue(typeof(T), let obj))
		{
			if (let service = obj as T)
				return .Ok(service);
		}
		return .Err;
	}

	/// Checks if a service is registered.
	public bool HasService<T>() where T : class
	{
		return mServices.ContainsKey(typeof(T));
	}

	/// Sets the current theme, replacing any existing theme.
	/// The old theme is deleted and all visuals are invalidated.
	public void SetTheme(ITheme newTheme)
	{
		// Delete old theme if exists
		if (mServices.TryGetValue(typeof(ITheme), let oldObj))
		{
			if (let oldTheme = oldObj as ITheme)
				delete oldTheme;
		}

		// Register new theme
		mServices[typeof(ITheme)] = newTheme;

		// Invalidate all visuals so controls repaint with new theme colors
		InvalidateLayout();
	}

	/// Gets the current theme, if any.
	public ITheme CurrentTheme
	{
		get
		{
			if (GetService<ITheme>() case .Ok(let theme))
				return theme;
			return null;
		}
	}

	/// Sets the viewport size for layout.
	public void SetViewportSize(float width, float height)
	{
		if (mViewportWidth != width || mViewportHeight != height)
		{
			mViewportWidth = width;
			mViewportHeight = height;
			InvalidateLayout();
		}
	}

	/// Marks layout as needing recalculation.
	public void InvalidateLayout()
	{
		mLayoutDirty = true;
		mVisualDirty = true;
	}

	/// Marks visuals as needing redraw.
	public void InvalidateVisual()
	{
		mVisualDirty = true;
	}

	/// Sets focus to the specified element.
	public void SetFocus(UIElement element)
	{
		if (mFocusedElement == element)
			return;

		let oldFocus = mFocusedElement;
		mFocusedElement = element;

		if (oldFocus != null)
			oldFocus.[Friend]OnLostFocus();

		if (mFocusedElement != null)
			mFocusedElement.[Friend]OnGotFocus();

		InvalidateVisual();
	}

	/// Captures mouse input to the specified element.
	public void CaptureMouse(UIElement element)
	{
		mCapturedElement = element;
	}

	/// Releases mouse capture.
	public void ReleaseMouseCapture()
	{
		mCapturedElement = null;
	}

	// === Popup Management ===

	/// Opens a popup and adds it to the active popup list.
	/// Called internally by Popup.Open().
	public void OpenPopup(Popup popup)
	{
		if (popup == null || mActivePopups.Contains(popup))
			return;

		// Set context on popup
		popup.[Friend]mContext = this;

		mActivePopups.Add(popup);

		// Track modal state
		if (popup.IsModal)
			mModalPopup = popup;

		InvalidateLayout();
	}

	/// Closes a popup and removes it from the active popup list.
	/// Called internally by Popup.Close().
	public void ClosePopup(Popup popup)
	{
		if (popup == null)
			return;

		mActivePopups.Remove(popup);

		// Clear context
		popup.[Friend]mContext = null;

		// Update modal state
		if (mModalPopup == popup)
		{
			// Find next modal popup if any
			mModalPopup = null;
			for (let p in mActivePopups)
			{
				if (p.IsModal)
				{
					mModalPopup = p;
					break;
				}
			}
		}

		InvalidateVisual();
	}

	/// Closes all open popups.
	public void CloseAllPopups()
	{
		// Close in reverse order (newest first)
		while (mActivePopups.Count > 0)
		{
			let popup = mActivePopups[mActivePopups.Count - 1];
			popup.Close();
		}
	}

	/// Queues an element for deletion at the end of the current frame.
	/// Use this instead of `delete` when an element needs to delete itself
	/// during event handling (e.g., a dialog closing when a button is clicked).
	/// This prevents use-after-free crashes when the call stack still references the element.
	public void DeferDelete(UIElement element)
	{
		if (element != null && !mDeferredDeletions.Contains(element))
			mDeferredDeletions.Add(element);
	}

	/// Processes all pending deferred deletions.
	/// Called automatically at the end of Update().
	private void ProcessDeferredDeletions()
	{
		if (mDeferredDeletions.Count == 0)
			return;

		// Get tooltip service for cleanup notifications
		ITooltipService tooltipService = null;
		if (GetService<ITooltipService>() case .Ok(let svc))
			tooltipService = svc;

		for (let element in mDeferredDeletions)
		{
			// Notify tooltip service about this element and all its descendants
			if (tooltipService != null)
				NotifyTooltipServiceRecursive(tooltipService, element);

			// Clear any references this context might have to the element or its descendants
			if (mFocusedElement != null && IsDescendantOf(mFocusedElement, element))
				mFocusedElement = null;
			if (mCapturedElement != null && IsDescendantOf(mCapturedElement, element))
				mCapturedElement = null;
			if (mHoveredElement != null && IsDescendantOf(mHoveredElement, element))
				mHoveredElement = null;

			delete element;
		}
		mDeferredDeletions.Clear();
	}

	/// Checks if 'element' is the same as 'ancestor' or a descendant of it.
	private static bool IsDescendantOf(UIElement element, UIElement ancestor)
	{
		var current = element;
		while (current != null)
		{
			if (current == ancestor)
				return true;
			current = current.Parent;
		}
		return false;
	}

	/// Recursively notifies tooltip service about an element and its children being deleted.
	private void NotifyTooltipServiceRecursive(ITooltipService tooltipService, UIElement element)
	{
		tooltipService.OnElementDeleted(element);
		for (let child in element.Children)
			NotifyTooltipServiceRecursive(tooltipService, child);
	}

	/// Closes popups that should close when clicking outside.
	/// Returns true if any popup was closed.
	internal bool HandleClickOutsidePopups(float x, float y)
	{
		var closedAny = false;

		// Check popups in reverse order (topmost first)
		for (int i = mActivePopups.Count - 1; i >= 0; i--)
		{
			let popup = mActivePopups[i];
			if (popup.ShouldCloseOnClickOutside(x, y))
			{
				popup.Close();
				closedAny = true;
			}
		}

		return closedAny;
	}

	/// Shows a context menu at the specified position.
	public void ShowContextMenu(ContextMenu menu, float x, float y)
	{
		menu.OpenAt(x, y);
	}

	/// Shows a context menu anchored to an element.
	public void ShowContextMenu(ContextMenu menu, UIElement anchor, PopupPlacement placement = .Bottom)
	{
		menu.OpenAt(anchor, placement);
	}

	/// Updates the UI state. Call this each frame.
	public void Update(float deltaTime, double totalTime)
	{
		mDeltaTime = deltaTime;
		mTotalTime = totalTime;

		// Update animations
		mAnimationManager.Update(deltaTime);

		// Update layout if needed
		if (mLayoutDirty && mRootElement != null)
		{
			PerformLayout();
			mLayoutDirty = false;
		}

		// Process any deferred deletions (must be last!)
		ProcessDeferredDeletions();
	}

	/// Performs the layout pass on the element tree.
	private void PerformLayout()
	{
		// Use logical size for layout (physical size / scale)
		let logicalWidth = mViewportWidth / mScale;
		let logicalHeight = mViewportHeight / mScale;

		// Layout main UI
		if (mRootElement != null)
		{
			// Measure pass
			let availableSize = SizeConstraints.FromMaximum(logicalWidth, logicalHeight);
			mRootElement.Measure(availableSize);

			// Arrange pass
			let finalRect = RectangleF(0, 0, logicalWidth, logicalHeight);
			mRootElement.Arrange(finalRect);
		}

		// Layout popups
		for (let popup in mActivePopups)
		{
			// Measure popup
			let popupConstraints = SizeConstraints.FromMaximum(logicalWidth, logicalHeight);
			popup.Measure(popupConstraints);

			// Calculate popup position
			let position = popup.CalculatePosition(logicalWidth, logicalHeight);

			// Arrange popup at calculated position
			let popupRect = RectangleF(position.X, position.Y, popup.DesiredSize.Width, popup.DesiredSize.Height);
			popup.Arrange(popupRect);
		}
	}

	/// Renders the UI to the provided draw context.
	public void Render(DrawContext drawContext)
	{
		// Apply scale transform for resolution independence
		if (mScale != 1.0f)
		{
			drawContext.PushState();
			drawContext.Scale(mScale, mScale);
		}

		// Render main UI
		if (mRootElement != null)
		{
			mRootElement.Render(drawContext);
		}

		// Render modal dimming overlay if modal popup is active
		if (mModalPopup != null && mModalPopup.Behavior.HasFlag(.DimBackground))
		{
			let logicalWidth = mViewportWidth / mScale;
			let logicalHeight = mViewportHeight / mScale;
			drawContext.FillRect(.(0, 0, logicalWidth, logicalHeight), Color(0, 0, 0, 128));
		}

		// Render popups (in order, so later popups appear on top)
		for (let popup in mActivePopups)
		{
			popup.Render(drawContext);
		}

		// Render drag-drop visual if active
		if (mDragDropManager.IsDragging)
		{
			mDragDropManager.RenderDragVisual(drawContext);
		}

		// Debug visualization
		if (mDebugSettings.ShowLayoutBounds || mDebugSettings.ShowMargins ||
			mDebugSettings.ShowPadding || mDebugSettings.ShowFocused ||
			mDebugSettings.ShowHitTestBounds)
		{
			RenderDebugOverlay(drawContext);
		}

		// Restore transform
		if (mScale != 1.0f)
		{
			drawContext.PopState();
		}

		mVisualDirty = false;
	}

	/// Renders debug visualization overlay.
	private void RenderDebugOverlay(DrawContext drawContext)
	{
		if (mRootElement == null)
			return;

		RenderElementDebug(drawContext, mRootElement);
	}

	/// Recursively renders debug visualization for an element and its children.
	private void RenderElementDebug(DrawContext drawContext, UIElement element)
	{
		if (element.Visibility == .Collapsed)
			return;

		let bounds = element.Bounds;
		let hasTransform = element.RenderTransform != Matrix.Identity;

		// Apply transform for debug overlay if enabled
		Matrix savedTransform = .Identity;
		if (mDebugSettings.TransformDebugOverlay && hasTransform)
		{
			savedTransform = drawContext.GetTransform();

			let origin = element.RenderTransformOrigin;
			let originX = bounds.X + bounds.Width * origin.X;
			let originY = bounds.Y + bounds.Height * origin.Y;

			let toOrigin = Matrix.CreateTranslation(-originX, -originY, 0);
			let fromOrigin = Matrix.CreateTranslation(originX, originY, 0);
			let combinedTransform = toOrigin * element.RenderTransform * fromOrigin * savedTransform;
			drawContext.SetTransform(combinedTransform);
		}

		// Layout bounds (blue)
		if (mDebugSettings.ShowLayoutBounds)
		{
			drawContext.DrawRect(bounds, Color(0, 120, 215, 200), 1.0f);
		}

		// Margins (orange)
		if (mDebugSettings.ShowMargins && !element.Margin.IsZero)
		{
			let margin = element.Margin;
			// Top margin
			if (margin.Top > 0)
				drawContext.FillRect(.(bounds.X, bounds.Y - margin.Top, bounds.Width, margin.Top), Color(255, 165, 0, 80));
			// Bottom margin
			if (margin.Bottom > 0)
				drawContext.FillRect(.(bounds.X, bounds.Y + bounds.Height, bounds.Width, margin.Bottom), Color(255, 165, 0, 80));
			// Left margin
			if (margin.Left > 0)
				drawContext.FillRect(.(bounds.X - margin.Left, bounds.Y, margin.Left, bounds.Height), Color(255, 165, 0, 80));
			// Right margin
			if (margin.Right > 0)
				drawContext.FillRect(.(bounds.X + bounds.Width, bounds.Y, margin.Right, bounds.Height), Color(255, 165, 0, 80));
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
				drawContext.FillRect(.(bounds.X, bounds.Y, bounds.Width, padding.Top), Color(0, 200, 0, 80));
			// Bottom padding
			if (padding.Bottom > 0)
				drawContext.FillRect(.(bounds.X, inner.Y + inner.Height, bounds.Width, padding.Bottom), Color(0, 200, 0, 80));
			// Left padding
			if (padding.Left > 0)
				drawContext.FillRect(.(bounds.X, inner.Y, padding.Left, inner.Height), Color(0, 200, 0, 80));
			// Right padding
			if (padding.Right > 0)
				drawContext.FillRect(.(inner.X + inner.Width, inner.Y, padding.Right, inner.Height), Color(0, 200, 0, 80));
		}

		// Focused highlight (yellow)
		if (mDebugSettings.ShowFocused && element == mFocusedElement)
		{
			drawContext.DrawRect(bounds, Color(255, 255, 0, 255), 2.0f);
		}

		// Hit test bounds (magenta) - shows where element accepts input
		if (mDebugSettings.ShowHitTestBounds)
		{
			drawContext.DrawRect(bounds, Color(255, 0, 255, 150), 1.0f);
		}

		// Restore transform before recursing to children
		if (mDebugSettings.TransformDebugOverlay && hasTransform)
			drawContext.SetTransform(savedTransform);

		// Recurse to children
		for (let child in element.Children)
		{
			RenderElementDebug(drawContext, child);
		}
	}

	/// Performs hit testing to find the element at the specified point.
	/// Coordinates are in physical pixels and will be converted to logical coordinates.
	/// Checks popups first (in reverse order), then main UI.
	public UIElement HitTest(float x, float y)
	{
		let logicalX = x / mScale;
		let logicalY = y / mScale;

		// Check popups first (in reverse order - topmost first)
		for (int i = mActivePopups.Count - 1; i >= 0; i--)
		{
			let popup = mActivePopups[i];
			let hit = popup.HitTest(logicalX, logicalY);
			if (hit != null)
				return hit;
		}

		// If modal popup is active, block hits to main UI
		if (mModalPopup != null)
			return null;

		// Check main UI
		if (mRootElement != null)
			return mRootElement.HitTest(logicalX, logicalY);

		return null;
	}

	/// Performs hit testing in logical coordinates (already scaled).
	/// Checks popups first (in reverse order), then main UI.
	public UIElement HitTestLogical(float x, float y)
	{
		// Check popups first (in reverse order - topmost first)
		for (int i = mActivePopups.Count - 1; i >= 0; i--)
		{
			let popup = mActivePopups[i];
			let hit = popup.HitTest(x, y);
			if (hit != null)
				return hit;
		}

		// If modal popup is active, block hits to main UI
		if (mModalPopup != null)
			return null;

		// Check main UI
		if (mRootElement != null)
			return mRootElement.HitTest(x, y);

		return null;
	}

	/// Finds an element by its ID.
	public UIElement FindElementById(UIElementId id)
	{
		if (mRootElement == null)
			return null;

		return mRootElement.FindElementById(id);
	}

	// === Input Processing ===

	/// Process mouse movement (simple API).
	/// Coordinates are in physical pixels and will be converted to logical coordinates.
	public void ProcessMouseMove(float x, float y, KeyModifiers modifiers = .None)
	{
		let logicalX = x / mScale;
		let logicalY = y / mScale;
		mLastMouseX = logicalX;
		mLastMouseY = logicalY;

		// Update drag-drop if active
		if (mDragDropManager.IsDragging)
		{
			mDragDropManager.UpdateDrag(logicalX, logicalY, modifiers);
		}

		mInputManager.ProcessMouseMove(logicalX, logicalY, modifiers);
	}

	/// Process mouse button press (simple API).
	/// Coordinates are in physical pixels and will be converted to logical coordinates.
	public void ProcessMouseDown(MouseButton button, float x, float y, KeyModifiers modifiers = .None)
	{
		let logicalX = x / mScale;
		let logicalY = y / mScale;
		mLastMouseX = logicalX;
		mLastMouseY = logicalY;

		// Check if we should close any popups (click outside)
		if (button == .Left)
		{
			HandleClickOutsidePopups(logicalX, logicalY);
		}

		mInputManager.ProcessMouseDown(button, logicalX, logicalY, modifiers);
	}

	/// Process mouse button release (simple API).
	/// Coordinates are in physical pixels and will be converted to logical coordinates.
	public void ProcessMouseUp(MouseButton button, float x, float y, KeyModifiers modifiers = .None)
	{
		let logicalX = x / mScale;
		let logicalY = y / mScale;
		mLastMouseX = logicalX;
		mLastMouseY = logicalY;

		// End drag-drop if active
		if (mDragDropManager.IsDragging && button == .Left)
		{
			mDragDropManager.EndDrag(logicalX, logicalY, modifiers);
		}

		mInputManager.ProcessMouseUp(button, logicalX, logicalY, modifiers);
	}

	/// Process mouse wheel.
	/// Coordinates are in physical pixels and will be converted to logical coordinates.
	public void ProcessMouseWheel(float deltaX, float deltaY, float x, float y, KeyModifiers modifiers = .None)
	{
		mInputManager.ProcessMouseWheel(deltaX, deltaY, x / mScale, y / mScale, modifiers);
	}

	/// Process key down.
	public void ProcessKeyDown(KeyCode key, int32 scanCode = 0, KeyModifiers modifiers = .None, bool isRepeat = false)
	{
		mInputManager.ProcessKeyDown(key, scanCode, modifiers, isRepeat);
	}

	/// Process key up.
	public void ProcessKeyUp(KeyCode key, int32 scanCode = 0, KeyModifiers modifiers = .None)
	{
		mInputManager.ProcessKeyUp(key, scanCode, modifiers);
	}

	/// Process text input.
	public void ProcessTextInput(char32 character)
	{
		mInputManager.ProcessTextInput(character);
	}
}
