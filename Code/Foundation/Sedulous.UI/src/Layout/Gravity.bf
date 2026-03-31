namespace Sedulous.UI;

using System;

/// Flags describing how a child should be positioned within its parent's available space.
public enum Gravity : int32
{
	None       = 0,

	// Horizontal axis
	Left       = 0x01,
	Right      = 0x02,
	CenterH    = 0x04,
	FillH      = 0x08,

	// Vertical axis
	Top        = 0x10,
	Bottom     = 0x20,
	CenterV    = 0x40,
	FillV      = 0x80,

	// Convenience combinations
	Center     = CenterH | CenterV,
	Fill       = FillH | FillV,
	TopLeft    = Top | Left,
	TopRight   = Top | Right,
	BottomLeft = Bottom | Left,
	BottomRight = Bottom | Right,
}

/// Static helper that resolves Gravity flags into concrete position and size.
public static class GravityHelper
{
	/// Apply gravity to position a child within a container.
	///
	/// @param gravity      Gravity flags.
	/// @param containerW   Available container width.
	/// @param containerH   Available container height.
	/// @param childW       Measured child width.
	/// @param childH       Measured child height.
	/// @param margin       Child's margin.
	/// @param outX         Resulting X position (relative to container origin).
	/// @param outY         Resulting Y position.
	/// @param outW         Resulting width (may expand if FillH).
	/// @param outH         Resulting height (may expand if FillV).
	public static void Apply(
		Gravity gravity,
		float containerW, float containerH,
		float childW, float childH,
		Thickness margin,
		out float outX, out float outY,
		out float outW, out float outH)
	{
		// --- Horizontal axis ---
		float availW = Math.Max(0, containerW - margin.Left - margin.Right);

		if (gravity.HasFlag(.FillH))
		{
			outX = margin.Left;
			outW = availW;
		}
		else if (gravity.HasFlag(.Right))
		{
			outX = containerW - margin.Right - childW;
			outW = childW;
		}
		else if (gravity.HasFlag(.CenterH))
		{
			outX = margin.Left + (availW - childW) * 0.5f;
			outW = childW;
		}
		else // Left or None — default to left
		{
			outX = margin.Left;
			outW = childW;
		}

		// --- Vertical axis ---
		float availH = Math.Max(0, containerH - margin.Top - margin.Bottom);

		if (gravity.HasFlag(.FillV))
		{
			outY = margin.Top;
			outH = availH;
		}
		else if (gravity.HasFlag(.Bottom))
		{
			outY = containerH - margin.Bottom - childH;
			outH = childH;
		}
		else if (gravity.HasFlag(.CenterV))
		{
			outY = margin.Top + (availH - childH) * 0.5f;
			outH = childH;
		}
		else // Top or None — default to top
		{
			outY = margin.Top;
			outH = childH;
		}
	}
}
