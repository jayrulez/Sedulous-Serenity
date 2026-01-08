using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Base class for all input event arguments.
/// Supports event routing with a Handled flag.
public class InputEventArgs
{
	/// Whether this event has been handled and should stop propagating.
	public bool Handled;

	/// The original source element that received the event.
	public UIElement Source;

	/// Timestamp of the event.
	public double Timestamp;

	public this()
	{
	}

	/// Resets the event args for reuse.
	public virtual void Reset()
	{
		Handled = false;
		Source = null;
		Timestamp = 0;
	}
}

/// Keyboard modifier flags.
public enum KeyModifiers : int32
{
	None = 0,
	Shift = 1,
	Ctrl = 2,
	Alt = 4,
	Super = 8,   // Windows/Command key
	CapsLock = 16,
	NumLock = 32
}

/// Mouse button identifiers.
public enum MouseButton : int32
{
	Left = 0,
	Middle = 1,
	Right = 2,
	X1 = 3,
	X2 = 4
}

/// Event arguments for mouse events.
public class MouseEventArgs : InputEventArgs
{
	/// X position in screen coordinates.
	public float ScreenX;

	/// Y position in screen coordinates.
	public float ScreenY;

	/// X position relative to the target element.
	public float LocalX;

	/// Y position relative to the target element.
	public float LocalY;

	/// Keyboard modifiers active during the event.
	public KeyModifiers Modifiers;

	public this()
	{
	}

	/// Gets the screen position as a Vector2.
	public Vector2 ScreenPosition => .(ScreenX, ScreenY);

	/// Gets the local position as a Vector2.
	public Vector2 LocalPosition => .(LocalX, LocalY);

	public override void Reset()
	{
		base.Reset();
		ScreenX = 0;
		ScreenY = 0;
		LocalX = 0;
		LocalY = 0;
		Modifiers = .None;
	}
}

/// Event arguments for mouse button events.
public class MouseButtonEventArgs : MouseEventArgs
{
	/// The mouse button that triggered the event.
	public MouseButton Button;

	/// Number of clicks (1 = single, 2 = double, etc.).
	public int32 ClickCount = 1;

	public this()
	{
	}

	public override void Reset()
	{
		base.Reset();
		Button = .Left;
		ClickCount = 1;
	}
}

/// Event arguments for mouse wheel events.
public class MouseWheelEventArgs : MouseEventArgs
{
	/// Horizontal scroll delta.
	public float DeltaX;

	/// Vertical scroll delta.
	public float DeltaY;

	public this()
	{
	}

	public override void Reset()
	{
		base.Reset();
		DeltaX = 0;
		DeltaY = 0;
	}
}

/// Event arguments for keyboard events.
public class KeyEventArgs : InputEventArgs
{
	/// The key code of the key.
	public int32 KeyCode;

	/// The scan code of the key.
	public int32 ScanCode;

	/// Keyboard modifiers active during the event.
	public KeyModifiers Modifiers;

	/// Whether this is a repeat event (key held down).
	public bool IsRepeat;

	public this()
	{
	}

	/// Checks if a modifier is active.
	public bool HasModifier(KeyModifiers mod) => ((int32)Modifiers & (int32)mod) != 0;

	public override void Reset()
	{
		base.Reset();
		KeyCode = 0;
		ScanCode = 0;
		Modifiers = .None;
		IsRepeat = false;
	}
}

/// Event arguments for text input events.
public class TextInputEventArgs : InputEventArgs
{
	/// The character that was input.
	public char32 Character;

	public this()
	{
	}

	public override void Reset()
	{
		base.Reset();
		Character = 0;
	}
}

/// Event arguments for focus events.
public class FocusEventArgs : InputEventArgs
{
	/// The element that previously had focus (for GotFocus) or will receive focus (for LostFocus).
	public UIElement OtherElement;

	public this()
	{
	}

	public override void Reset()
	{
		base.Reset();
		OtherElement = null;
	}
}

/// Indicates whether the event should bubble up the tree.
public enum RoutingStrategy
{
	/// Event goes directly to target only.
	Direct,
	/// Event bubbles from target up to root.
	Bubble,
	/// Event tunnels from root down to target (Preview events).
	Tunnel
}
