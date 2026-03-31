namespace Sedulous.UI;

using System;

/// Specifies how a parent constrains a child's measurement.
/// Inspired by Android's MeasureSpec.
public struct MeasureSpec
{
	/// The measurement mode.
	public enum Mode
	{
		/// No constraints. Child can be any size.
		Unspecified,
		/// Child can be at most this size.
		AtMost,
		/// Child must be exactly this size.
		Exactly
	}

	public Mode SpecMode;
	public float Size;

	public this(Mode mode, float size)
	{
		SpecMode = mode;
		Size = size;
	}

	/// Create an Exactly spec.
	public static MeasureSpec MakeExactly(float size) => .(Mode.Exactly, size);

	/// Create an AtMost spec.
	public static MeasureSpec MakeAtMost(float size) => .(Mode.AtMost, size);

	/// Create an Unspecified spec.
	public static MeasureSpec MakeUnspecified() => .(Mode.Unspecified, 0);

	/// Resolve a desired size against this spec.
	/// Returns the final size the child should use.
	public float Resolve(float desiredSize)
	{
		switch (SpecMode)
		{
		case .Exactly:
			return Size;
		case .AtMost:
			return Math.Min(desiredSize, Size);
		case .Unspecified:
			return desiredSize;
		}
	}

	/// Resolve a desired size, applying min/max constraints.
	public float Resolve(float desiredSize, float minSize, float maxSize)
	{
		float size = Resolve(desiredSize);
		if (minSize > 0)
			size = Math.Max(size, minSize);
		if (maxSize > 0)
			size = Math.Min(size, maxSize);
		return size;
	}
}
