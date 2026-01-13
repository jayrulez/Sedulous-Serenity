namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// A keyframe in a particle curve.
struct CurveKeyFloat
{
	/// Time position (0-1 for particle lifetime).
	public float Time;
	/// Value at this keyframe.
	public float Value;
	/// Incoming tangent (slope approaching this key).
	public float TangentIn;
	/// Outgoing tangent (slope leaving this key).
	public float TangentOut;

	public this(float time, float value, float tangentIn = 0, float tangentOut = 0)
	{
		Time = time;
		Value = value;
		TangentIn = tangentIn;
		TangentOut = tangentOut;
	}
}

/// A keyframe for Color curves.
struct CurveKeyColor
{
	/// Time position (0-1 for particle lifetime).
	public float Time;
	/// Value at this keyframe.
	public Color Value;

	public this(float time, Color value)
	{
		Time = time;
		Value = value;
	}
}

/// A keyframe for Vector2 curves.
struct CurveKeyVector2
{
	/// Time position (0-1 for particle lifetime).
	public float Time;
	/// Value at this keyframe.
	public Vector2 Value;
	/// Incoming tangent.
	public Vector2 TangentIn;
	/// Outgoing tangent.
	public Vector2 TangentOut;

	public this(float time, Vector2 value, Vector2 tangentIn = .Zero, Vector2 tangentOut = .Zero)
	{
		Time = time;
		Value = value;
		TangentIn = tangentIn;
		TangentOut = tangentOut;
	}
}

/// A keyframe for Vector3 curves.
struct CurveKeyVector3
{
	/// Time position (0-1 for particle lifetime).
	public float Time;
	/// Value at this keyframe.
	public Vector3 Value;
	/// Incoming tangent.
	public Vector3 TangentIn;
	/// Outgoing tangent.
	public Vector3 TangentOut;

	public this(float time, Vector3 value, Vector3 tangentIn = .Zero, Vector3 tangentOut = .Zero)
	{
		Time = time;
		Value = value;
		TangentIn = tangentIn;
		TangentOut = tangentOut;
	}
}

/// Curve for animating float values over particle lifetime.
class ParticleCurveFloat
{
	private List<CurveKeyFloat> mKeys = new .() ~ delete _;

	/// Number of keyframes.
	public int32 KeyCount => (int32)mKeys.Count;

	/// Whether this curve has any keys.
	public bool HasKeys => mKeys.Count > 0;

	/// Adds a keyframe.
	public void AddKey(float time, float value, float tangentIn = 0, float tangentOut = 0)
	{
		mKeys.Add(.(time, value, tangentIn, tangentOut));
		SortKeys();
	}

	/// Adds a keyframe.
	public void AddKey(CurveKeyFloat key)
	{
		mKeys.Add(key);
		SortKeys();
	}

	/// Clears all keyframes.
	public void Clear()
	{
		mKeys.Clear();
	}

	/// Evaluates the curve at the given time (0-1).
	public float Evaluate(float t)
	{
		if (mKeys.Count == 0)
			return 0;

		if (mKeys.Count == 1)
			return mKeys[0].Value;

		// Clamp time
		var tClamped = Math.Clamp(t, 0, 1);

		// Find surrounding keys
		int32 keyIndex = 0;
		for (int32 i = 0; i < mKeys.Count - 1; i++)
		{
			if (tClamped >= mKeys[i].Time && tClamped <= mKeys[i + 1].Time)
			{
				keyIndex = i;
				break;
			}
			if (tClamped > mKeys[i + 1].Time)
				keyIndex = i + 1;
		}

		// If at or past last key, return last value
		if (keyIndex >= mKeys.Count - 1)
			return mKeys[mKeys.Count - 1].Value;

		// Hermite interpolation between keyIndex and keyIndex+1
		let k0 = mKeys[keyIndex];
		let k1 = mKeys[keyIndex + 1];

		float segmentTime = k1.Time - k0.Time;
		if (segmentTime <= 0)
			return k0.Value;

		float localT = (tClamped - k0.Time) / segmentTime;
		return HermiteInterpolate(k0.Value, k1.Value, k0.TangentOut * segmentTime, k1.TangentIn * segmentTime, localT);
	}

	/// Creates a simple two-key curve (start to end).
	public static ParticleCurveFloat CreateLinear(float startValue, float endValue)
	{
		let curve = new ParticleCurveFloat();
		curve.AddKey(0, startValue);
		curve.AddKey(1, endValue);
		return curve;
	}

	/// Creates a constant curve.
	public static ParticleCurveFloat CreateConstant(float value)
	{
		let curve = new ParticleCurveFloat();
		curve.AddKey(0, value);
		return curve;
	}

