using System;
using Sedulous.Mathematics;

namespace Sedulous.GUI;

/// Manages input routing for a GUIContext.
/// Routes mouse and keyboard events to the appropriate UI elements.
public class InputManager
{
	private GUIContext mContext;
	private ElementHandle<UIElement> mHoveredElement;
	private Vector2 mLastMousePosition;

	/// Creates an InputManager for the specified context.
	public this(GUIContext context)
	{
		mContext = context;
		mHoveredElement = .Invalid;
	}

	/// The element currently under the mouse cursor (null if deleted or none).
	public UIElement HoveredElement => mHoveredElement.TryResolve();

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

		// Hit test to find element under cursor (coordinates are already logical)
		let hitElement = mContext.HitTestLogical(x, y);

		// Get current hovered element (may be null if deleted)
		let currentHovered = mHoveredElement.TryResolve();

		// Handle enter/leave
		if (hitElement != currentHovered)
		{
			// Leave old element (only if still valid)
			if (currentHovered != null)
			{
				let leaveArgs = scope MouseEventArgs(x, y);
				InvokeMouseLeave(currentHovered, leaveArgs);
			}

			mHoveredElement = hitElement;

			// Enter new element
			if (hitElement != null)
			{
				let enterArgs = scope MouseEventArgs(x, y);
				InvokeMouseEnter(hitElement, enterArgs);
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
	public void ProcessMouseDown(float x, float y, MouseButton button, KeyModifiers modifiers = .None)
	{
		mLastMousePosition = .(x, y);

		// If there's a capture, route to captured element
		let captured = mContext.FocusManager?.CapturedElement;
		if (captured != null)
		{
			let args = scope MouseButtonEventArgs(x, y, button, modifiers);
			InvokeMouseDown(captured, args);
			return;
		}

		let hitElement = mContext.HitTestLogical(x, y);
		if (hitElement != null)
		{
			let args = scope MouseButtonEventArgs(x, y, button, modifiers);
			InvokeMouseDown(hitElement, args);

			// If clicked element is not focusable and didn't handle the event
			// (e.g., Label focusing its target), clear focus
			if (!hitElement.IsFocusable && !args.Handled)
			{
				mContext.FocusManager?.ClearFocus();
			}
		}
		else
		{
			// Clicked on empty space - clear focus
			mContext.FocusManager?.ClearFocus();
		}
	}

	/// Process a mouse button up event.
	public void ProcessMouseUp(float x, float y, MouseButton button, KeyModifiers modifiers = .None)
	{
		mLastMousePosition = .(x, y);

		// If there's a capture, route to captured element
		let captured = mContext.FocusManager?.CapturedElement;
		if (captured != null)
		{
			let args = scope MouseButtonEventArgs(x, y, button, modifiers);
			InvokeMouseUp(captured, args);
			return;
		}

		let hitElement = mContext.HitTestLogical(x, y);
		if (hitElement != null)
		{
			let args = scope MouseButtonEventArgs(x, y, button, modifiers);
			InvokeMouseUp(hitElement, args);
		}
	}

	/// Process a mouse wheel event.
	public void ProcessMouseWheel(float x, float y, float delta, KeyModifiers modifiers = .None)
	{
		mLastMousePosition = .(x, y);

		let hitElement = mContext.HitTestLogical(x, y);
		if (hitElement != null)
		{
			let args = scope MouseWheelEventArgs(x, y, delta, modifiers);
			InvokeMouseWheel(hitElement, args);
		}
	}

	/// Process a key down event.
	public void ProcessKeyDown(KeyCode key, KeyModifiers modifiers)
	{
		// Handle Tab navigation (but not Ctrl+Tab which controls use for tab cycling)
		if (key == .Tab && !modifiers.HasFlag(.Ctrl))
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
		if (mHoveredElement.Id == element.Id)
			mHoveredElement = .Invalid;
	}

	// === Internal event invocation ===
	// Control.OnMouseEnter/Leave already handles IsHovered/IsPressed state

	/// Converts screen coordinates in the event args to local coordinates relative to the element.
	private void ConvertToLocalCoordinates(UIElement element, MouseEventArgs args)
	{
		args.LocalX = args.ScreenX - element.ArrangedBounds.X;
		args.LocalY = args.ScreenY - element.ArrangedBounds.Y;
	}

	private void InvokeMouseEnter(UIElement element, MouseEventArgs args)
	{
		ConvertToLocalCoordinates(element, args);
		element.[Friend]OnMouseEnter(args);
	}

	private void InvokeMouseLeave(UIElement element, MouseEventArgs args)
	{
		ConvertToLocalCoordinates(element, args);
		element.[Friend]OnMouseLeave(args);
	}

	private void InvokeMouseMove(UIElement element, MouseEventArgs args)
	{
		ConvertToLocalCoordinates(element, args);
		element.[Friend]OnMouseMove(args);
	}

	private void InvokeMouseDown(UIElement element, MouseButtonEventArgs args)
	{
		ConvertToLocalCoordinates(element, args);
		element.[Friend]OnMouseDown(args);
	}

	private void InvokeMouseUp(UIElement element, MouseButtonEventArgs args)
	{
		ConvertToLocalCoordinates(element, args);
		element.[Friend]OnMouseUp(args);
	}

	private void InvokeMouseWheel(UIElement element, MouseWheelEventArgs args)
	{
		// Bubble the mouse wheel event up through ancestors until handled
		var current = element;
		while (current != null && !args.Handled)
		{
			ConvertToLocalCoordinates(current, args);
			current.[Friend]OnMouseWheel(args);
			current = current.Parent;
		}
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
