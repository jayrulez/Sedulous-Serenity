namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;

/// Central input dispatcher. Routes mouse, keyboard, and text events to the view tree.
/// Lives inside UIContext and reuses pooled event args to avoid allocation.
public class InputManager
{
	private UIContext mContext;

	// Mouse state
	private View mHoveredView;
	private View mPressedView;
	private MouseButton mPressedButton;

	// Double-click detection
	private double mLastClickTime;
	private Vector2 mLastClickPos;
	private MouseButton mLastClickButton;
	private int32 mClickCount;

	/// Time window for double-click detection (seconds).
	public float DoubleClickTime = 0.3f;

	/// Max distance the mouse can move between clicks for double-click (pixels).
	public float DoubleClickDistance = 4.0f;

	// Pooled event args (reused every frame)
	private MouseEventArgs mMouseEventArgs = new .() ~ delete _;
	private MouseButtonEventArgs mMouseButtonEventArgs = new .() ~ delete _;
	private MouseWheelEventArgs mMouseWheelEventArgs = new .() ~ delete _;
	private KeyEventArgs mKeyEventArgs = new .() ~ delete _;
	private TextInputEventArgs mTextInputEventArgs = new .() ~ delete _;

	public this(UIContext context)
	{
		mContext = context;
	}

	/// The currently hovered view.
	public View HoveredView => mHoveredView;

	/// The view that received the last mouse down (tracked until mouse up).
	public View PressedView => mPressedView;

	//==========================================================================
	// Mouse Events
	//==========================================================================

	/// Process mouse movement. Updates hover state, fires enter/leave events.
	public void ProcessMouseMove(float screenX, float screenY, KeyModifiers modifiers)
	{
		// Check if drag system wants to consume this event
		if (mContext.DragDrop.UpdateDrag(screenX, screenY, modifiers))
			return;

		let focusMgr = mContext.FocusManager;
		View target;

		// If captured, route to captured view
		if (focusMgr.CapturedView != null)
		{
			target = focusMgr.CapturedView;
		}
		else
		{
			target = mContext.HitTest(.(screenX, screenY));
		}

		// Handle enter/leave
		if (target != mHoveredView)
		{
			if (mHoveredView != null)
			{
				mHoveredView.[Friend]mIsHovered = false;
				mMouseEventArgs.Reset();
				mMouseEventArgs.ScreenX = screenX;
				mMouseEventArgs.ScreenY = screenY;
				mMouseEventArgs.Modifiers = modifiers;
				SetLocalCoords(mMouseEventArgs, mHoveredView);
				mHoveredView.OnMouseLeave(mMouseEventArgs);
			}

			mHoveredView = target;

			if (mHoveredView != null)
			{
				mHoveredView.[Friend]mIsHovered = true;
				mMouseEventArgs.Reset();
				mMouseEventArgs.ScreenX = screenX;
				mMouseEventArgs.ScreenY = screenY;
				mMouseEventArgs.Modifiers = modifiers;
				SetLocalCoords(mMouseEventArgs, mHoveredView);
				mHoveredView.OnMouseEnter(mMouseEventArgs);
			}

			// Notify tooltip manager of hover change
			mContext.Tooltips.OnHoverChanged(mHoveredView);
		}

		// Update tooltip mouse position
		mContext.Tooltips.OnMouseMoved(screenX, screenY);

		// Update cursor
		let cursor = (mHoveredView != null) ? mHoveredView.EffectiveCursor : CursorType.Default;
		if (mContext.ActiveInputRoot != null)
			mContext.ActiveInputRoot.RequestedCursor = cursor;

		// Fire OnMouseMove on target
		if (target != null)
		{
			mMouseEventArgs.Reset();
			mMouseEventArgs.ScreenX = screenX;
			mMouseEventArgs.ScreenY = screenY;
			mMouseEventArgs.Modifiers = modifiers;
			SetLocalCoords(mMouseEventArgs, target);
			target.OnMouseMove(mMouseEventArgs);

			if (!mMouseEventArgs.Handled)
				BubbleMouseEvent(target.Parent, mMouseEventArgs, scope (v, e) => v.OnMouseMove(e));
		}
	}

