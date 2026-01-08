using System;
using Sedulous.Mathematics;
using Sedulous.UI;

namespace Sedulous.Framework.UI;

/// Health/mana/resource bar for games.
/// Displays a filled bar with optional text and animation.
class ResourceBar : Widget
{
	private float mValue = 1.0f;
	private float mDisplayValue = 1.0f;
	private float mMaxValue = 1.0f;
	private Color mFillColor = Color(46, 204, 113, 255);
	private Color mBackgroundColor = Color(52, 73, 94, 255);
	private Color mBorderColor = Color(44, 62, 80, 255);
	private float mBorderWidth = 2.0f;
	private bool mShowText = true;
	private bool mAnimateChanges = true;
	private float mAnimationSpeed = 5.0f;
	private Orientation mOrientation = .Horizontal;

	// Flash effect
	private Color mFlashColor = .White;
	private float mFlashRemaining = 0;
	private float mFlashDuration = 0;

	/// Gets or sets the current value (0 to MaxValue).
	public float Value
	{
		get => mValue;
		set
		{
			mValue = Math.Clamp(value, 0, mMaxValue);
			if (!mAnimateChanges)
				mDisplayValue = mValue / mMaxValue;
		}
	}

	/// Gets or sets the maximum value.
	public float MaxValue
	{
		get => mMaxValue;
		set
		{
			mMaxValue = Math.Max(1, value);
			mValue = Math.Min(mValue, mMaxValue);
		}
	}

	/// Gets the normalized value (0 to 1).
	public float NormalizedValue => mMaxValue > 0 ? mValue / mMaxValue : 0;

	/// Gets or sets the fill color.
	public Color FillColor
	{
		get => mFillColor;
		set => mFillColor = value;
	}

	/// Gets or sets the background color.
	public Color BackgroundColor
	{
		get => mBackgroundColor;
		set => mBackgroundColor = value;
	}

	/// Gets or sets the border color.
	public Color BorderColor
	{
		get => mBorderColor;
		set => mBorderColor = value;
	}

	/// Gets or sets the border width.
	public float BorderWidth
	{
		get => mBorderWidth;
		set => mBorderWidth = value;
	}

	/// Gets or sets whether to show text.
	public bool ShowText
	{
		get => mShowText;
		set => mShowText = value;
	}

	/// Gets or sets whether value changes are animated.
	public bool AnimateChanges
	{
		get => mAnimateChanges;
		set => mAnimateChanges = value;
	}

	/// Gets or sets the animation speed.
	public float AnimationSpeed
	{
		get => mAnimationSpeed;
		set => mAnimationSpeed = value;
	}

	/// Gets or sets the bar orientation.
	public Orientation Orientation
	{
		get => mOrientation;
		set => mOrientation = value;
	}

	/// Triggers a flash effect (for damage/heal).
	public void Flash(Color color, float duration = 0.3f)
	{
		mFlashColor = color;
		mFlashDuration = duration;
		mFlashRemaining = duration;
	}

	protected override void OnUpdate(float deltaTime)
	{
		base.OnUpdate(deltaTime);

		// Animate display value
		if (mAnimateChanges)
		{
			let targetValue = NormalizedValue;
			if (mDisplayValue != targetValue)
			{
				let diff = targetValue - mDisplayValue;
				let change = mAnimationSpeed * deltaTime;
				if (Math.Abs(diff) < change)
					mDisplayValue = targetValue;
				else
					mDisplayValue += Math.Sign(diff) * change;
				InvalidateVisual();
			}
		}

		// Update flash
		if (mFlashRemaining > 0)
		{
			mFlashRemaining -= deltaTime;
			InvalidateVisual();
		}
	}

	protected override void OnRender(DrawContext dc)
	{
		let bounds = ContentBounds;

		// Background
		dc.FillRect(bounds, mBackgroundColor);

		// Fill
		let fillAmount = Math.Clamp(mDisplayValue, 0, 1);
		RectangleF fillBounds;
		if (mOrientation == .Horizontal)
		{
			fillBounds = RectangleF(
				bounds.X,
				bounds.Y,
				bounds.Width * fillAmount,
				bounds.Height
			);
		}
		else
		{
			let fillHeight = bounds.Height * fillAmount;
			fillBounds = RectangleF(
				bounds.X,
				bounds.Y + bounds.Height - fillHeight,
				bounds.Width,
				fillHeight
			);
		}

		// Apply flash effect
		Color fillColor = mFillColor;
		if (mFlashRemaining > 0 && mFlashDuration > 0)
		{
			let flashT = mFlashRemaining / mFlashDuration;
			fillColor = LerpColor(mFillColor, mFlashColor, flashT);
		}

		dc.FillRect(fillBounds, fillColor);

		// Border
		if (mBorderWidth > 0)
		{
			dc.DrawRect(bounds, mBorderColor, mBorderWidth);
		}

		// Text (simplified - no font access yet)
		if (mShowText)
		{
			// Text rendering would go here when backend provides font access
		}
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		// Default size for resource bars
		if (mOrientation == .Horizontal)
			return Vector2(200, 24);
		else
			return Vector2(24, 200);
	}

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
