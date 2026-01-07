using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Manages input routing and focus for the UI.
class InputManager
{
	private UIContext mContext;
	private Widget mFocusedWidget;
	private Widget mHoveredWidget;
	private Widget mCapturedWidget;
	private Vector2 mLastMousePosition;
	private KeyModifiers mCurrentModifiers;

	/// Creates an input manager for the specified context.
	public this(UIContext context)
	{
		mContext = context;
	}

	/// Gets the currently focused widget.
	public Widget FocusedWidget => mFocusedWidget;

	/// Gets the currently hovered widget.
	public Widget HoveredWidget => mHoveredWidget;

	/// Gets the widget that has mouse capture.
	public Widget CapturedWidget => mCapturedWidget;

	/// Gets the current mouse position.
	public Vector2 MousePosition => mLastMousePosition;

	/// Gets the current key modifiers.
	public KeyModifiers Modifiers => mCurrentModifiers;

	// ============ Mouse Capture ============

	/// Captures the mouse to the specified widget.
	public void CaptureMouse(Widget widget)
	{
		mCapturedWidget = widget;
	}

	/// Releases mouse capture.
	public void ReleaseMouse()
	{
		mCapturedWidget = null;
	}

	// ============ Focus Management ============

	/// Sets focus to the specified widget.
	public bool SetFocus(Widget widget)
	{
		if (widget == mFocusedWidget)
			return true;

		if (widget != null && (!widget.IsFocusable || !widget.IsEnabled))
			return false;

		// Notify old widget of lost focus
		if (mFocusedWidget != null)
		{
			mFocusedWidget.[Friend]OnLostFocus();
		}

		mFocusedWidget = widget;

		// Notify new widget of gained focus
		if (mFocusedWidget != null)
		{
			mFocusedWidget.[Friend]OnGotFocus();
		}

		return true;
	}

	/// Clears the current focus.
	public void ClearFocus()
	{
		SetFocus(null);
	}

	/// Moves focus in the specified direction.
	public bool MoveFocus(FocusDirection direction)
	{
		// TODO: Implement tab navigation
		// This requires traversing the widget tree in tab order
		return false;
	}

	// ============ Input Processing ============

	/// Processes mouse movement.
	public void ProcessMouseMove(Vector2 position)
	{
		let delta = position - mLastMousePosition;
		mLastMousePosition = position;

		// Find widget under mouse
		Widget targetWidget = mCapturedWidget;
		if (targetWidget == null && mContext.Root != null)
		{
			targetWidget = mContext.Root.HitTestRecursive(position);
		}

		// Handle hover changes
		if (targetWidget != mHoveredWidget)
		{
			// Mouse leave old widget
			if (mHoveredWidget != null)
			{
				let args = scope MouseEventArgs(
					mHoveredWidget.ScreenToLocal(position),
					position,
					mCurrentModifiers
				);
				mHoveredWidget.[Friend]OnMouseLeave(args);
			}

			mHoveredWidget = targetWidget;

			// Mouse enter new widget
			if (mHoveredWidget != null)
			{
				let args = scope MouseEventArgs(
					mHoveredWidget.ScreenToLocal(position),
					position,
					mCurrentModifiers
				);
				mHoveredWidget.[Friend]OnMouseEnter(args);
			}
		}

		// Send mouse move to target
		if (targetWidget != null)
		{
			let args = scope MouseMoveEventArgs(
				targetWidget.ScreenToLocal(position),
				position,
				delta,
				mCurrentModifiers
			);
			BubbleMouseMove(targetWidget, args);
		}
	}

	/// Processes mouse button press or release.
	public void ProcessMouseButton(MouseButton button, bool pressed, Vector2 position)
	{
		mLastMousePosition = position;

		// Find target widget
		Widget targetWidget = mCapturedWidget;
		if (targetWidget == null && mContext.Root != null)
		{
			targetWidget = mContext.Root.HitTestRecursive(position);
		}

		if (targetWidget != null)
		{
			let args = scope MouseButtonEventArgs(
				targetWidget.ScreenToLocal(position),
				position,
				button,
				1, // TODO: Track click count for double-clicks
				mCurrentModifiers
			);

			if (pressed)
			{
				// Set focus on click
				if (targetWidget.IsFocusable)
					SetFocus(targetWidget);

				BubbleMouseDown(targetWidget, args);
			}
			else
			{
				BubbleMouseUp(targetWidget, args);
			}
		}
	}

