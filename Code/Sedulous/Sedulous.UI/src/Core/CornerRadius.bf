using System;

namespace Sedulous.UI;

/// Represents corner radii for rounded rectangles.
struct CornerRadius : IEquatable<CornerRadius>, IHashable
{
	/// Top-left corner radius.
	public float TopLeft;
	/// Top-right corner radius.
	public float TopRight;
	/// Bottom-right corner radius.
	public float BottomRight;
	/// Bottom-left corner radius.
	public float BottomLeft;

	/// Initializes a uniform corner radius.
	public this(float uniformRadius)
	{
		TopLeft = uniformRadius;
		TopRight = uniformRadius;
		BottomRight = uniformRadius;
		BottomLeft = uniformRadius;
	}

	/// Initializes with individual corner values.
	public this(float topLeft, float topRight, float bottomRight, float bottomLeft)
	{
		TopLeft = topLeft;
		TopRight = topRight;
		BottomRight = bottomRight;
		BottomLeft = bottomLeft;
	}

	/// Creates a uniform corner radius.
	public static CornerRadius Uniform(float radius) => CornerRadius(radius);

	/// Gets a zero corner radius.
	public static CornerRadius Zero => CornerRadius(0);

	/// Gets whether all corners are zero.
	public bool IsZero => TopLeft == 0 && TopRight == 0 && BottomRight == 0 && BottomLeft == 0;

	/// Gets whether all corners are equal.
	public bool IsUniform => TopLeft == TopRight && TopRight == BottomRight && BottomRight == BottomLeft;

	/// Multiplies corner radius by a scalar.
	public static CornerRadius operator *(CornerRadius r, float scale)
	{
		return CornerRadius(r.TopLeft * scale, r.TopRight * scale, r.BottomRight * scale, r.BottomLeft * scale);
	}

	/// Checks equality.
	public bool Equals(CornerRadius other)
	{
		return TopLeft == other.TopLeft && TopRight == other.TopRight &&
			   BottomRight == other.BottomRight && BottomLeft == other.BottomLeft;
	}

	/// Checks equality.
	public static bool operator ==(CornerRadius a, CornerRadius b) => a.Equals(b);

	/// Checks inequality.
	public static bool operator !=(CornerRadius a, CornerRadius b) => !a.Equals(b);

	/// Gets hash code.
	public int GetHashCode()
	{
		var hash = TopLeft.GetHashCode();
		hash = hash * 31 + TopRight.GetHashCode();
		hash = hash * 31 + BottomRight.GetHashCode();
		hash = hash * 31 + BottomLeft.GetHashCode();
		return hash;
	}

	/// Converts to string.
	public override void ToString(String str)
	{
		if (IsUniform)
			str.AppendF("{{Radius:{0}}}", TopLeft);
		else
			str.AppendF("{{TL:{0} TR:{1} BR:{2} BL:{3}}}", TopLeft, TopRight, BottomRight, BottomLeft);
	}
}
