using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Slider control for value selection.
class Slider : Widget
{
	private float mValue = 0;
	private float mMinimum = 0;
	private float mMaximum = 1;
	private float mStep = 0;
	private Orientation mOrientation = .Horizontal;

	private Color mTrackColor = Color(60, 60, 60, 255);
	private Color mFillColor = Color(60, 120, 200, 255);
	private Color mThumbColor = Color(200, 200, 200, 255);
	private Color mThumbHoverColor = Color(230, 230, 230, 255);
	private Color mThumbPressedColor = Color(170, 170, 170, 255);

	private float mTrackHeight = 4;
	private float mThumbSize = 16;
	private CornerRadius mTrackRadius = .Uniform(2);

	private bool mIsHovered;
	private bool mIsDragging;

	/// Event raised when the value changes.
	public Event<delegate void(float)> OnValueChanged ~ _.Dispose();

	/// Creates a slider.
	public this()
	{
		IsFocusable = true;
		MinWidth = 100;
		MinHeight = 20;
	}

	/// Gets or sets the current value.
	public float Value
	{
		get => mValue;
		set
		{
			var newValue = Math.Clamp(value, mMinimum, mMaximum);

			// Apply step
			if (mStep > 0)
			{
				let steps = Math.Round((newValue - mMinimum) / mStep);
				newValue = mMinimum + steps * mStep;
				newValue = Math.Clamp(newValue, mMinimum, mMaximum);
			}

			if (mValue != newValue)
			{
				mValue = newValue;
				InvalidateVisual();
				OnValueChanged(mValue);
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
					Value = mMinimum;
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
					Value = mMaximum;
				InvalidateVisual();
			}
		}
	}

	/// Gets or sets the step size (0 = continuous).
	public float Step
	{
		get => mStep;
		set => mStep = Math.Max(0, value);
	}

	/// Gets the normalized value (0-1).
	public float NormalizedValue
	{
		get
		{
			let range = mMaximum - mMinimum;
			if (range <= 0)
				return 0;
			return (mValue - mMinimum) / range;
		}
		set
		{
			Value = mMinimum + Math.Clamp(value, 0, 1) * (mMaximum - mMinimum);
		}
	}

