using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Base class for mouse events.
class MouseEventArgs
{
	/// Position relative to the widget.
	public Vector2 Position;
	/// Position in screen coordinates.
	public Vector2 ScreenPosition;
	/// Active key modifiers.
	public KeyModifiers Modifiers;
	/// Whether the event has been handled.
	public bool Handled;

	/// Creates mouse event args.
	public this(Vector2 position, Vector2 screenPosition, KeyModifiers modifiers = .None)
	{
		Position = position;
		ScreenPosition = screenPosition;
		Modifiers = modifiers;
		Handled = false;
	}
}

/// Mouse move event arguments.
class MouseMoveEventArgs : MouseEventArgs
{
	/// Movement delta since last event.
	public Vector2 Delta;

	/// Creates mouse move event args.
	public this(Vector2 position, Vector2 screenPosition, Vector2 delta, KeyModifiers modifiers = .None)
		: base(position, screenPosition, modifiers)
	{
		Delta = delta;
	}
}

/// Mouse button event arguments.
class MouseButtonEventArgs : MouseEventArgs
{
	/// The button that was pressed or released.
	public MouseButton Button;
	/// Number of consecutive clicks (1 = single, 2 = double, etc.).
	public int ClickCount;

	/// Creates mouse button event args.
	public this(Vector2 position, Vector2 screenPosition, MouseButton button, int clickCount = 1, KeyModifiers modifiers = .None)
		: base(position, screenPosition, modifiers)
	{
		Button = button;
		ClickCount = clickCount;
	}
}

/// Mouse wheel event arguments.
class MouseWheelEventArgs : MouseEventArgs
{
	/// Horizontal scroll amount.
	public float DeltaX;
	/// Vertical scroll amount.
	public float DeltaY;

	/// Creates mouse wheel event args.
	public this(Vector2 position, Vector2 screenPosition, float deltaX, float deltaY, KeyModifiers modifiers = .None)
		: base(position, screenPosition, modifiers)
	{
		DeltaX = deltaX;
		DeltaY = deltaY;
	}
}

/// Key event arguments.
class KeyEventArgs
{
	/// The key that was pressed or released.
	public KeyCode Key;
	/// Active key modifiers.
	public KeyModifiers Modifiers;
	/// Whether this is a key repeat.
	public bool IsRepeat;
	/// Whether the event has been handled.
	public bool Handled;

	/// Creates key event args.
	public this(KeyCode key, KeyModifiers modifiers = .None, bool isRepeat = false)
	{
		Key = key;
		Modifiers = modifiers;
		IsRepeat = isRepeat;
		Handled = false;
	}
}

/// Text input event arguments.
class TextInputEventArgs
{
	/// The text that was input.
	public String Text ~ delete _;
	/// Whether the event has been handled.
	public bool Handled;

	/// Creates text input event args.
	public this(StringView text)
	{
		Text = new String(text);
		Handled = false;
	}
}

/// Common key codes.
enum KeyCode
{
	Unknown = 0,

	// Letters
	A, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,

	// Numbers
	Num0, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9,

	// Function keys
	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,

	// Special keys
	Escape,
	Tab,
	CapsLock,
	Shift,
	Control,
	Alt,
	Space,
	Enter,
	Backspace,
	Delete,
	Insert,
	Home,
	End,
	PageUp,
	PageDown,

	// Arrow keys
	Left,
	Right,
	Up,
	Down,

	// Punctuation
	Minus,
	Equals,
	LeftBracket,
	RightBracket,
	Backslash,
	Semicolon,
	Apostrophe,
	Grave,
	Comma,
	Period,
	Slash,

	// Numpad
	NumPad0, NumPad1, NumPad2, NumPad3, NumPad4,
	NumPad5, NumPad6, NumPad7, NumPad8, NumPad9,
	NumPadDecimal,
	NumPadDivide,
	NumPadMultiply,
	NumPadSubtract,
	NumPadAdd,
	NumPadEnter,
	NumLock,

	// Misc
	PrintScreen,
	ScrollLock,
	Pause,
	Menu
}
