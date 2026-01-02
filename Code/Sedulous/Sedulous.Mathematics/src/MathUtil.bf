using System;

namespace Sedulous.Mathematics;

/// Common math constants and utility functions.
static class MathUtil
{
	/// Pi constant.
	public const float Pi = 3.14159265358979323846f;

	/// Two times Pi.
	public const float TwoPi = Pi * 2.0f;

	/// Pi divided by two.
	public const float PiOver2 = Pi / 2.0f;

	/// Pi divided by four.
	public const float PiOver4 = Pi / 4.0f;

	/// Conversion factor from degrees to radians.
	public const float Deg2Rad = Pi / 180.0f;

	/// Conversion factor from radians to degrees.
	public const float Rad2Deg = 180.0f / Pi;

	/// A small value used for floating-point comparisons.
	public const float Epsilon = 1e-6f;

	/// Converts degrees to radians.
	public static float ToRadians(float degrees)
	{
		return degrees * Deg2Rad;
	}

	/// Converts radians to degrees.
	public static float ToDegrees(float radians)
	{
		return radians * Rad2Deg;
	}

	/// Clamps a value between a minimum and maximum.
	public static float Clamp(float value, float min, float max)
	{
		if (value < min) return min;
		if (value > max) return max;
		return value;
	}

	/// Clamps a value between 0 and 1.
	public static float Clamp01(float value)
	{
		return Clamp(value, 0.0f, 1.0f);
	}

	/// Linear interpolation between two values.
	public static float Lerp(float a, float b, float t)
	{
		return a + (b - a) * t;
	}

	/// Checks if two floats are approximately equal.
	public static bool Approximately(float a, float b, float tolerance = Epsilon)
	{
		return Math.Abs(a - b) <= tolerance;
	}

	/// Returns the minimum of two values.
	public static float Min(float a, float b)
	{
		return a < b ? a : b;
	}

	/// Returns the maximum of two values.
	public static float Max(float a, float b)
	{
		return a > b ? a : b;
	}

	/// Returns the sign of a value (-1, 0, or 1).
	public static float Sign(float value)
	{
		if (value > 0) return 1.0f;
		if (value < 0) return -1.0f;
		return 0.0f;
	}

	/// Wraps an angle to the range [-Pi, Pi].
	public static float WrapAngle(float angle)
	{
		var result = angle;
		while (result > Pi) result -= TwoPi;
		while (result < -Pi) result += TwoPi;
		return result;
	}
}
