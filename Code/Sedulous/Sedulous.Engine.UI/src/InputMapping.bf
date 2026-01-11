namespace Sedulous.Engine.UI;

/// Utility class for mapping Shell input types to UI input types.
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
	/// These have the same values so we can cast directly.
	public static Sedulous.UI.MouseButton MapMouseButton(Sedulous.Shell.Input.MouseButton shellButton)
	{
		return (.)shellButton;
	}
}
