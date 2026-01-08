using System;
using System.Collections;

namespace Sedulous.UI;

/// Manages input routing through the UI element tree.
/// Supports tunneling (Preview), bubbling, and direct event strategies.
public class InputManager
{
	private UIContext mContext;

	// Reusable event args to avoid allocations
	private MouseButtonEventArgs mMouseButtonArgs = new .() ~ delete _;
	private MouseEventArgs mMouseMoveArgs = new .() ~ delete _;
	private MouseWheelEventArgs mMouseWheelArgs = new .() ~ delete _;
	private KeyEventArgs mKeyArgs = new .() ~ delete _;
	private TextInputEventArgs mTextInputArgs = new .() ~ delete _;
	private FocusEventArgs mFocusArgs = new .() ~ delete _;

	// Current mouse state
	private float mLastMouseX;
	private float mLastMouseY;
	private bool[5] mButtonState; // Track state of 5 buttons

	// Double-click detection
	private double mLastClickTime;
	private MouseButton mLastClickButton;
	private float mLastClickX;
	private float mLastClickY;
	private int32 mClickCount;
	private const float DoubleClickTime = 0.5f; // 500ms
	private const float DoubleClickDistance = 4.0f; // pixels

	public this(UIContext context)
	{
		mContext = context;
	}

	/// Gets the current mouse X position.
	public float MouseX => mLastMouseX;

	/// Gets the current mouse Y position.
	public float MouseY => mLastMouseY;

	/// Checks if a mouse button is currently pressed.
	public bool IsButtonPressed(MouseButton button)
	{
		let idx = (int)button;
		return idx >= 0 && idx < 5 && mButtonState[idx];
	}

	/// Process mouse movement.
	public void ProcessMouseMove(float x, float y, KeyModifiers modifiers = .None)
	{
		mLastMouseX = x;
		mLastMouseY = y;

		let target = mContext.CapturedElement ?? mContext.HitTest(x, y);

		// Handle mouse enter/leave
		UpdateHoveredElement(target);

		// Route mouse move event
		if (target != null)
		{
			mMouseMoveArgs.Reset();
			mMouseMoveArgs.ScreenX = x;
			mMouseMoveArgs.ScreenY = y;
			mMouseMoveArgs.LocalX = x - target.Bounds.X;
			mMouseMoveArgs.LocalY = y - target.Bounds.Y;
			mMouseMoveArgs.Modifiers = modifiers;
			mMouseMoveArgs.Source = target;
			mMouseMoveArgs.Timestamp = mContext.TotalTime;

			RouteEvent(target, mMouseMoveArgs, .OnMouseMove);
		}
	}

	/// Process mouse button press.
	public void ProcessMouseDown(MouseButton button, float x, float y, KeyModifiers modifiers = .None)
	{
		let idx = (int)button;
		if (idx >= 0 && idx < 5)
			mButtonState[idx] = true;

		mLastMouseX = x;
		mLastMouseY = y;

		let target = mContext.CapturedElement ?? mContext.HitTest(x, y);

		// Handle click counting for double-click detection
		let clickCount = CalculateClickCount(button, x, y);

		if (target != null)
		{
			// Set focus on click
			if (target.Focusable)
				mContext.SetFocus(target);

			mMouseButtonArgs.Reset();
			mMouseButtonArgs.ScreenX = x;
			mMouseButtonArgs.ScreenY = y;
			mMouseButtonArgs.LocalX = x - target.Bounds.X;
			mMouseButtonArgs.LocalY = y - target.Bounds.Y;
			mMouseButtonArgs.Button = button;
			mMouseButtonArgs.ClickCount = clickCount;
			mMouseButtonArgs.Modifiers = modifiers;
			mMouseButtonArgs.Source = target;
			mMouseButtonArgs.Timestamp = mContext.TotalTime;

			RouteEvent(target, mMouseButtonArgs, .OnMouseDown);
		}
	}

	/// Process mouse button release.
	public void ProcessMouseUp(MouseButton button, float x, float y, KeyModifiers modifiers = .None)
	{
		let idx = (int)button;
		if (idx >= 0 && idx < 5)
			mButtonState[idx] = false;

		mLastMouseX = x;
		mLastMouseY = y;

		let target = mContext.CapturedElement ?? mContext.HitTest(x, y);
		if (target != null)
		{
			mMouseButtonArgs.Reset();
			mMouseButtonArgs.ScreenX = x;
			mMouseButtonArgs.ScreenY = y;
			mMouseButtonArgs.LocalX = x - target.Bounds.X;
			mMouseButtonArgs.LocalY = y - target.Bounds.Y;
			mMouseButtonArgs.Button = button;
			mMouseButtonArgs.ClickCount = mClickCount;
			mMouseButtonArgs.Modifiers = modifiers;
			mMouseButtonArgs.Source = target;
			mMouseButtonArgs.Timestamp = mContext.TotalTime;

			RouteEvent(target, mMouseButtonArgs, .OnMouseUp);
		}
	}

	/// Process mouse wheel scroll.
	public void ProcessMouseWheel(float deltaX, float deltaY, float x, float y, KeyModifiers modifiers = .None)
	{
		let target = mContext.HitTest(x, y);
		if (target != null)
		{
			mMouseWheelArgs.Reset();
			mMouseWheelArgs.ScreenX = x;
			mMouseWheelArgs.ScreenY = y;
			mMouseWheelArgs.LocalX = x - target.Bounds.X;
			mMouseWheelArgs.LocalY = y - target.Bounds.Y;
			mMouseWheelArgs.DeltaX = deltaX;
			mMouseWheelArgs.DeltaY = deltaY;
			mMouseWheelArgs.Modifiers = modifiers;
			mMouseWheelArgs.Source = target;
			mMouseWheelArgs.Timestamp = mContext.TotalTime;

			RouteEvent(target, mMouseWheelArgs, .OnMouseWheel);
		}
	}

