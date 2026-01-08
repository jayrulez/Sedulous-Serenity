using System;

namespace Sedulous.UI;

/// Easing function types for animations.
enum EaseFunction
{
	/// Linear interpolation (no easing).
	Linear,

	// Quadratic
	/// Quadratic ease in (accelerating).
	QuadIn,
	/// Quadratic ease out (decelerating).
	QuadOut,
	/// Quadratic ease in and out.
	QuadInOut,

	// Cubic
	/// Cubic ease in.
	CubicIn,
	/// Cubic ease out.
	CubicOut,
	/// Cubic ease in and out.
	CubicInOut,

	// Quartic
	/// Quartic ease in.
	QuartIn,
	/// Quartic ease out.
	QuartOut,
	/// Quartic ease in and out.
	QuartInOut,

	// Quintic
	/// Quintic ease in.
	QuintIn,
	/// Quintic ease out.
	QuintOut,
	/// Quintic ease in and out.
	QuintInOut,

	// Sine
	/// Sinusoidal ease in.
	SineIn,
	/// Sinusoidal ease out.
	SineOut,
	/// Sinusoidal ease in and out.
	SineInOut,

	// Exponential
	/// Exponential ease in.
	ExpoIn,
	/// Exponential ease out.
	ExpoOut,
	/// Exponential ease in and out.
	ExpoInOut,

	// Circular
	/// Circular ease in.
	CircIn,
	/// Circular ease out.
	CircOut,
	/// Circular ease in and out.
	CircInOut,

	// Elastic
	/// Elastic ease in (spring effect).
	ElasticIn,
	/// Elastic ease out.
	ElasticOut,
	/// Elastic ease in and out.
	ElasticInOut,

	// Back
	/// Back ease in (overshoots then returns).
	BackIn,
	/// Back ease out.
	BackOut,
	/// Back ease in and out.
	BackInOut,

	// Bounce
	/// Bounce ease in.
	BounceIn,
	/// Bounce ease out.
	BounceOut,
	/// Bounce ease in and out.
	BounceInOut
}

/// Static class providing easing function implementations.
static class Easing
{
	private const float PI = Math.PI_f;
	private const float HALF_PI = Math.PI_f / 2;
	private const float C1 = 1.70158f;
	private const float C2 = C1 * 1.525f;
	private const float C3 = C1 + 1;
	private const float C4 = (2 * PI) / 3;
	private const float C5 = (2 * PI) / 4.5f;

	/// Evaluates an easing function at the given time.
	/// t should be in the range [0, 1].
	public static float Evaluate(EaseFunction easeFunc, float tValue)
	{
		var t = Math.Clamp(tValue, 0, 1);

		switch (easeFunc)
		{
		case .Linear:
			return t;

		// Quadratic
		case .QuadIn:
			return t * t;
		case .QuadOut:
			return 1 - (1 - t) * (1 - t);
		case .QuadInOut:
			return t < 0.5f ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;

		// Cubic
		case .CubicIn:
			return t * t * t;
		case .CubicOut:
			return 1 - (1 - t) * (1 - t) * (1 - t);
		case .CubicInOut:
			return t < 0.5f ? 4 * t * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;

		// Quartic
		case .QuartIn:
			return t * t * t * t;
		case .QuartOut:
			return 1 - (1 - t) * (1 - t) * (1 - t) * (1 - t);
		case .QuartInOut:
			return t < 0.5f ? 8 * t * t * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;

		// Quintic
		case .QuintIn:
			return t * t * t * t * t;
		case .QuintOut:
			return 1 - (1 - t) * (1 - t) * (1 - t) * (1 - t) * (1 - t);
		case .QuintInOut:
			return t < 0.5f ? 16 * t * t * t * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;

		// Sine
		case .SineIn:
			return 1 - Math.Cos(t * HALF_PI);
		case .SineOut:
			return Math.Sin(t * HALF_PI);
		case .SineInOut:
			return -(Math.Cos(PI * t) - 1) / 2;

		// Exponential
		case .ExpoIn:
			return t == 0 ? 0 : Math.Pow(2, 10 * t - 10);
		case .ExpoOut:
			return t == 1 ? 1 : 1 - Math.Pow(2, -10 * t);
		case .ExpoInOut:
			if (t == 0) return 0;
			if (t == 1) return 1;
			return t < 0.5f ? Math.Pow(2, 20 * t - 10) / 2 : (2 - Math.Pow(2, -20 * t + 10)) / 2;

		// Circular
		case .CircIn:
			return 1 - Math.Sqrt(1 - t * t);
		case .CircOut:
			return Math.Sqrt(1 - (t - 1) * (t - 1));
		case .CircInOut:
			return t < 0.5f
				? (1 - Math.Sqrt(1 - 4 * t * t)) / 2
				: (Math.Sqrt(1 - (-2 * t + 2) * (-2 * t + 2)) + 1) / 2;

		// Elastic
		case .ElasticIn:
			if (t == 0) return 0;
			if (t == 1) return 1;
			return -Math.Pow(2, 10 * t - 10) * Math.Sin((t * 10 - 10.75f) * C4);
		case .ElasticOut:
			if (t == 0) return 0;
			if (t == 1) return 1;
			return Math.Pow(2, -10 * t) * Math.Sin((t * 10 - 0.75f) * C4) + 1;
		case .ElasticInOut:
			if (t == 0) return 0;
			if (t == 1) return 1;
			return t < 0.5f
				? -(Math.Pow(2, 20 * t - 10) * Math.Sin((20 * t - 11.125f) * C5)) / 2
				: (Math.Pow(2, -20 * t + 10) * Math.Sin((20 * t - 11.125f) * C5)) / 2 + 1;

		// Back
		case .BackIn:
			return C3 * t * t * t - C1 * t * t;
		case .BackOut:
			return 1 + C3 * (t - 1) * (t - 1) * (t - 1) + C1 * (t - 1) * (t - 1);
		case .BackInOut:
			return t < 0.5f
				? (4 * t * t * ((C2 + 1) * 2 * t - C2)) / 2
				: ((2 * t - 2) * (2 * t - 2) * ((C2 + 1) * (t * 2 - 2) + C2) + 2) / 2;

		// Bounce
		case .BounceIn:
			return 1 - BounceOutImpl(1 - t);
		case .BounceOut:
			return BounceOutImpl(t);
		case .BounceInOut:
			return t < 0.5f
				? (1 - BounceOutImpl(1 - 2 * t)) / 2
				: (1 + BounceOutImpl(2 * t - 1)) / 2;
		}
	}

	private static float BounceOutImpl(float t)
	{
		const float n1 = 7.5625f;
		const float d1 = 2.75f;

		if (t < 1 / d1)
		{
			return n1 * t * t;
		}
		else if (t < 2 / d1)
		{
			let t2 = t - 1.5f / d1;
			return n1 * t2 * t2 + 0.75f;
		}
		else if (t < 2.5f / d1)
		{
			let t2 = t - 2.25f / d1;
			return n1 * t2 * t2 + 0.9375f;
		}
		else
		{
			let t2 = t - 2.625f / d1;
			return n1 * t2 * t2 + 0.984375f;
		}
	}

	/// Interpolates between two float values using the specified easing.
	public static float Lerp(float from, float to, float t, EaseFunction easing)
	{
		let easedT = Evaluate(easing, t);
		return from + (to - from) * easedT;
	}
}
