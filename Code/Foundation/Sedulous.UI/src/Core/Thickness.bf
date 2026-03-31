namespace Sedulous.UI;

/// Describes the thickness of a frame around a rectangle (padding, margin, border).
public struct Thickness
{
	public float Left;
	public float Top;
	public float Right;
	public float Bottom;

	/// All sides the same.
	public this(float uniform)
	{
		Left = uniform;
		Top = uniform;
		Right = uniform;
		Bottom = uniform;
	}

	/// Horizontal (left/right) and vertical (top/bottom).
	public this(float horizontal, float vertical)
	{
		Left = horizontal;
		Top = vertical;
		Right = horizontal;
		Bottom = vertical;
	}

	/// Each side individually.
	public this(float left, float top, float right, float bottom)
	{
		Left = left;
		Top = top;
		Right = right;
		Bottom = bottom;
	}

	/// Total horizontal thickness (Left + Right).
	public float Horizontal => Left + Right;

	/// Total vertical thickness (Top + Bottom).
	public float Vertical => Top + Bottom;

	/// Zero thickness.
	public static readonly Thickness Zero = .(0);
}