	/// Gets or sets the orientation.
	public Orientation Orientation
	{
		get => mOrientation;
		set { if (mOrientation != value) { mOrientation = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the track color.
	public Color TrackColor
	{
		get => mTrackColor;
		set => mTrackColor = value;
	}

	/// Gets or sets the fill color.
	public Color FillColor
	{
		get => mFillColor;
		set => mFillColor = value;
	}

	/// Gets or sets the thumb color.
	public Color ThumbColor
	{
		get => mThumbColor;
		set => mThumbColor = value;
	}

	/// Gets or sets the thumb size.
	public float ThumbSize
	{
		get => mThumbSize;
		set { if (mThumbSize != value) { mThumbSize = value; InvalidateMeasure(); } }
	}

	/// Measures the slider.
	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		if (mOrientation == .Horizontal)
			return Vector2(100, Math.Max(mThumbSize, mTrackHeight));
		else
			return Vector2(Math.Max(mThumbSize, mTrackHeight), 100);
	}

	/// Gets the thumb rectangle.
	private RectangleF GetThumbRect()
	{
		let bounds = Bounds;
		let normalized = NormalizedValue;

		if (mOrientation == .Horizontal)
		{
			let trackWidth = bounds.Width - mThumbSize;
			let thumbX = bounds.X + trackWidth * normalized;
			let thumbY = bounds.Y + (bounds.Height - mThumbSize) / 2;
			return RectangleF(thumbX, thumbY, mThumbSize, mThumbSize);
		}
		else
		{
			let trackHeight = bounds.Height - mThumbSize;
			let thumbX = bounds.X + (bounds.Width - mThumbSize) / 2;
			let thumbY = bounds.Bottom - mThumbSize - trackHeight * normalized;
			return RectangleF(thumbX, thumbY, mThumbSize, mThumbSize);
		}
	}

	/// Converts a position to a value.
	private float PositionToValue(Vector2 position)
	{
		let bounds = Bounds;

		if (mOrientation == .Horizontal)
		{
			let trackWidth = bounds.Width - mThumbSize;
			if (trackWidth <= 0)
				return mMinimum;
			let normalized = (position.X - bounds.X - mThumbSize / 2) / trackWidth;
			return mMinimum + Math.Clamp(normalized, 0, 1) * (mMaximum - mMinimum);
		}
		else
		{
			let trackHeight = bounds.Height - mThumbSize;
			if (trackHeight <= 0)
				return mMinimum;
			let normalized = 1 - (position.Y - bounds.Y - mThumbSize / 2) / trackHeight;
			return mMinimum + Math.Clamp(normalized, 0, 1) * (mMaximum - mMinimum);
		}
	}

	/// Renders the slider.
	protected override void OnRender(DrawContext dc)
	{
		let bounds = Bounds;
		let normalized = NormalizedValue;

		// Calculate track bounds
		RectangleF trackRect;
		RectangleF fillRect;

		if (mOrientation == .Horizontal)
		{
			let trackY = bounds.Y + (bounds.Height - mTrackHeight) / 2;
			trackRect = RectangleF(bounds.X + mThumbSize / 2, trackY, bounds.Width - mThumbSize, mTrackHeight);
			fillRect = RectangleF(trackRect.X, trackRect.Y, trackRect.Width * normalized, mTrackHeight);
		}
		else
		{
			let trackX = bounds.X + (bounds.Width - mTrackHeight) / 2;
			trackRect = RectangleF(trackX, bounds.Y + mThumbSize / 2, mTrackHeight, bounds.Height - mThumbSize);
			let fillHeight = trackRect.Height * normalized;
			fillRect = RectangleF(trackRect.X, trackRect.Bottom - fillHeight, mTrackHeight, fillHeight);
		}

		// Draw track
		dc.FillRoundedRect(trackRect, mTrackRadius, mTrackColor);

		// Draw fill
		if (normalized > 0)
			dc.FillRoundedRect(fillRect, mTrackRadius, mFillColor);

		// Draw thumb
		let thumbRect = GetThumbRect();
		var thumbColor = mThumbColor;
		if (mIsDragging)
			thumbColor = mThumbPressedColor;
		else if (mIsHovered)
			thumbColor = mThumbHoverColor;

		dc.FillCircle(
			Vector2(thumbRect.X + thumbRect.Width / 2, thumbRect.Y + thumbRect.Height / 2),
			mThumbSize / 2,
			thumbColor
		);

		// Draw focus ring
		if (IsFocused)
		{
			dc.DrawCircle(
				Vector2(thumbRect.X + thumbRect.Width / 2, thumbRect.Y + thumbRect.Height / 2),
				mThumbSize / 2 + 2,
				Color(100, 150, 255, 200),
				2
			);
		}
	}

	/// Handles mouse enter.
	protected override bool OnMouseEnter(MouseEventArgs e)
	{
		mIsHovered = true;
		InvalidateVisual();
		return false;
	}

	/// Handles mouse leave.
	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		mIsHovered = false;
		InvalidateVisual();
		return false;
	}

	/// Handles mouse down.
	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && IsEnabled)
		{
			mIsDragging = true;
			Context?.Input.CaptureMouse(this);
			Value = PositionToValue(e.ScreenPosition);
			InvalidateVisual();
			return true;
		}
		return false;
	}

	/// Handles mouse up.
	protected override bool OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && mIsDragging)
		{
			mIsDragging = false;
			Context?.Input.ReleaseMouse();
			InvalidateVisual();
			return true;
		}
		return false;
	}

	/// Handles mouse move.
	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		if (mIsDragging)
		{
			Value = PositionToValue(e.ScreenPosition);
			return true;
		}
		return false;
	}

	/// Handles key down.
	protected override bool OnKeyDown(KeyEventArgs e)
	{
		if (!IsEnabled)
			return false;

		let stepSize = (mStep > 0) ? mStep : (mMaximum - mMinimum) / 10;

		switch (e.Key)
		{
		case .Left, .Down:
			Value = mValue - stepSize;
			return true;
		case .Right, .Up:
			Value = mValue + stepSize;
			return true;
		case .Home:
			Value = mMinimum;
			return true;
		case .End:
			Value = mMaximum;
			return true;
		default:
			return false;
		}
	}
}