	private void SortKeys()
	{
		mKeys.Sort(scope (a, b) => a.Time <=> b.Time);
	}

	private static float HermiteInterpolate(float p0, float p1, float m0, float m1, float t)
	{
		float t2 = t * t;
		float t3 = t2 * t;
		float h00 = 2 * t3 - 3 * t2 + 1;
		float h10 = t3 - 2 * t2 + t;
		float h01 = -2 * t3 + 3 * t2;
		float h11 = t3 - t2;
		return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1;
	}
}

/// Curve for animating Color values over particle lifetime.
class ParticleCurveColor
{
	private List<CurveKeyColor> mKeys = new .() ~ delete _;

	/// Number of keyframes.
	public int32 KeyCount => (int32)mKeys.Count;

	/// Whether this curve has any keys.
	public bool HasKeys => mKeys.Count > 0;

	/// Adds a keyframe.
	public void AddKey(float time, Color value)
	{
		mKeys.Add(.(time, value));
		SortKeys();
	}

	/// Clears all keyframes.
	public void Clear()
	{
		mKeys.Clear();
	}

	/// Evaluates the curve at the given time (0-1).
	public Color Evaluate(float t)
	{
		if (mKeys.Count == 0)
			return .White;

		if (mKeys.Count == 1)
			return mKeys[0].Value;

		// Clamp time
		var tClamped = Math.Clamp(t, 0, 1);

		// Find surrounding keys
		int32 keyIndex = 0;
		for (int32 i = 0; i < mKeys.Count - 1; i++)
		{
			if (tClamped >= mKeys[i].Time && tClamped <= mKeys[i + 1].Time)
			{
				keyIndex = i;
				break;
			}
			if (tClamped > mKeys[i + 1].Time)
				keyIndex = i + 1;
		}

		// If at or past last key, return last value
		if (keyIndex >= mKeys.Count - 1)
			return mKeys[mKeys.Count - 1].Value;

		// Linear interpolation for colors
		let k0 = mKeys[keyIndex];
		let k1 = mKeys[keyIndex + 1];

		float segmentTime = k1.Time - k0.Time;
		if (segmentTime <= 0)
			return k0.Value;

		float localT = (tClamped - k0.Time) / segmentTime;
		return k0.Value.Interpolate(k1.Value, localT);
	}

	/// Creates a simple two-key curve (start to end).
	public static ParticleCurveColor CreateLinear(Color startValue, Color endValue)
	{
		let curve = new ParticleCurveColor();
		curve.AddKey(0, startValue);
		curve.AddKey(1, endValue);
		return curve;
	}

	/// Creates a constant curve.
	public static ParticleCurveColor CreateConstant(Color value)
	{
		let curve = new ParticleCurveColor();
		curve.AddKey(0, value);
		return curve;
	}

	private void SortKeys()
	{
		mKeys.Sort(scope (a, b) => a.Time <=> b.Time);
	}
}

/// Curve for animating Vector2 values over particle lifetime.
class ParticleCurveVector2
{
	private List<CurveKeyVector2> mKeys = new .() ~ delete _;

	/// Number of keyframes.
	public int32 KeyCount => (int32)mKeys.Count;

	/// Whether this curve has any keys.
	public bool HasKeys => mKeys.Count > 0;

	/// Adds a keyframe.
	public void AddKey(float time, Vector2 value, Vector2 tangentIn = .Zero, Vector2 tangentOut = .Zero)
	{
		mKeys.Add(.(time, value, tangentIn, tangentOut));
		SortKeys();
	}

	/// Clears all keyframes.
	public void Clear()
	{
		mKeys.Clear();
	}

	/// Evaluates the curve at the given time (0-1).
	public Vector2 Evaluate(float t)
	{
		if (mKeys.Count == 0)
			return .Zero;

		if (mKeys.Count == 1)
			return mKeys[0].Value;

		// Clamp time
		var tClamped = Math.Clamp(t, 0, 1);

		// Find surrounding keys
		int32 keyIndex = 0;
		for (int32 i = 0; i < mKeys.Count - 1; i++)
		{
			if (tClamped >= mKeys[i].Time && tClamped <= mKeys[i + 1].Time)
			{
				keyIndex = i;
				break;
			}
			if (tClamped > mKeys[i + 1].Time)
				keyIndex = i + 1;
		}

		// If at or past last key, return last value
		if (keyIndex >= mKeys.Count - 1)
			return mKeys[mKeys.Count - 1].Value;

		// Hermite interpolation
		let k0 = mKeys[keyIndex];
		let k1 = mKeys[keyIndex + 1];

		float segmentTime = k1.Time - k0.Time;
		if (segmentTime <= 0)
			return k0.Value;

		float localT = (tClamped - k0.Time) / segmentTime;
		return .(
			HermiteInterpolate(k0.Value.X, k1.Value.X, k0.TangentOut.X * segmentTime, k1.TangentIn.X * segmentTime, localT),
			HermiteInterpolate(k0.Value.Y, k1.Value.Y, k0.TangentOut.Y * segmentTime, k1.TangentIn.Y * segmentTime, localT)
		);
	}

