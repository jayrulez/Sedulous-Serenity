using System;

namespace Sedulous.UI;

/// Standard easing curve types.
public enum EasingType
{
	/// Linear interpolation (no easing).
	Linear,
	/// Quadratic ease in (accelerating).
	QuadraticIn,
	/// Quadratic ease out (decelerating).
	QuadraticOut,
	/// Quadratic ease in-out.
	QuadraticInOut,
	/// Cubic ease in.
	CubicIn,
	/// Cubic ease out.
	CubicOut,
	/// Cubic ease in-out.
	CubicInOut,
	/// Quartic ease in.
	QuarticIn,
	/// Quartic ease out.
	QuarticOut,
	/// Quartic ease in-out.
	QuarticInOut,
	/// Quintic ease in.
	QuinticIn,
	/// Quintic ease out.
	QuinticOut,
	/// Quintic ease in-out.
	QuinticInOut,
	/// Sinusoidal ease in.
	SineIn,
	/// Sinusoidal ease out.
	SineOut,
	/// Sinusoidal ease in-out.
	SineInOut,
	/// Exponential ease in.
	ExponentialIn,
	/// Exponential ease out.
	ExponentialOut,
	/// Exponential ease in-out.
	ExponentialInOut,
	/// Circular ease in.
	CircularIn,
	/// Circular ease out.
	CircularOut,
	/// Circular ease in-out.
	CircularInOut,
	/// Elastic ease in (spring overshoot).
	ElasticIn,
	/// Elastic ease out.
	ElasticOut,
	/// Elastic ease in-out.
	ElasticInOut,
	/// Back ease in (slight overshoot).
	BackIn,
	/// Back ease out.
	BackOut,
	/// Back ease in-out.
	BackInOut,
	/// Bounce ease in.
	BounceIn,
	/// Bounce ease out.
	BounceOut,
	/// Bounce ease in-out.
	BounceInOut
}

/// Easing functions for animations.
/// All functions take t in [0,1] and return a value typically in [0,1].
public static class Easing
{
	private const float PI = Math.PI_f;
	private const float HALF_PI = PI / 2.0f;

	/// Evaluates the easing function for the given type.
	public static float Evaluate(EasingType type, float t)
	{
		switch (type)
		{
		case .Linear: return Linear(t);
		case .QuadraticIn: return QuadraticIn(t);
		case .QuadraticOut: return QuadraticOut(t);
		case .QuadraticInOut: return QuadraticInOut(t);
		case .CubicIn: return CubicIn(t);
		case .CubicOut: return CubicOut(t);
		case .CubicInOut: return CubicInOut(t);
		case .QuarticIn: return QuarticIn(t);
		case .QuarticOut: return QuarticOut(t);
		case .QuarticInOut: return QuarticInOut(t);
		case .QuinticIn: return QuinticIn(t);
		case .QuinticOut: return QuinticOut(t);
		case .QuinticInOut: return QuinticInOut(t);
		case .SineIn: return SineIn(t);
		case .SineOut: return SineOut(t);
		case .SineInOut: return SineInOut(t);
		case .ExponentialIn: return ExponentialIn(t);
		case .ExponentialOut: return ExponentialOut(t);
		case .ExponentialInOut: return ExponentialInOut(t);
		case .CircularIn: return CircularIn(t);
		case .CircularOut: return CircularOut(t);
		case .CircularInOut: return CircularInOut(t);
		case .ElasticIn: return ElasticIn(t);
		case .ElasticOut: return ElasticOut(t);
		case .ElasticInOut: return ElasticInOut(t);
		case .BackIn: return BackIn(t);
		case .BackOut: return BackOut(t);
		case .BackInOut: return BackInOut(t);
		case .BounceIn: return BounceIn(t);
		case .BounceOut: return BounceOut(t);
		case .BounceInOut: return BounceInOut(t);
		}
	}

	// Linear
	public static float Linear(float t) => t;

	// Quadratic
	public static float QuadraticIn(float t) => t * t;
	public static float QuadraticOut(float t) => t * (2 - t);
	public static float QuadraticInOut(float t) => t < 0.5f ? 2 * t * t : -1 + (4 - 2 * t) * t;

	// Cubic
	public static float CubicIn(float t) => t * t * t;
	public static float CubicOut(float t) { let t1 = t - 1; return t1 * t1 * t1 + 1; }
	public static float CubicInOut(float t) => t < 0.5f ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1;

	// Quartic
	public static float QuarticIn(float t) => t * t * t * t;
	public static float QuarticOut(float t) { let t1 = t - 1; return 1 - t1 * t1 * t1 * t1; }
	public static float QuarticInOut(float t) { let t1 = t - 1; return t < 0.5f ? 8 * t * t * t * t : 1 - 8 * t1 * t1 * t1 * t1; }

