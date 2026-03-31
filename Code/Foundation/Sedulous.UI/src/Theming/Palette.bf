namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;

/// A set of seed colors that define an application's color scheme.
/// Includes pure static utility methods for state-based color derivation.
public struct Palette
{
	public Color Primary;
	public Color Secondary;
	public Color Accent;
	public Color Background;
	public Color Surface;
	public Color Error;
	public Color Text;
	public Color Border;
	public Color Warning;
	public Color Success;

	//==========================================================================
	// Color manipulation utilities (pure, no allocation)
	//==========================================================================

	/// Lerp between two colors using Color.Interpolate.
	public static Color Lerp(Color a, Color b, float t)
	{
		return a.Interpolate(b, t);
	}

	/// Lighten a color by lerping RGB toward white, preserving alpha.
	public static Color Lighten(Color color, float amount)
	{
		let white = Color(255, 255, 255, (int32)color.A);
		return Lerp(color, white, Math.Clamp(amount, 0, 1));
	}

	/// Darken a color by lerping RGB toward black, preserving alpha.
	public static Color Darken(Color color, float amount)
	{
		let black = Color(0, 0, 0, (int32)color.A);
		return Lerp(color, black, Math.Clamp(amount, 0, 1));
	}

	/// Desaturate a color by lerping toward its luminance grayscale value.
	public static Color Desaturate(Color color, float amount)
	{
		let amt = Math.Clamp(amount, 0, 1);
		// Perceptual luminance weights
		let lum = (int32)(0.299f * color.R + 0.587f * color.G + 0.114f * color.B);
		let gray = Color(lum, lum, lum, (int32)color.A);
		return Lerp(color, gray, amt);
	}

	/// WithAlpha returns a color with the specified alpha (0-255).
	public static Color WithAlpha(Color color, uint8 alpha)
	{
		return Color((int32)color.R, (int32)color.G, (int32)color.B, (int32)alpha);
	}

	//==========================================================================
	// State derivation
	//==========================================================================

	/// Compute hover color: slightly lighter.
	public static Color ComputeHover(Color color)
	{
		return Lighten(color, 0.15f);
	}

	/// Compute pressed color: slightly darker.
	public static Color ComputePressed(Color color)
	{
		return Darken(color, 0.15f);
	}

	/// Compute disabled color: desaturated and half alpha.
	public static Color ComputeDisabled(Color color)
	{
		let desat = Desaturate(color, 0.5f);
		return WithAlpha(desat, (uint8)(desat.A / 2));
	}

	/// Compute focused color: blend toward accent.
	public static Color ComputeFocused(Color color, Color accent)
	{
		return Lerp(color, accent, 0.2f);
	}

	/// Resolve a base color to its visual state variant.
	public static Color ResolveState(Color baseColor, ControlState state, Color accent)
	{
		switch (state)
		{
		case .Hover:    return ComputeHover(baseColor);
		case .Pressed:  return ComputePressed(baseColor);
		case .Disabled: return ComputeDisabled(baseColor);
		case .Focused:  return ComputeFocused(baseColor, accent);
		case .Normal:   return baseColor;
		}
	}

	//==========================================================================
	// Predefined palettes
	//==========================================================================

	/// Dark palette extracted from the existing hardcoded control colors.
	public static Palette Dark => .()
	{
		Primary    = .(0.25f, 0.25f, 0.3f, 1.0f),
		Secondary  = .(0.2f, 0.2f, 0.25f, 1.0f),
		Accent     = .(0.3f, 0.5f, 0.9f, 1.0f),
		Background = .(0.12f, 0.12f, 0.15f, 1.0f),
		Surface    = .(0.18f, 0.18f, 0.22f, 1.0f),
		Error      = .(0.9f, 0.3f, 0.3f, 1.0f),
		Text       = .(0.95f, 0.95f, 0.95f, 1.0f),
		Border     = .(0.4f, 0.4f, 0.45f, 1.0f),
		Warning    = .(1.0f, 0.76f, 0.03f, 1.0f),
		Success    = .(0.30f, 0.69f, 0.31f, 1.0f)
	};

	/// Light palette.
	public static Palette Light => .()
	{
		Primary    = .(0.85f, 0.85f, 0.9f, 1.0f),
		Secondary  = .(0.75f, 0.75f, 0.8f, 1.0f),
		Accent     = .(0.2f, 0.4f, 0.8f, 1.0f),
		Background = .(0.95f, 0.95f, 0.96f, 1.0f),
		Surface    = .(1.0f, 1.0f, 1.0f, 1.0f),
		Error      = .(0.85f, 0.2f, 0.2f, 1.0f),
		Text       = .(0.1f, 0.1f, 0.1f, 1.0f),
		Border     = .(0.7f, 0.7f, 0.72f, 1.0f),
		Warning    = .(0.93f, 0.60f, 0.0f, 1.0f),
		Success    = .(0.24f, 0.55f, 0.24f, 1.0f)
	};
}
