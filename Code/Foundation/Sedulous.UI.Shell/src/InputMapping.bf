namespace Sedulous.UI.Shell;

/// Utility class for mapping Shell input types to UI input types.
/// Shared between Sedulous.Engine.UI and Sedulous.Engine.UI.
static class InputMapping
{
	/// Maps Shell.Input.KeyCode to UI.KeyCode.
	public static Sedulous.UI.KeyCode MapKey(Sedulous.Shell.Input.KeyCode shellKey)
	{
		switch (shellKey)
		{
		case .A: return .A;
		case .B: return .B;
		case .C: return .C;
		case .D: return .D;
		case .E: return .E;
		case .F: return .F;
		case .G: return .G;
		case .H: return .H;
		case .I: return .I;
		case .J: return .J;
		case .K: return .K;
		case .L: return .L;
		case .M: return .M;
		case .N: return .N;
		case .O: return .O;
		case .P: return .P;
		case .Q: return .Q;
		case .R: return .R;
		case .S: return .S;
		case .T: return .T;
		case .U: return .U;
		case .V: return .V;
		case .W: return .W;
		case .X: return .X;
		case .Y: return .Y;
		case .Z: return .Z;
		case .Num0: return .Num0;
		case .Num1: return .Num1;
		case .Num2: return .Num2;
		case .Num3: return .Num3;
		case .Num4: return .Num4;
		case .Num5: return .Num5;
		case .Num6: return .Num6;
		case .Num7: return .Num7;
		case .Num8: return .Num8;
		case .Num9: return .Num9;
		case .Return: return .Return;
		case .Escape: return .Escape;
		case .Backspace: return .Backspace;
		case .Tab: return .Tab;
		case .Space: return .Space;
		case .Left: return .Left;
		case .Right: return .Right;
		case .Up: return .Up;
		case .Down: return .Down;
		case .Home: return .Home;
		case .End: return .End;
		case .PageUp: return .PageUp;
		case .PageDown: return .PageDown;
		case .Delete: return .Delete;
		case .Insert: return .Insert;
		default: return .Unknown;
		}
	}

	/// Maps Shell.Input.KeyModifiers to UI.KeyModifiers.
	public static Sedulous.UI.KeyModifiers MapModifiers(Sedulous.Shell.Input.KeyModifiers shellMods)
	{
		Sedulous.UI.KeyModifiers result = .None;
		if (shellMods.HasFlag(.Shift))
			result |= .Shift;
		if (shellMods.HasFlag(.Ctrl))
			result |= .Ctrl;
		if (shellMods.HasFlag(.Alt))
			result |= .Alt;
		return result;
	}

	/// Maps Shell.Input.MouseButton to UI.MouseButton.
	public static Sedulous.UI.MouseButton MapMouseButton(Sedulous.Shell.Input.MouseButton shellButton)
	{
		return (.)shellButton;
	}

	/// Maps UI.CursorType to Shell.Input.CursorType.
	public static Sedulous.Shell.Input.CursorType MapCursor(Sedulous.UI.CursorType uiCursor)
	{
		switch (uiCursor)
		{
		case .Default:    return .Default;
		case .Text:       return .Text;
		case .Wait:       return .Wait;
		case .Crosshair:  return .Crosshair;
		case .Progress:   return .Progress;
		case .Move:       return .Move;
		case .NotAllowed: return .NotAllowed;
		case .Pointer:    return .Pointer;
		case .ResizeEW:   return .ResizeEW;
		case .ResizeNS:   return .ResizeNS;
		case .ResizeNWSE: return .ResizeNWSE;
		case .ResizeNESW: return .ResizeNESW;
		}
	}

	/// Converts a shell key code to a printable character.
	/// Returns '\0' if the key doesn't produce a printable character.
	/// This is a fallback for when SDL_StartTextInput is not active.
	/// Uses US keyboard layout.
	public static char32 KeyToChar(Sedulous.Shell.Input.KeyCode key, bool shift)
	{
		// Letters A-Z
		if (key >= .A && key <= .Z)
		{
			let baseChar = 'a' + (int)(key - .A);
			return shift ? (char32)((int)'A' + (int)(key - .A)) : (char32)baseChar;
		}

		// Common punctuation and numbers (US keyboard layout)
		switch (key)
		{
		// Top row numbers
		case .Num1: return shift ? '!' : '1';
		case .Num2: return shift ? '@' : '2';
		case .Num3: return shift ? '#' : '3';
		case .Num4: return shift ? '$' : '4';
		case .Num5: return shift ? '%' : '5';
		case .Num6: return shift ? '^' : '6';
		case .Num7: return shift ? '&' : '7';
		case .Num8: return shift ? '*' : '8';
		case .Num9: return shift ? '(' : '9';
		case .Num0: return shift ? ')' : '0';

		// Keypad numbers
		case .Keypad0: return '0';
		case .Keypad1: return '1';
		case .Keypad2: return '2';
		case .Keypad3: return '3';
		case .Keypad4: return '4';
		case .Keypad5: return '5';
		case .Keypad6: return '6';
		case .Keypad7: return '7';
		case .Keypad8: return '8';
		case .Keypad9: return '9';

		// Keypad operators
		case .KeypadDivide:   return '/';
		case .KeypadMultiply: return '*';
		case .KeypadMinus:    return '-';
		case .KeypadPlus:     return '+';
		case .KeypadPeriod:   return '.';

		// Punctuation
		case .Space:        return ' ';
		case .Minus:        return shift ? '_' : '-';
		case .Equals:       return shift ? '+' : '=';
		case .LeftBracket:  return shift ? '{' : '[';
		case .RightBracket: return shift ? '}' : ']';
		case .Backslash:    return shift ? '|' : '\\';
		case .Semicolon:    return shift ? ':' : ';';
		case .Apostrophe:   return shift ? '"' : '\'';
		case .Grave:        return shift ? '~' : '`';
		case .Comma:        return shift ? '<' : ',';
		case .Period:       return shift ? '>' : '.';
		case .Slash:        return shift ? '?' : '/';

		default:            return '\0';
		}
	}
}
