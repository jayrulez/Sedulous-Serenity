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

	// Viewport size
	private float mViewportWidth;
	private float mViewportHeight;

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

	/// Current viewport width.
	public float ViewportWidth => mViewportWidth;

	/// Current viewport height.
	public float ViewportHeight => mViewportHeight;

	/// Whether layout needs to be recalculated.
	public bool IsLayoutDirty => mLayoutDirty;

	/// Whether visual rendering needs to be updated.
	public bool IsVisualDirty => mVisualDirty;

	public this()
	{
		mDebugSettings = .Default;
		mInputManager = new InputManager(this);
		mAnimationManager = new AnimationManager();
	}

	/// The input manager for this context.
	public InputManager InputManager => mInputManager;

	/// The animation manager for this context.
	public AnimationManager Animations => mAnimationManager;

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
	}

	/// Performs the layout pass on the element tree.
	private void PerformLayout()
	{
		if (mRootElement == null)
			return;

		// Measure pass
		let availableSize = SizeConstraints.FromMaximum(mViewportWidth, mViewportHeight);
		mRootElement.Measure(availableSize);

		// Arrange pass
		let finalRect = RectangleF(0, 0, mViewportWidth, mViewportHeight);
		mRootElement.Arrange(finalRect);
	}

	/// Renders the UI to the provided draw context.
	public void Render(DrawContext drawContext)
	{
		if (mRootElement == null)
			return;

		mRootElement.Render(drawContext);

		// Debug visualization
		if (mDebugSettings.ShowLayoutBounds || mDebugSettings.ShowMargins ||
			mDebugSettings.ShowPadding || mDebugSettings.ShowFocused ||
			mDebugSettings.ShowHitTestBounds)
		{
			RenderDebugOverlay(drawContext);
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

		// Recurse to children
		for (let child in element.Children)
		{
			RenderElementDebug(drawContext, child);
		}
	}

	/// Performs hit testing to find the element at the specified point.
	public UIElement HitTest(float x, float y)
	{
		if (mRootElement == null)
			return null;

		return mRootElement.HitTest(x, y);
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
	public void ProcessMouseMove(float x, float y, KeyModifiers modifiers = .None)
	{
		mInputManager.ProcessMouseMove(x, y, modifiers);
	}

	/// Process mouse button press (simple API).
	public void ProcessMouseDown(MouseButton button, float x, float y, KeyModifiers modifiers = .None)
	{
		mInputManager.ProcessMouseDown(button, x, y, modifiers);
	}

	/// Process mouse button release (simple API).
	public void ProcessMouseUp(MouseButton button, float x, float y, KeyModifiers modifiers = .None)
	{
		mInputManager.ProcessMouseUp(button, x, y, modifiers);
	}

	/// Process mouse wheel.
	public void ProcessMouseWheel(float deltaX, float deltaY, float x, float y, KeyModifiers modifiers = .None)
	{
		mInputManager.ProcessMouseWheel(deltaX, deltaY, x, y, modifiers);
	}

	/// Process key down.
	public void ProcessKeyDown(int32 keyCode, int32 scanCode = 0, KeyModifiers modifiers = .None, bool isRepeat = false)
	{
		mInputManager.ProcessKeyDown(keyCode, scanCode, modifiers, isRepeat);
	}

	/// Process key up.
	public void ProcessKeyUp(int32 keyCode, int32 scanCode = 0, KeyModifiers modifiers = .None)
	{
		mInputManager.ProcessKeyUp(keyCode, scanCode, modifiers);
	}

	/// Process text input.
	public void ProcessTextInput(char32 character)
	{
		mInputManager.ProcessTextInput(character);
	}
}
