using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

class ControlStateTests
{
	[Test]
	public static void DefaultStateIsNormal()
	{
		Test.Assert((int)ControlState.Normal == 0);
	}

	[Test]
	public static void StateFlags()
	{
		let state = (ControlState)((int)ControlState.Focused | (int)ControlState.Hovered);
		Test.Assert(((int)state & (int)ControlState.Focused) != 0);
		Test.Assert(((int)state & (int)ControlState.Hovered) != 0);
		Test.Assert(((int)state & (int)ControlState.Pressed) == 0);
	}

	[Test]
	public static void DisabledPrecedence()
	{
		let state = (ControlState)((int)ControlState.Disabled | (int)ControlState.Focused | (int)ControlState.Hovered);
		Test.Assert(((int)state & (int)ControlState.Disabled) != 0);
	}
}

class StyleTests
{
	[Test]
	public static void StyleSetAndGet()
	{
		let style = scope Style();
		style.SetColor("Background", Color.Red);

		Test.Assert(style.TryGetColor("Background", .Normal, let color));
		Test.Assert(color == Color.Red);
	}

	[Test]
	public static void StyleWithStateOverride()
	{
		let style = scope Style();
		style.SetColor("Background", Color.White);

		let hoverStyle = style.AddStateStyle(.Hovered);
		hoverStyle.SetColor("Background", Color.LightGray);

		// Normal state gets base value
		Test.Assert(style.TryGetColor("Background", .Normal, let normalColor));
		Test.Assert(normalColor == Color.White);

		// Hovered state gets override
		Test.Assert(style.TryGetColor("Background", .Hovered, let hoverColor));
		Test.Assert(hoverColor == Color.LightGray);
	}

	[Test]
	public static void StyleFallsBackToBase()
	{
		let style = scope Style();
		style.SetColor("Background", Color.Blue);
		style.AddStateStyle(.Hovered); // Empty state style

		// Should fall back to base when state style doesn't have the property
		Test.Assert(style.TryGetColor("Background", .Hovered, let color));
		Test.Assert(color == Color.Blue);
	}

	[Test]
	public static void StyleMissingProperty()
	{
		let style = scope Style();
		style.SetColor("Background", Color.Red);

		Test.Assert(!style.TryGetColor("Foreground", .Normal, ?));
	}

	[Test]
	public static void StyleFloatProperty()
	{
		let style = scope Style();
		style.SetFloat("FontSize", 16.0f);

		Test.Assert(style.TryGetFloat("FontSize", .Normal, let size));
		Test.Assert(size == 16.0f);
	}

	[Test]
	public static void StyleThicknessProperty()
	{
		let style = scope Style();
		style.SetThickness("Padding", Thickness(10));

		Test.Assert(style.TryGetThickness("Padding", .Normal, let thickness));
		Test.Assert(thickness.Left == 10);
	}
}

class ThemeTests
{
	[Test]
	public static void ThemeCreation()
	{
		let theme = scope Theme();
		Test.Assert(theme.DefaultFontFamily == "Segoe UI");
		Test.Assert(theme.DefaultFontSize == 14.0f);
	}

	[Test]
	public static void ThemeSetColor()
	{
		let theme = scope Theme();
		theme.SetColor("Primary", Color.Blue);

		Test.Assert(theme.HasColor("Primary"));
		Test.Assert(theme.GetColor("Primary") == Color.Blue);
	}

	[Test]
	public static void ThemeMissingColorReturnsMagenta()
	{
		let theme = scope Theme();
		Test.Assert(theme.GetColor("NonExistent") == Color.Magenta);
	}

	[Test]
	public static void ThemeSetFontFamily()
	{
		let theme = scope Theme();
		theme.SetDefaultFontFamily("Arial");
		Test.Assert(theme.DefaultFontFamily == "Arial");
	}

	[Test]
	public static void ThemeSetFontSize()
	{
		let theme = scope Theme();
		theme.SetDefaultFontSize(18.0f);
		Test.Assert(theme.DefaultFontSize == 18.0f);
	}

