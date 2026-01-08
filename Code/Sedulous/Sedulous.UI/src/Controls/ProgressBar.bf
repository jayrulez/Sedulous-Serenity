using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Progress indicator widget.
class ProgressBar : Widget
{
	private float mValue = 0;
	private float mMinimum = 0;
	private float mMaximum = 1;
	private bool mIsIndeterminate;
	private Orientation mOrientation = .Horizontal;

	private Color mBackgroundColor = Color(40, 40, 40, 255);
	private Color mFillColor = Color(60, 120, 200, 255);
	private Color mBorderColor = Color(80, 80, 80, 255);
	private float mBorderWidth = 1;
	private CornerRadius mCornerRadius = .Uniform(3);

	// Animation for indeterminate mode
	private float mIndeterminateOffset;

	/// Creates a progress bar.
	public this()
	{
		IsFocusable = false;
		MinHeight = 8;
		MinWidth = 50;
	}

	/// Gets or sets the current value.
	public float Value
	{
		get => mValue;
		set
		{
			let clamped = Math.Clamp(value, mMinimum, mMaximum);
			if (mValue != clamped)
			{
				mValue = clamped;
				InvalidateVisual();
			}
		}
	}

	/// Gets or sets the minimum value.
	public float Minimum
	{
		get => mMinimum;
		set
		{
			if (mMinimum != value)
			{
				mMinimum = value;
				if (mValue < mMinimum)
					mValue = mMinimum;
				InvalidateVisual();
			}
		}
	}

	/// Gets or sets the maximum value.
	public float Maximum
	{
		get => mMaximum;
		set
		{
			if (mMaximum != value)
			{
				mMaximum = value;
				if (mValue > mMaximum)
					mValue = mMaximum;
				InvalidateVisual();
			}
		}
	}

	/// Gets the normalized progress (0-1).
	public float NormalizedValue
	{
		get
		{
			let range = mMaximum - mMinimum;
			if (range <= 0)
				return 0;
			return (mValue - mMinimum) / range;
		}
	}

	/// Gets or sets whether the progress is indeterminate.
	public bool IsIndeterminate
	{
		get => mIsIndeterminate;
		set { mIsIndeterminate = value; InvalidateVisual(); }
	}

	/// Gets or sets the orientation.
	public Orientation Orientation
	{
		get => mOrientation;
		set { if (mOrientation != value) { mOrientation = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the background color.
	public Color BackgroundColor
	{
		get => mBackgroundColor;
		set => mBackgroundColor = value;
	}

	/// Gets or sets the fill color.
	public Color FillColor
	{
		get => mFillColor;
		set => mFillColor = value;
	}

	/// Gets or sets the border color.
	public Color BorderColor
	{
		get => mBorderColor;
		set => mBorderColor = value;
	}

	/// Gets or sets the corner radius.
	public CornerRadius CornerRadius
	{
		get => mCornerRadius;
		set => mCornerRadius = value;
	}

	/// Measures the progress bar.
	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		if (mOrientation == .Horizontal)
			return Vector2(100, 16);
		else
			return Vector2(16, 100);
	}

	/// Updates the indeterminate animation.
	protected override void OnUpdate(float deltaTime)
	{
		if (mIsIndeterminate)
		{
			mIndeterminateOffset += deltaTime * 2;
			if (mIndeterminateOffset > 2)
				mIndeterminateOffset -= 2;
			InvalidateVisual();
		}
	}

	/// Renders the progress bar.
	protected override void OnRender(DrawContext dc)
	{
		let bounds = Bounds;

		// Draw background
		if (mCornerRadius.IsZero)
		{
			dc.FillRect(bounds, mBackgroundColor);
			if (mBorderWidth > 0)
				dc.DrawRect(bounds, mBorderColor, mBorderWidth);
		}
		else
		{
			dc.FillRoundedRect(bounds, mCornerRadius, mBackgroundColor);
			if (mBorderWidth > 0)
				dc.DrawRoundedRect(bounds, mCornerRadius, mBorderColor, mBorderWidth);
		}

		// Draw fill
		if (mIsIndeterminate)
		{
			// Indeterminate: sliding bar
			let barWidth = (mOrientation == .Horizontal) ? bounds.Width * 0.3f : bounds.Height * 0.3f;
			let offset = mIndeterminateOffset;
			var pos = (offset < 1) ? offset : (2 - offset); // Bounce 0->1->0

			RectangleF fillRect;
			if (mOrientation == .Horizontal)
			{
				let x = bounds.X + (bounds.Width - barWidth) * pos;
				fillRect = RectangleF(x, bounds.Y, barWidth, bounds.Height);
			}
			else
			{
				let y = bounds.Y + (bounds.Height - barWidth) * pos;
				fillRect = RectangleF(bounds.X, y, bounds.Width, barWidth);
			}

			if (mCornerRadius.IsZero)
				dc.FillRect(fillRect, mFillColor);
			else
				dc.FillRoundedRect(fillRect, mCornerRadius, mFillColor);
		}
		else
		{
			// Determinate: fill proportionally
			let progress = NormalizedValue;
			if (progress > 0)
			{
				RectangleF fillRect;
				if (mOrientation == .Horizontal)
				{
					fillRect = RectangleF(
						bounds.X,
						bounds.Y,
						bounds.Width * progress,
						bounds.Height
					);
				}
				else
				{
					let fillHeight = bounds.Height * progress;
					fillRect = RectangleF(
						bounds.X,
						bounds.Bottom - fillHeight,
						bounds.Width,
						fillHeight
					);
				}

				if (mCornerRadius.IsZero)
					dc.FillRect(fillRect, mFillColor);
				else
					dc.FillRoundedRect(fillRect, mCornerRadius, mFillColor);
			}
		}
	}
}