	/// Processes mouse wheel scrolling.
	public void ProcessMouseWheel(float deltaX, float deltaY, Vector2 position)
	{
		// Find target widget
		Widget targetWidget = mCapturedWidget;
		if (targetWidget == null && mContext.Root != null)
		{
			targetWidget = mContext.Root.HitTestRecursive(position);
		}

		if (targetWidget != null)
		{
			let args = scope MouseWheelEventArgs(
				targetWidget.ScreenToLocal(position),
				position,
				deltaX,
				deltaY,
				mCurrentModifiers
			);
			BubbleMouseWheel(targetWidget, args);
		}
	}

	/// Processes key down event.
	public void ProcessKeyDown(KeyCode key, KeyModifiers modifiers, bool isRepeat)
	{
		mCurrentModifiers = modifiers;

		if (mFocusedWidget != null)
		{
			let args = scope KeyEventArgs(key, modifiers, isRepeat);
			BubbleKeyDown(mFocusedWidget, args);

			// Handle tab navigation if not handled
			if (!args.Handled && key == .Tab)
			{
				let direction = modifiers.HasFlag(.Shift) ? FocusDirection.Previous : FocusDirection.Next;
				MoveFocus(direction);
			}
		}
	}

	/// Processes key up event.
	public void ProcessKeyUp(KeyCode key, KeyModifiers modifiers)
	{
		mCurrentModifiers = modifiers;

		if (mFocusedWidget != null)
		{
			let args = scope KeyEventArgs(key, modifiers, false);
			BubbleKeyUp(mFocusedWidget, args);
		}
	}

	/// Processes text input.
	public void ProcessTextInput(StringView text)
	{
		if (mFocusedWidget != null)
		{
			let args = scope TextInputEventArgs(text);
			BubbleTextInput(mFocusedWidget, args);
		}
	}

	// ============ Event Bubbling ============

	private void BubbleMouseMove(Widget target, MouseMoveEventArgs args)
	{
		var current = target;
		while (current != null && !args.Handled)
		{
			if (current.[Friend]OnMouseMove(args))
				args.Handled = true;
			current = current.Parent;
		}
	}

	private void BubbleMouseDown(Widget target, MouseButtonEventArgs args)
	{
		var current = target;
		while (current != null && !args.Handled)
		{
			if (current.[Friend]OnMouseDown(args))
				args.Handled = true;
			current = current.Parent;
		}
	}

	private void BubbleMouseUp(Widget target, MouseButtonEventArgs args)
	{
		var current = target;
		while (current != null && !args.Handled)
		{
			if (current.[Friend]OnMouseUp(args))
				args.Handled = true;
			current = current.Parent;
		}
	}

	private void BubbleMouseWheel(Widget target, MouseWheelEventArgs args)
	{
		var current = target;
		while (current != null && !args.Handled)
		{
			if (current.[Friend]OnMouseWheel(args))
				args.Handled = true;
			current = current.Parent;
		}
	}

	private void BubbleKeyDown(Widget target, KeyEventArgs args)
	{
		var current = target;
		while (current != null && !args.Handled)
		{
			if (current.[Friend]OnKeyDown(args))
				args.Handled = true;
			current = current.Parent;
		}
	}

	private void BubbleKeyUp(Widget target, KeyEventArgs args)
	{
		var current = target;
		while (current != null && !args.Handled)
		{
			if (current.[Friend]OnKeyUp(args))
				args.Handled = true;
			current = current.Parent;
		}
	}

	private void BubbleTextInput(Widget target, TextInputEventArgs args)
	{
		var current = target;
		while (current != null && !args.Handled)
		{
			if (current.[Friend]OnTextInput(args))
				args.Handled = true;
			current = current.Parent;
		}
	}
}