	/// Creates a simple two-key curve (start to end).
	public static ParticleCurveVector2 CreateLinear(Vector2 startValue, Vector2 endValue)
	{
		let curve = new ParticleCurveVector2();
		curve.AddKey(0, startValue);
		curve.AddKey(1, endValue);
		return curve;
	}

	private void SortKeys()
	{
		mKeys.Sort(scope (a, b) => a.Time <=> b.Time);
	}

	private static float HermiteInterpolate(float p0, float p1, float m0, float m1, float t)
	{
		float t2 = t * t;
		float t3 = t2 * t;
		float h00 = 2 * t3 - 3 * t2 + 1;
		float h10 = t3 - 2 * t2 + t;
		float h01 = -2 * t3 + 3 * t2;
		float h11 = t3 - t2;
		return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1;
	}
}

/// Curve for animating Vector3 values over particle lifetime.
class ParticleCurveVector3
{
	private List<CurveKeyVector3> mKeys = new .() ~ delete _;

	/// Number of keyframes.
	public int32 KeyCount => (int32)mKeys.Count;

	/// Whether this curve has any keys.
	public bool HasKeys => mKeys.Count > 0;

	/// Adds a keyframe.
	public void AddKey(float time, Vector3 value, Vector3 tangentIn = .Zero, Vector3 tangentOut = .Zero)
	{
		mKeys.Add(.(time, value, tangentIn, tangentOut));
		SortKeys();
	}

	/// Clears all keyframes.
	public void Clear()
	{
		mKeys.Clear();
	}

	/// Evaluates the curve at the given time (0-1).
	public Vector3 Evaluate(float t)
	{
		if (mKeys.Count == 0)
			return .Zero;

		if (mKeys.Count == 1)
			return mKeys[0].Value;

		// Clamp time
		var tClamped = Math.Clamp(t, 0, 1);

		// Find surrounding keys
		int32 keyIndex = 0;
		for (int32 i = 0; i < mKeys.Count - 1; i++)
		{
			if (tClamped >= mKeys[i].Time && tClamped <= mKeys[i + 1].Time)
			{
				keyIndex = i;
				break;
			}
			if (tClamped > mKeys[i + 1].Time)
				keyIndex = i + 1;
		}

		// If at or past last key, return last value
		if (keyIndex >= mKeys.Count - 1)
			return mKeys[mKeys.Count - 1].Value;

		// Hermite interpolation
		let k0 = mKeys[keyIndex];
		let k1 = mKeys[keyIndex + 1];

		float segmentTime = k1.Time - k0.Time;
		if (segmentTime <= 0)
			return k0.Value;

		float localT = (tClamped - k0.Time) / segmentTime;
		return .(
			HermiteInterpolate(k0.Value.X, k1.Value.X, k0.TangentOut.X * segmentTime, k1.TangentIn.X * segmentTime, localT),
			HermiteInterpolate(k0.Value.Y, k1.Value.Y, k0.TangentOut.Y * segmentTime, k1.TangentIn.Y * segmentTime, localT),
			HermiteInterpolate(k0.Value.Z, k1.Value.Z, k0.TangentOut.Z * segmentTime, k1.TangentIn.Z * segmentTime, localT)
		);
	}

	/// Creates a simple two-key curve (start to end).
	public static ParticleCurveVector3 CreateLinear(Vector3 startValue, Vector3 endValue)
	{
		let curve = new ParticleCurveVector3();
		curve.AddKey(0, startValue);
		curve.AddKey(1, endValue);
		return curve;
	}

	private void SortKeys()
	{
		mKeys.Sort(scope (a, b) => a.Time <=> b.Time);
	}

	private static float HermiteInterpolate(float p0, float p1, float m0, float m1, float t)
	{
		float t2 = t * t;
		float t3 = t2 * t;
		float h00 = 2 * t3 - 3 * t2 + 1;
		float h10 = t3 - 2 * t2 + t;
		float h01 = -2 * t3 + 3 * t2;
		float h11 = t3 - t2;
		return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1;
	}
}