	/// Process mouse button press.
	/// Returns true if the mouse down was consumed by the UI.
	public bool ProcessMouseDown(float screenX, float screenY, MouseButton button, KeyModifiers modifiers)
	{
		// Hide tooltip on click
		mContext.Tooltips.OnMouseDown();

		// Check if click is outside popups (for close-on-click-outside)
		let popupLayer = mContext.ActivePopupLayer;
		if (popupLayer.HasPopups)
		{
			let logicalPoint = Vector2(screenX / mContext.DpiScale, screenY / mContext.DpiScale);
			let popupHit = popupLayer.HitTest(logicalPoint);
			if (popupHit == null)
			{
				popupLayer.HandleClickOutside(screenX, screenY);
				return true; // Consume the click
			}
		}

		let focusMgr = mContext.FocusManager;
		View target;

		if (focusMgr.CapturedView != null)
			target = focusMgr.CapturedView;
		else
			target = mContext.HitTest(.(screenX, screenY));

		if (target == null)
		{
			// Click on empty space clears focus
			focusMgr.ClearFocus();
			return false;
		}

		// Double-click detection
		double now = mContext.TotalTime;
		float dx = screenX - mLastClickPos.X;
		float dy = screenY - mLastClickPos.Y;
		float dist = Math.Sqrt(dx * dx + dy * dy);

		if (button == mLastClickButton &&
			(now - mLastClickTime) < DoubleClickTime &&
			dist < DoubleClickDistance)
		{
			mClickCount++;
		}
		else
		{
			mClickCount = 1;
		}

		mLastClickTime = now;
		mLastClickPos = .(screenX, screenY);
		mLastClickButton = button;

		// Track pressed state
		mPressedView = target;
		mPressedButton = button;
		target.[Friend]mIsPressed = true;

		// Focus on click (only if enabled)
		if (target.Focusable && target.Enabled)
			focusMgr.SetFocus(target);
		else
		{
			// Walk up to find a focusable AND enabled ancestor, or clear focus
			var ancestor = target.Parent;
			bool foundFocusable = false;
			while (ancestor != null)
			{
				if (ancestor.Focusable && ancestor.Enabled)
				{
					focusMgr.SetFocus(ancestor);
					foundFocusable = true;
					break;
				}
				ancestor = ancestor.Parent;
			}
			if (!foundFocusable)
				focusMgr.ClearFocus();
		}

		// Fire event
		mMouseButtonEventArgs.Reset();
		mMouseButtonEventArgs.ScreenX = screenX;
		mMouseButtonEventArgs.ScreenY = screenY;
		mMouseButtonEventArgs.Button = button;
		mMouseButtonEventArgs.ClickCount = mClickCount;
		mMouseButtonEventArgs.Modifiers = modifiers;
		SetLocalCoords(mMouseButtonEventArgs, target);
		target.OnMouseDown(mMouseButtonEventArgs);

		if (!mMouseButtonEventArgs.Handled)
			BubbleMouseButtonEvent(target.Parent, mMouseButtonEventArgs, scope (v, e) => v.OnMouseDown(e));

		// After mousedown event processing, check for drag source.
		// Run regardless of Handled — a control can handle clicks (e.g. selection)
		// and still participate in drag (click+hold → threshold → drag starts).
		// Skip on double-clicks: double-clicks trigger actions (redock, select word),
		// not drags. Without this guard, a double-click that destroys a view (e.g.
		// floating window redock) would start a phantom drag with no matching mouse-up.
		if (button == .Left && mClickCount <= 1)
		{
			var dragCandidate = target;
			while (dragCandidate != null)
			{
				if (let source = dragCandidate as IDragSource)
				{
					mContext.DragDrop.BeginPotentialDrag(dragCandidate, source, screenX, screenY, button);
					break;
				}
				dragCandidate = dragCandidate.Parent;
			}
		}

		return mMouseButtonEventArgs.Handled;
	}

	/// Process mouse button release. Returns true if consumed by the UI.
	public bool ProcessMouseUp(float screenX, float screenY, MouseButton button, KeyModifiers modifiers)
	{
		// Check if drag system wants to consume this event
		if (mContext.DragDrop.EndDrag(screenX, screenY))
		{
			if (mPressedView != null)
			{
				mPressedView.[Friend]mIsPressed = false;
				mPressedView = null;
			}
			return true;
		}

		View target = mPressedView;

		if (target == null)
		{
			// No pressed view — use hit test
			target = mContext.HitTest(.(screenX, screenY));
			if (target == null)
				return false;
		}

		target.[Friend]mIsPressed = false;

		mMouseButtonEventArgs.Reset();
		mMouseButtonEventArgs.ScreenX = screenX;
		mMouseButtonEventArgs.ScreenY = screenY;
		mMouseButtonEventArgs.Button = button;
		mMouseButtonEventArgs.ClickCount = mClickCount;
		mMouseButtonEventArgs.Modifiers = modifiers;
		SetLocalCoords(mMouseButtonEventArgs, target);
		target.OnMouseUp(mMouseButtonEventArgs);

		if (!mMouseButtonEventArgs.Handled)
			BubbleMouseButtonEvent(target.Parent, mMouseButtonEventArgs, scope (v, e) => v.OnMouseUp(e));

		mPressedView = null;
		return mMouseButtonEventArgs.Handled;
	}

	/// Process mouse wheel scroll. Returns true if consumed by the UI.
	public bool ProcessMouseWheel(float screenX, float screenY, float deltaX, float deltaY, KeyModifiers modifiers)
	{
		let target = mContext.HitTest(.(screenX, screenY));
		if (target == null)
			return false;

		mMouseWheelEventArgs.Reset();
		mMouseWheelEventArgs.ScreenX = screenX;
		mMouseWheelEventArgs.ScreenY = screenY;
		mMouseWheelEventArgs.DeltaX = deltaX;
		mMouseWheelEventArgs.DeltaY = deltaY;
		mMouseWheelEventArgs.Modifiers = modifiers;
		SetLocalCoords(mMouseWheelEventArgs, target);
		target.OnMouseWheel(mMouseWheelEventArgs);

		if (!mMouseWheelEventArgs.Handled)
			BubbleMouseWheelEvent(target.Parent, mMouseWheelEventArgs);

		return mMouseWheelEventArgs.Handled;
	}

