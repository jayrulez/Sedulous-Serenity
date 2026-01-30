using System;
using Sedulous.Mathematics;

namespace Sedulous.GUI;

/// Manages input routing for a GUIContext.
/// Routes mouse and keyboard events to the appropriate UI elements.
public class InputManager
{
	private GUIContext mContext;
	private UIElement mHoveredElement;
	private Vector2 mLastMousePosition;

	/// Creates an InputManager for the specified context.
	public this(GUIContext context)
	{
		mContext = context;
	}

	/// The element currently under the mouse cursor.
	public UIElement HoveredElement => mHoveredElement;

	/// The last known mouse position.
	public Vector2 LastMousePosition => mLastMousePosition;

	/// Process a mouse move event.
	public void ProcessMouseMove(float x, float y)
	{
		mLastMousePosition = .(x, y);

		// If there's a capture, route to captured element
		let captured = mContext.FocusManager?.CapturedElement;
		if (captured != null)
		{
			let args = scope MouseEventArgs(x, y);
			InvokeMouseMove(captured, args);
			return;
		}

		// Hit test to find element under cursor
		let hitElement = mContext.HitTest(x, y);

		// Handle enter/leave
		if (hitElement != mHoveredElement)
		{
			// Leave old element
			if (mHoveredElement != null)
			{
				let leaveArgs = scope MouseEventArgs(x, y);
				InvokeMouseLeave(mHoveredElement, leaveArgs);
			}

			mHoveredElement = hitElement;

			// Enter new element
			if (mHoveredElement != null)
			{
				let enterArgs = scope MouseEventArgs(x, y);
				InvokeMouseEnter(mHoveredElement, enterArgs);
			}
		}

		// Send move event
		if (hitElement != null)
		{
			let args = scope MouseEventArgs(x, y);
			InvokeMouseMove(hitElement, args);
		}
	}

	/// Process a mouse button down event.
	public void ProcessMouseDown(float x, float y, MouseButton button)
	{
		mLastMousePosition = .(x, y);

		// If there's a capture, route to captured element
		let captured = mContext.FocusManager?.CapturedElement;
		if (captured != null)
		{
			let args = scope MouseButtonEventArgs(x, y, button);
			InvokeMouseDown(captured, args);
			return;
		}

		let hitElement = mContext.HitTest(x, y);
		if (hitElement != null)
		{
			let args = scope MouseButtonEventArgs(x, y, button);
			InvokeMouseDown(hitElement, args);
		}
	}

	/// Process a mouse button up event.
	public void ProcessMouseUp(float x, float y, MouseButton button)
	{
		mLastMousePosition = .(x, y);

		// If there's a capture, route to captured element
		let captured = mContext.FocusManager?.CapturedElement;
		if (captured != null)
		{
			let args = scope MouseButtonEventArgs(x, y, button);
			InvokeMouseUp(captured, args);
			return;
		}

		let hitElement = mContext.HitTest(x, y);
		if (hitElement != null)
		{
			let args = scope MouseButtonEventArgs(x, y, button);
			InvokeMouseUp(hitElement, args);
		}
	}

	/// Process a mouse wheel event.
	public void ProcessMouseWheel(float x, float y, float delta)
	{
		mLastMousePosition = .(x, y);

		let hitElement = mContext.HitTest(x, y);
		if (hitElement != null)
		{
			let args = scope MouseWheelEventArgs(x, y, delta);
			InvokeMouseWheel(hitElement, args);
		}
	}

	/// Process a key down event.
	public void ProcessKeyDown(KeyCode key, KeyModifiers modifiers)
	{
		// Handle Tab navigation
		if (key == .Tab)
		{
			if (modifiers.HasFlag(.Shift))
				mContext.FocusManager?.FocusPrevious();
			else
				mContext.FocusManager?.FocusNext();
			return;
		}

		// Route to focused element
		let focused = mContext.FocusManager?.FocusedElement;
		if (focused != null)
		{
			let args = scope KeyEventArgs(key, modifiers);
			InvokeKeyDown(focused, args);
		}
	}

	/// Process a key up event.
	public void ProcessKeyUp(KeyCode key, KeyModifiers modifiers)
	{
		let focused = mContext.FocusManager?.FocusedElement;
		if (focused != null)
		{
			let args = scope KeyEventArgs(key, modifiers);
			InvokeKeyUp(focused, args);
		}
	}

	/// Process a text input event.
	public void ProcessTextInput(char32 character)
	{
		let focused = mContext.FocusManager?.FocusedElement;
		if (focused != null)
		{
			let args = scope TextInputEventArgs(character);
			InvokeTextInput(focused, args);
		}
	}

	/// Called when an element is about to be deleted.
	/// Clears hover state if necessary.
	public void OnElementDeleted(UIElement element)
	{
		if (mHoveredElement == element)
			mHoveredElement = null;
	}

	// === Internal event invocation ===
	// Control.OnMouseEnter/Leave already handles IsHovered/IsPressed state

	private void InvokeMouseEnter(UIElement element, MouseEventArgs args)
	{
		element.[Friend]OnMouseEnter(args);
	}

	private void InvokeMouseLeave(UIElement element, MouseEventArgs args)
	{
		element.[Friend]OnMouseLeave(args);
	}

	private void InvokeMouseMove(UIElement element, MouseEventArgs args)
	{
		element.[Friend]OnMouseMove(args);
	}

	private void InvokeMouseDown(UIElement element, MouseButtonEventArgs args)
	{
		element.[Friend]OnMouseDown(args);
	}

	private void InvokeMouseUp(UIElement element, MouseButtonEventArgs args)
	{
		element.[Friend]OnMouseUp(args);
	}

	private void InvokeMouseWheel(UIElement element, MouseWheelEventArgs args)
	{
		element.[Friend]OnMouseWheel(args);
	}

	private void InvokeKeyDown(UIElement element, KeyEventArgs args)
	{
		element.[Friend]OnKeyDown(args);
	}

	private void InvokeKeyUp(UIElement element, KeyEventArgs args)
	{
		element.[Friend]OnKeyUp(args);
	}

	private void InvokeTextInput(UIElement element, TextInputEventArgs args)
	{
		element.[Friend]OnTextInput(args);
	}
}
