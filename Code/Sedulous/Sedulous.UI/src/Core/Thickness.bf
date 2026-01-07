using System;

namespace Sedulous.UI;

/// Represents thickness values for margins, padding, and borders.
struct Thickness : IEquatable<Thickness>, IHashable
{
	/// Left thickness.
	public float Left;
	/// Top thickness.
	public float Top;
	/// Right thickness.
	public float Right;
	/// Bottom thickness.
	public float Bottom;

	/// Initializes a uniform thickness.
	public this(float uniformValue)
	{
		Left = uniformValue;
		Top = uniformValue;
		Right = uniformValue;
		Bottom = uniformValue;
	}

	/// Initializes with horizontal and vertical values.
	public this(float horizontal, float vertical)
	{
		Left = horizontal;
		Right = horizontal;
		Top = vertical;
		Bottom = vertical;
	}

	/// Initializes with individual values.
	public this(float left, float top, float right, float bottom)
	{
		Left = left;
		Top = top;
		Right = right;
		Bottom = bottom;
	}

	/// Creates a uniform thickness.
	public static Thickness Uniform(float value) => Thickness(value);

	/// Creates a symmetric thickness.
	public static Thickness Symmetric(float horizontal, float vertical) => Thickness(horizontal, vertical);

	/// Gets the total horizontal thickness (left + right).
	public float HorizontalThickness => Left + Right;

	/// Gets the total vertical thickness (top + bottom).
	public float VerticalThickness => Top + Bottom;

	/// Gets a zero thickness.
	public static Thickness Zero => Thickness(0);

	/// Adds two thickness values.
	public static Thickness operator +(Thickness a, Thickness b)
	{
		return Thickness(a.Left + b.Left, a.Top + b.Top, a.Right + b.Right, a.Bottom + b.Bottom);
	}

	/// Subtracts two thickness values.
	public static Thickness operator -(Thickness a, Thickness b)
	{
		return Thickness(a.Left - b.Left, a.Top - b.Top, a.Right - b.Right, a.Bottom - b.Bottom);
	}

	/// Multiplies thickness by a scalar.
	public static Thickness operator *(Thickness t, float scale)
	{
		return Thickness(t.Left * scale, t.Top * scale, t.Right * scale, t.Bottom * scale);
	}

	/// Checks equality.
	public bool Equals(Thickness other)
	{
		return Left == other.Left && Top == other.Top && Right == other.Right && Bottom == other.Bottom;
	}

	/// Checks equality.
	public static bool operator ==(Thickness a, Thickness b) => a.Equals(b);

	/// Checks inequality.
	public static bool operator !=(Thickness a, Thickness b) => !a.Equals(b);

	/// Gets hash code.
	public int GetHashCode()
	{
		var hash = Left.GetHashCode();
		hash = hash * 31 + Top.GetHashCode();
		hash = hash * 31 + Right.GetHashCode();
		hash = hash * 31 + Bottom.GetHashCode();
		return hash;
	}

	/// Converts to string.
	public override void ToString(String str)
	{
		str.AppendF("{{Left:{0} Top:{1} Right:{2} Bottom:{3}}}", Left, Top, Right, Bottom);
	}
}