	/// Process key down event.
	public void ProcessKeyDown(KeyCode key, int32 scanCode = 0, KeyModifiers modifiers = .None, bool isRepeat = false)
	{
		let target = mContext.FocusedElement;
		if (target != null)
		{
			mKeyArgs.Reset();
			mKeyArgs.Key = key;
			mKeyArgs.ScanCode = scanCode;
			mKeyArgs.Modifiers = modifiers;
			mKeyArgs.IsRepeat = isRepeat;
			mKeyArgs.Source = target;
			mKeyArgs.Timestamp = mContext.TotalTime;

			RouteEvent(target, mKeyArgs, .OnKeyDown);
		}
	}

	/// Process key up event.
	public void ProcessKeyUp(KeyCode key, int32 scanCode = 0, KeyModifiers modifiers = .None)
	{
		let target = mContext.FocusedElement;
		if (target != null)
		{
			mKeyArgs.Reset();
			mKeyArgs.Key = key;
			mKeyArgs.ScanCode = scanCode;
			mKeyArgs.Modifiers = modifiers;
			mKeyArgs.IsRepeat = false;
			mKeyArgs.Source = target;
			mKeyArgs.Timestamp = mContext.TotalTime;

			RouteEvent(target, mKeyArgs, .OnKeyUp);
		}
	}

	/// Process text input event.
	public void ProcessTextInput(char32 character)
	{
		let target = mContext.FocusedElement;
		if (target != null)
		{
			mTextInputArgs.Reset();
			mTextInputArgs.Character = character;
			mTextInputArgs.Source = target;
			mTextInputArgs.Timestamp = mContext.TotalTime;

			RouteEvent(target, mTextInputArgs, .OnTextInput);
		}
	}

	/// Updates the hovered element and fires enter/leave events.
	private void UpdateHoveredElement(UIElement newHovered)
	{
		let oldHovered = mContext.[Friend]mHoveredElement;

		if (newHovered != oldHovered)
		{
			// Fire leave event on old hovered element
			if (oldHovered != null)
			{
				oldHovered.[Friend]OnMouseLeave();
			}

			mContext.[Friend]mHoveredElement = newHovered;

			// Fire enter event on new hovered element
			if (newHovered != null)
			{
				newHovered.[Friend]OnMouseEnter();
			}
		}
	}

	/// Calculates click count for double-click detection.
	private int32 CalculateClickCount(MouseButton button, float x, float y)
	{
		let currentTime = mContext.TotalTime;
		let timeSinceLastClick = currentTime - mLastClickTime;
		let dx = x - mLastClickX;
		let dy = y - mLastClickY;
		let distance = Math.Sqrt(dx * dx + dy * dy);

		if (button == mLastClickButton &&
			timeSinceLastClick < DoubleClickTime &&
			distance < DoubleClickDistance)
		{
			mClickCount++;
		}
		else
		{
			mClickCount = 1;
		}

		mLastClickTime = currentTime;
		mLastClickButton = button;
		mLastClickX = x;
		mLastClickY = y;

		return mClickCount;
	}

	/// Input event types for routing.
	private enum InputEventType
	{
		OnMouseMove,
		OnMouseDown,
		OnMouseUp,
		OnMouseWheel,
		OnKeyDown,
		OnKeyUp,
		OnTextInput
	}

	/// Routes an event through the element tree with bubbling support.
	private void RouteEvent(UIElement target, InputEventArgs args, InputEventType eventType)
	{
		// Currently using bubbling strategy: start at target, bubble up to root
		var current = target;

		while (current != null && !args.Handled)
		{
			// Update local coordinates for mouse events
			if (let mouseArgs = args as MouseEventArgs)
			{
				mouseArgs.LocalX = mouseArgs.ScreenX - current.Bounds.X;
				mouseArgs.LocalY = mouseArgs.ScreenY - current.Bounds.Y;
			}

			// Dispatch to the element
			DispatchToElement(current, args, eventType);

			// Bubble up to parent
			current = current.Parent;
		}
	}

	/// Dispatches an event to a specific element.
	private void DispatchToElement(UIElement element, InputEventArgs args, InputEventType eventType)
	{
		switch (eventType)
		{
		case .OnMouseMove:
			if (let mouseArgs = args as MouseEventArgs)
				element.[Friend]OnMouseMoveRouted(mouseArgs);
		case .OnMouseDown:
			if (let btnArgs = args as MouseButtonEventArgs)
				element.[Friend]OnMouseDownRouted(btnArgs);
		case .OnMouseUp:
			if (let btnArgs = args as MouseButtonEventArgs)
				element.[Friend]OnMouseUpRouted(btnArgs);
		case .OnMouseWheel:
			if (let wheelArgs = args as MouseWheelEventArgs)
				element.[Friend]OnMouseWheelRouted(wheelArgs);
		case .OnKeyDown:
			if (let keyArgs = args as KeyEventArgs)
				element.[Friend]OnKeyDownRouted(keyArgs);
		case .OnKeyUp:
			if (let keyArgs = args as KeyEventArgs)
				element.[Friend]OnKeyUpRouted(keyArgs);
		case .OnTextInput:
			if (let textArgs = args as TextInputEventArgs)
				element.[Friend]OnTextInputRouted(textArgs);
		}
	}
}
