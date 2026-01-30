using System;
using Sedulous.Mathematics;

namespace Sedulous.GUI;

/// Style overrides for a specific visual state.
/// Null values inherit from the base ControlStyle.
public struct StateStyle
{
	public Color? Background;
	public Color? Foreground;
	public Color? BorderColor;
	public float? BorderThickness;
	public float? CornerRadius;

	/// Creates an empty state style (all values inherit).
	public static StateStyle Empty => .();

	/// Creates a state style with just a background override.
	public static StateStyle WithBackground(Color bg) => .() { Background = bg };

	/// Creates a state style with background and foreground overrides.
	public static StateStyle WithColors(Color bg, Color fg) => .() { Background = bg, Foreground = fg };
}

/// Style definition for a control type.
/// Contains base style plus per-state overrides.
public struct ControlStyle
{
	// Base style (used for Normal state)
	public Color Background;
	public Color Foreground;
	public Color BorderColor;
	public float BorderThickness;
	public float CornerRadius;

	// State overrides
	public StateStyle Hover;
	public StateStyle Pressed;
	public StateStyle Disabled;
	public StateStyle Focused;

	/// Gets the effective background color for the given state.
	public Color GetBackground(ControlState state)
	{
		switch (state)
		{
		case .Hover:
			return Hover.Background ?? Palette.ComputeHover(Background);
		case .Pressed:
			return Pressed.Background ?? Palette.ComputePressed(Background);
		case .Disabled:
			return Disabled.Background ?? Palette.ComputeDisabled(Background);
		case .Focused:
			return Focused.Background ?? Background;
		default:
			return Background;
		}
	}

	/// Gets the effective foreground color for the given state.
	public Color GetForeground(ControlState state)
	{
		switch (state)
		{
		case .Hover:
			return Hover.Foreground ?? Foreground;
		case .Pressed:
			return Pressed.Foreground ?? Foreground;
		case .Disabled:
			return Disabled.Foreground ?? Palette.ComputeDisabled(Foreground);
		case .Focused:
			return Focused.Foreground ?? Foreground;
		default:
			return Foreground;
		}
	}

	/// Gets the effective border color for the given state.
	public Color GetBorderColor(ControlState state)
	{
		switch (state)
		{
		case .Hover:
			return Hover.BorderColor ?? Palette.ComputeHover(BorderColor);
		case .Pressed:
			return Pressed.BorderColor ?? Palette.ComputePressed(BorderColor);
		case .Disabled:
			return Disabled.BorderColor ?? Palette.ComputeDisabled(BorderColor);
		case .Focused:
			return Focused.BorderColor ?? BorderColor;
		default:
			return BorderColor;
		}
	}

	/// Gets the effective border thickness for the given state.
	public float GetBorderThickness(ControlState state)
	{
		switch (state)
		{
		case .Hover:
			return Hover.BorderThickness ?? BorderThickness;
		case .Pressed:
			return Pressed.BorderThickness ?? BorderThickness;
		case .Disabled:
			return Disabled.BorderThickness ?? BorderThickness;
		case .Focused:
			return Focused.BorderThickness ?? BorderThickness + 1;
		default:
			return BorderThickness;
		}
	}
}