	//==========================================================================
	// Keyboard Events
	//==========================================================================

	/// Process key down. Routes to focused view with bubbling.
	/// Returns true if the key was consumed by the UI.
	public bool ProcessKeyDown(KeyCode key, KeyModifiers modifiers, bool isRepeat)
	{
		let focusMgr = mContext.FocusManager;

		// Escape cancels active drag first
		if (key == .Escape && !isRepeat && mContext.DragDrop.IsDragging)
		{
			mContext.DragDrop.CancelDrag();
			return true;
		}

		// Escape closes topmost popup
		if (key == .Escape && !isRepeat)
		{
			let popupLayer = mContext.ActivePopupLayer;
			if (popupLayer.HasPopups)
			{
				popupLayer.CloseTopPopup();
				return true;
			}
		}

		// Tab navigation
		if (key == .Tab && !isRepeat)
		{
			if (((int32)modifiers & (int32)KeyModifiers.Shift) != 0)
				focusMgr.FocusPrevious();
			else
				focusMgr.FocusNext();
			return true;
		}

		let target = focusMgr.FocusedView;
		if (target == null)
			return false;

		mKeyEventArgs.Reset();
		mKeyEventArgs.Key = key;
		mKeyEventArgs.Modifiers = modifiers;
		mKeyEventArgs.IsRepeat = isRepeat;
		target.OnKeyDown(mKeyEventArgs);

		if (!mKeyEventArgs.Handled)
			BubbleKeyEvent(target.Parent, mKeyEventArgs, scope (v, e) => v.OnKeyDown(e));

		return mKeyEventArgs.Handled;
	}

	/// Process key up. Routes to focused view with bubbling.
	/// Returns true if the key was consumed by the UI.
	public bool ProcessKeyUp(KeyCode key, KeyModifiers modifiers)
	{
		let target = mContext.FocusManager.FocusedView;
		if (target == null)
			return false;

		mKeyEventArgs.Reset();
		mKeyEventArgs.Key = key;
		mKeyEventArgs.Modifiers = modifiers;
		target.OnKeyUp(mKeyEventArgs);

		if (!mKeyEventArgs.Handled)
			BubbleKeyEvent(target.Parent, mKeyEventArgs, scope (v, e) => v.OnKeyUp(e));

		return mKeyEventArgs.Handled;
	}

	/// Process text input. Routes to focused view.
	public void ProcessTextInput(char32 character)
	{
		let target = mContext.FocusManager.FocusedView;
		if (target == null)
			return;

		mTextInputEventArgs.Reset();
		mTextInputEventArgs.Character = character;
		target.OnTextInput(mTextInputEventArgs);
	}

	//==========================================================================
	// Cleanup
	//==========================================================================

	/// Called when a view is about to be deleted. Clears any references to it.
	public void OnElementDeleted(View view)
	{
		if (mHoveredView == view)
		{
			mHoveredView.[Friend]mIsHovered = false;
			mHoveredView = null;
		}

		if (mPressedView == view)
		{
			mPressedView.[Friend]mIsPressed = false;
			mPressedView = null;
		}
	}

	//==========================================================================
	// Helpers
	//==========================================================================

	/// Convert screen coordinates to local coordinates on the target view.
	private void SetLocalCoords(MouseEventArgs e, View target)
	{
		let local = target.ToLocal(.(e.ScreenX, e.ScreenY));
		e.LocalX = local.X;
		e.LocalY = local.Y;
	}

	/// Bubble a mouse event up the parent chain until handled.
	private void BubbleMouseEvent(View start, MouseEventArgs e, delegate void(View, MouseEventArgs) handler)
	{
		var current = start;
		while (current != null && !e.Handled)
		{
			SetLocalCoords(e, current);
			handler(current, e);
			current = current.Parent;
		}
	}

	/// Bubble a mouse button event up the parent chain.
	private void BubbleMouseButtonEvent(View start, MouseButtonEventArgs e, delegate void(View, MouseButtonEventArgs) handler)
	{
		var current = start;
		while (current != null && !e.Handled)
		{
			SetLocalCoords(e, current);
			handler(current, e);
			current = current.Parent;
		}
	}

	/// Bubble a mouse wheel event up the parent chain.
	private void BubbleMouseWheelEvent(View start, MouseWheelEventArgs e)
	{
		var current = start;
		while (current != null && !e.Handled)
		{
			SetLocalCoords(e, current);
			current.OnMouseWheel(e);
			current = current.Parent;
		}
	}

	/// Bubble a key event up the parent chain.
	private void BubbleKeyEvent(View start, KeyEventArgs e, delegate void(View, KeyEventArgs) handler)
	{
		var current = start;
		while (current != null && !e.Handled)
		{
			handler(current, e);
			current = current.Parent;
		}
	}
}
