using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Delegate for setting a float property value.
delegate void FloatSetter(float value);

/// Delegate for setting a Color property value.
delegate void ColorSetter(Color value);

/// Delegate for setting a Vector2 property value.
delegate void Vector2Setter(Vector2 value);

/// Delegate for setting a Thickness property value.
delegate void ThicknessSetter(Thickness value);

/// Animation for float properties.
class FloatAnimation : Animation
{
	private float mFrom;
	private float mTo;
	private FloatSetter mSetter ~ delete _;

	/// Gets or sets the starting value.
	public float From
	{
		get => mFrom;
		set => mFrom = value;
	}

	/// Gets or sets the ending value.
	public float To
	{
		get => mTo;
		set => mTo = value;
	}

	/// Creates a float animation.
	public this() { }

	/// Creates a float animation with from/to values.
	public this(float from, float to)
	{
		mFrom = from;
		mTo = to;
	}

	/// Sets the value setter delegate.
	public void SetSetter(FloatSetter setter)
	{
		delete mSetter;
		mSetter = setter;
	}

	protected override void ApplyValue(float progress)
	{
		if (mSetter != null)
		{
			let value = mFrom + (mTo - mFrom) * progress;
			mSetter(value);
		}
	}

	/// Gets the current interpolated value.
	public float CurrentValue => mFrom + (mTo - mFrom) * EasedProgress;
}

/// Animation for Color properties.
class ColorAnimation : Animation
{
	private Color mFrom;
	private Color mTo;
	private ColorSetter mSetter ~ delete _;

	/// Gets or sets the starting color.
	public Color From
	{
		get => mFrom;
		set => mFrom = value;
	}

	/// Gets or sets the ending color.
	public Color To
	{
		get => mTo;
		set => mTo = value;
	}

	/// Creates a color animation.
	public this() { }

	/// Creates a color animation with from/to values.
	public this(Color from, Color to)
	{
		mFrom = from;
		mTo = to;
	}

	/// Sets the value setter delegate.
	public void SetSetter(ColorSetter setter)
	{
		delete mSetter;
		mSetter = setter;
	}

	protected override void ApplyValue(float progress)
	{
		if (mSetter != null)
		{
			let value = LerpColor(mFrom, mTo, progress);
			mSetter(value);
		}
	}

	/// Gets the current interpolated color.
	public Color CurrentValue => LerpColor(mFrom, mTo, EasedProgress);

	private static Color LerpColor(Color from, Color to, float t)
	{
		return Color(
			(uint8)(from.R + (int32)(to.R - from.R) * t),
			(uint8)(from.G + (int32)(to.G - from.G) * t),
			(uint8)(from.B + (int32)(to.B - from.B) * t),
			(uint8)(from.A + (int32)(to.A - from.A) * t)
		);
	}
}

/// Animation for Vector2 properties (position, size, etc.).
class Vector2Animation : Animation
{
	private Vector2 mFrom;
	private Vector2 mTo;
	private Vector2Setter mSetter ~ delete _;

	/// Gets or sets the starting value.
	public Vector2 From
	{
		get => mFrom;
		set => mFrom = value;
	}

	/// Gets or sets the ending value.
	public Vector2 To
	{
		get => mTo;
		set => mTo = value;
	}

	/// Creates a Vector2 animation.
	public this() { }

	/// Creates a Vector2 animation with from/to values.
	public this(Vector2 from, Vector2 to)
	{
		mFrom = from;
		mTo = to;
	}

	/// Sets the value setter delegate.
	public void SetSetter(Vector2Setter setter)
	{
		delete mSetter;
		mSetter = setter;
	}

	protected override void ApplyValue(float progress)
	{
		if (mSetter != null)
		{
			let value = Vector2(
				mFrom.X + (mTo.X - mFrom.X) * progress,
				mFrom.Y + (mTo.Y - mFrom.Y) * progress
			);
			mSetter(value);
		}
	}

	/// Gets the current interpolated value.
	public Vector2 CurrentValue
	{
		get
		{
			let t = EasedProgress;
			return Vector2(
				mFrom.X + (mTo.X - mFrom.X) * t,
				mFrom.Y + (mTo.Y - mFrom.Y) * t
			);
		}
	}
}

/// Animation for Thickness properties (margin, padding, etc.).
class ThicknessAnimation : Animation
{
	private Thickness mFrom;
	private Thickness mTo;
	private ThicknessSetter mSetter ~ delete _;

	/// Gets or sets the starting thickness.
	public Thickness From
	{
		get => mFrom;
		set => mFrom = value;
	}

	/// Gets or sets the ending thickness.
	public Thickness To
	{
		get => mTo;
		set => mTo = value;
	}

	/// Creates a thickness animation.
	public this() { }

	/// Creates a thickness animation with from/to values.
	public this(Thickness from, Thickness to)
	{
		mFrom = from;
		mTo = to;
	}

	/// Sets the value setter delegate.
	public void SetSetter(ThicknessSetter setter)
	{
		delete mSetter;
		mSetter = setter;
	}

	protected override void ApplyValue(float progress)
	{
		if (mSetter != null)
		{
			let value = Thickness(
				mFrom.Left + (mTo.Left - mFrom.Left) * progress,
				mFrom.Top + (mTo.Top - mFrom.Top) * progress,
				mFrom.Right + (mTo.Right - mFrom.Right) * progress,
				mFrom.Bottom + (mTo.Bottom - mFrom.Bottom) * progress
			);
			mSetter(value);
		}
	}

	/// Gets the current interpolated thickness.
	public Thickness CurrentValue
	{
		get
		{
			let t = EasedProgress;
			return Thickness(
				mFrom.Left + (mTo.Left - mFrom.Left) * t,
				mFrom.Top + (mTo.Top - mFrom.Top) * t,
				mFrom.Right + (mTo.Right - mFrom.Right) * t,
				mFrom.Bottom + (mTo.Bottom - mFrom.Bottom) * t
			);
		}
	}
}

/// Animation for opacity (convenience class).
class OpacityAnimation : FloatAnimation
{
	public this() : base(1.0f, 0.0f) { }

	public this(float from, float to) : base(from, to) { }

	/// Creates a fade-in animation.
	public static OpacityAnimation FadeIn(float duration = 0.3f)
	{
		let anim = new OpacityAnimation(0, 1);
		anim.Duration = duration;
		anim.EaseFunc = .QuadOut;
		return anim;
	}

	/// Creates a fade-out animation.
	public static OpacityAnimation FadeOut(float duration = 0.3f)
	{
		let anim = new OpacityAnimation(1, 0);
		anim.Duration = duration;
		anim.EaseFunc = .QuadIn;
		return anim;
	}
}