	[Test]
	public static void ThemeRegisterStyle()
	{
		let theme = scope Theme();
		let style = new Style();
		style.SetColor("Background", Color.White);

		theme.RegisterStyle(typeof(Control), style);

		let retrieved = theme.GetStyle(typeof(Control));
		Test.Assert(retrieved != null);
		Test.Assert(retrieved.TryGetColor("Background", .Normal, ?));
	}

	[Test]
	public static void ThemeGetStyleReturnsNullForUnregistered()
	{
		let theme = scope Theme();
		Test.Assert(theme.GetStyle(typeof(Control)) == null);
	}
}

class DefaultThemeTests
{
	[Test]
	public static void DefaultThemeHasColors()
	{
		let theme = scope DefaultTheme();

		Test.Assert(theme.HasColor("Primary"));
		Test.Assert(theme.HasColor("Background"));
		Test.Assert(theme.HasColor("Foreground"));
		Test.Assert(theme.HasColor("Border"));
	}

	[Test]
	public static void DefaultThemeColorsAreValid()
	{
		let theme = scope DefaultTheme();

		let primary = theme.GetColor("Primary");
		Test.Assert(primary != Color.Magenta); // Magenta is the "missing" color

		let background = theme.GetColor("Background");
		Test.Assert(background == Color.White);
	}
}

class ControlThemeTests
{
	class TestControl : Control
	{
		public new ControlState ControlState
		{
			get => base.ControlState;
			set => base.ControlState = value;
		}
	}

	[Test]
	public static void ControlDefaultState()
	{
		let control = scope TestControl();
		Test.Assert(control.ControlState == .Normal);
	}

	[Test]
	public static void ControlBorderThickness()
	{
		let control = scope TestControl();
		control.BorderThickness = Thickness(2);

		Test.Assert(control.BorderThickness.Left == 2);
		Test.Assert(control.BorderThickness.Top == 2);
	}

	[Test]
	public static void ControlFontSizeDefault()
	{
		let control = scope TestControl();
		// Without a theme, should return default 14
		Test.Assert(control.FontSize == 14.0f);
	}

	[Test]
	public static void ControlFontSizeOverride()
	{
		let control = scope TestControl();
		control.FontSize = 20.0f;
		Test.Assert(control.FontSize == 20.0f);
	}

	[Test]
	public static void ControlWithTheme()
	{
		let context = new UIContext();
		defer delete context;

		let theme = new DefaultTheme();
		context.RegisterService<ITheme>(theme);

		// Verify service is registered
		Test.Assert(context.HasService<ITheme>());

		let control = scope TestControl();
		context.RootElement = control; // UIContext takes ownership

		// Control should have the context
		Test.Assert(control.Context == context);

		// GetTheme should find the theme via context
		let foundTheme = control.GetTheme();
		Test.Assert(foundTheme != null);
		Test.Assert(foundTheme == theme);

		delete theme;
	}

	[Test]
	public static void ControlStateChangeOnFocus()
	{
		let context = new UIContext();
		defer delete context;

		let control = scope TestControl();
		context.RootElement = control; // UIContext takes ownership

		// Verify control is focusable
		Test.Assert(control.Focusable);

		context.SetFocus(control);

		// Verify focus was set
		Test.Assert(context.FocusedElement == control);
		Test.Assert(control.IsFocused);

		// Check state includes Focused
		Test.Assert(((int)control.ControlState & (int)ControlState.Focused) != 0);
	}

	[Test]
	public static void ControlStyleOverridesTheme()
	{
		let context = new UIContext();
		defer delete context;

		let theme = new DefaultTheme();
		context.RegisterService<ITheme>(theme);

		let control = scope TestControl();
		context.RootElement = control; // UIContext takes ownership

		let customStyle = scope Style();
		customStyle.SetColor("Background", Color.Purple);
		control.Style = customStyle;

		Test.Assert(control.GetEffectiveStyle() == customStyle);

		delete theme;
	}
}
