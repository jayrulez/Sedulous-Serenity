using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Color definition that can be solid or gradient.
struct ThemeColor
{
	/// Primary color value.
	public Color Primary;
	/// Secondary color for gradients.
	public Color Secondary;
	/// Whether this is a gradient color.
	public bool IsGradient;
	/// Angle in degrees for gradient direction (0 = left to right).
	public float GradientAngle;

	/// Creates a solid color.
	public this(Color color)
	{
		Primary = color;
		Secondary = color;
		IsGradient = false;
		GradientAngle = 0;
	}

	/// Creates a gradient color.
	public this(Color primary, Color secondary, float angle = 0)
	{
		Primary = primary;
		Secondary = secondary;
		IsGradient = true;
		GradientAngle = angle;
	}

	/// Creates a solid color from RGBA values.
	public static ThemeColor FromRGBA(uint8 r, uint8 g, uint8 b, uint8 a = 255)
	{
		return ThemeColor(Color(r, g, b, a));
	}

	/// Creates a solid white color.
	public static ThemeColor White => ThemeColor(.White);

	/// Creates a solid black color.
	public static ThemeColor Black => ThemeColor(Color(0, 0, 0, 255));

	/// Creates a transparent color.
	public static ThemeColor Transparent => ThemeColor(Color(0, 0, 0, 0));

	/// Gets the color to use for rendering (returns Primary for solid colors).
	public Color GetColor() => Primary;

	/// Gets interpolated color at a position (0-1) for gradients.
	public Color GetColorAt(float t)
	{
		var t;
		if (!IsGradient)
			return Primary;

		t = Math.Clamp(t, 0, 1);
		return Color(
			(uint8)(Primary.R + (Secondary.R - Primary.R) * t),
			(uint8)(Primary.G + (Secondary.G - Primary.G) * t),
			(uint8)(Primary.B + (Secondary.B - Primary.B) * t),
			(uint8)(Primary.A + (Secondary.A - Primary.A) * t)
		);
	}

	/// Implicit conversion from Color.
	public static implicit operator ThemeColor(Color color) => ThemeColor(color);
}

/// Theme resource types.
enum ThemeResourceType
{
	/// Color resource.
	Color,
	/// Float/numeric resource.
	Float,
	/// Font resource.
	Font,
	/// Texture resource.
	Texture,
	/// Style resource.
	Style
}