	// Quintic
	public static float QuinticIn(float t) => t * t * t * t * t;
	public static float QuinticOut(float t) { let t1 = t - 1; return 1 + t1 * t1 * t1 * t1 * t1; }
	public static float QuinticInOut(float t) { let t1 = t - 1; return t < 0.5f ? 16 * t * t * t * t * t : 1 + 16 * t1 * t1 * t1 * t1 * t1; }

	// Sine
	public static float SineIn(float t) => 1 - Math.Cos(t * HALF_PI);
	public static float SineOut(float t) => Math.Sin(t * HALF_PI);
	public static float SineInOut(float t) => 0.5f * (1 - Math.Cos(PI * t));

	// Exponential
	public static float ExponentialIn(float t) => t == 0 ? 0 : Math.Pow(2, 10 * (t - 1));
	public static float ExponentialOut(float t) => t == 1 ? 1 : 1 - Math.Pow(2, -10 * t);
	public static float ExponentialInOut(float t)
	{
		if (t == 0) return 0;
		if (t == 1) return 1;
		return t < 0.5f ? 0.5f * Math.Pow(2, 20 * t - 10) : 1 - 0.5f * Math.Pow(2, -20 * t + 10);
	}

	// Circular
	public static float CircularIn(float t) => 1 - Math.Sqrt(1 - t * t);
	public static float CircularOut(float t) { let t1 = t - 1; return Math.Sqrt(1 - t1 * t1); }
	public static float CircularInOut(float t)
	{
		if (t < 0.5f)
			return 0.5f * (1 - Math.Sqrt(1 - 4 * t * t));
		let t1 = 2 * t - 2;
		return 0.5f * (Math.Sqrt(1 - t1 * t1) + 1);
	}

	// Elastic
	public static float ElasticIn(float t)
	{
		if (t == 0) return 0;
		if (t == 1) return 1;
		return -Math.Pow(2, 10 * t - 10) * Math.Sin((t * 10 - 10.75f) * (2 * PI / 3));
	}

	public static float ElasticOut(float t)
	{
		if (t == 0) return 0;
		if (t == 1) return 1;
		return Math.Pow(2, -10 * t) * Math.Sin((t * 10 - 0.75f) * (2 * PI / 3)) + 1;
	}

	public static float ElasticInOut(float t)
	{
		if (t == 0) return 0;
		if (t == 1) return 1;
		let c = (2 * PI) / 4.5f;
		return t < 0.5f
			? -0.5f * Math.Pow(2, 20 * t - 10) * Math.Sin((20 * t - 11.125f) * c)
			: 0.5f * Math.Pow(2, -20 * t + 10) * Math.Sin((20 * t - 11.125f) * c) + 1;
	}

	// Back (slight overshoot)
	private const float BACK_C1 = 1.70158f;
	private const float BACK_C2 = BACK_C1 * 1.525f;
	private const float BACK_C3 = BACK_C1 + 1;

	public static float BackIn(float t) => BACK_C3 * t * t * t - BACK_C1 * t * t;
	public static float BackOut(float t) { let t1 = t - 1; return 1 + BACK_C3 * t1 * t1 * t1 + BACK_C1 * t1 * t1; }
	public static float BackInOut(float t)
	{
		return t < 0.5f
			? (4 * t * t * ((BACK_C2 + 1) * 2 * t - BACK_C2)) / 2
			: ((2 * t - 2) * (2 * t - 2) * ((BACK_C2 + 1) * (t * 2 - 2) + BACK_C2) + 2) / 2;
	}

	// Bounce
	public static float BounceOut(float t)
	{
		let n1 = 7.5625f;
		let d1 = 2.75f;

		if (t < 1 / d1)
			return n1 * t * t;
		else if (t < 2 / d1)
		{
			let t1 = t - 1.5f / d1;
			return n1 * t1 * t1 + 0.75f;
		}
		else if (t < 2.5f / d1)
		{
			let t1 = t - 2.25f / d1;
			return n1 * t1 * t1 + 0.9375f;
		}
		else
		{
			let t1 = t - 2.625f / d1;
			return n1 * t1 * t1 + 0.984375f;
		}
	}

	public static float BounceIn(float t) => 1 - BounceOut(1 - t);

	public static float BounceInOut(float t)
	{
		return t < 0.5f
			? (1 - BounceOut(1 - 2 * t)) / 2
			: (1 + BounceOut(2 * t - 1)) / 2;
	}
}
