using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// A slider control that allows selecting a value from a range.
public class Slider : Control
{
	private float mValue = 0;
	private float mMinimum = 0;
	private float mMaximum = 100;
	private float mSmallChange = 1;
	private float mLargeChange = 10;
	private Orientation mOrientation = .Horizontal;
	private bool mIsDragging = false;

	private const float ThumbSize = 16.0f;
	private const float TrackThickness = 4.0f;

	// Colors
	private Color? mTrackColor = null;
	private Color? mThumbColor = null;
	private Color? mFillColor = null;

	// Value changed event
	private EventAccessor<delegate void(Slider, float)> mValueChangedEvent = new .() ~ delete _;

	/// Event fired when the value changes.
	public EventAccessor<delegate void(Slider, float)> ValueChanged => mValueChangedEvent;

	/// The current value.
	public float Value
	{
		get => mValue;
		set
		{
			let clamped = Math.Clamp(value, mMinimum, mMaximum);
			if (mValue != clamped)
			{
				mValue = clamped;
				OnValueChanged();
				InvalidateVisual();
			}
		}
	}

	/// The minimum value.
	public float Minimum
	{
		get => mMinimum;
		set
		{
			if (mMinimum != value)
			{
				mMinimum = value;
				if (mValue < mMinimum) Value = mMinimum;
				if (mMaximum < mMinimum) mMaximum = mMinimum;
				InvalidateVisual();
			}
		}
	}

	/// The maximum value.
	public float Maximum
	{
		get => mMaximum;
		set
		{
			if (mMaximum != value)
			{
				mMaximum = value;
				if (mValue > mMaximum) Value = mMaximum;
				if (mMinimum > mMaximum) mMinimum = mMaximum;
				InvalidateVisual();
			}
		}
	}

	/// Small change amount (arrow keys).
	public float SmallChange
	{
		get => mSmallChange;
		set => mSmallChange = Math.Max(0, value);
	}

	/// Large change amount (page up/down).
	public float LargeChange
	{
		get => mLargeChange;
		set => mLargeChange = Math.Max(0, value);
	}

	/// The orientation of the slider.
	public Orientation Orientation
	{
		get => mOrientation;
		set { mOrientation = value; InvalidateMeasure(); }
	}

	/// The color of the track.
	public Color? TrackColor
	{
		get => mTrackColor;
		set { mTrackColor = value; InvalidateVisual(); }
	}

	/// The color of the thumb.
	public Color? ThumbColor
	{
		get => mThumbColor;
		set { mThumbColor = value; InvalidateVisual(); }
	}

	/// The color of the filled portion of the track.
	public Color? FillColor
	{
		get => mFillColor;
		set { mFillColor = value; InvalidateVisual(); }
	}

	/// Whether the slider is currently being dragged.
	public bool IsDragging => mIsDragging;

	public this()
	{
		Focusable = true;
		Cursor = .Pointer;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (mOrientation == .Horizontal)
			return .(constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : 100, ThumbSize);
		else
			return .(ThumbSize, constraints.MaxHeight != SizeConstraints.Infinity ? constraints.MaxHeight : 100);
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		let bounds = ContentBounds;
		let theme = GetTheme();

		// Get colors from explicit values or theme
		let trackColor = mTrackColor ?? theme?.GetColor("Border") ?? Color(200, 200, 200);
		let fillColor = mFillColor ?? theme?.GetColor("Primary") ?? Color(0, 120, 215);
		var thumbColor = mThumbColor ?? theme?.GetColor("Primary") ?? Color(0, 120, 215);

		// Modify thumb color based on state
		if (!IsEnabled)
			thumbColor = theme?.GetColor("ForegroundDisabled") ?? Color(180, 180, 180);
		else if (mIsDragging)
			thumbColor = theme?.GetColor("PrimaryDark") ?? Color(0, 90, 180);
		else if (IsMouseOver)
			thumbColor = theme?.GetColor("PrimaryLight") ?? Color(30, 140, 235);

		let ratio = GetRatio();

		if (mOrientation == .Horizontal)
		{
			// Draw horizontal slider
			let trackY = bounds.Y + (bounds.Height - TrackThickness) / 2;
			let thumbX = bounds.X + ThumbSize / 2 + (bounds.Width - ThumbSize) * ratio;

			// Track background
			let trackRect = RectangleF(bounds.X + ThumbSize / 2, trackY, bounds.Width - ThumbSize, TrackThickness);
			drawContext.FillRect(trackRect, trackColor);

			// Filled portion
			let fillRect = RectangleF(bounds.X + ThumbSize / 2, trackY, thumbX - bounds.X - ThumbSize / 2, TrackThickness);
			if (fillRect.Width > 0)
				drawContext.FillRect(fillRect, fillColor);

			// Thumb
			let thumbRect = RectangleF(thumbX - ThumbSize / 2, bounds.Y + (bounds.Height - ThumbSize) / 2, ThumbSize, ThumbSize);
			drawContext.FillCircle(.(thumbRect.X + ThumbSize / 2, thumbRect.Y + ThumbSize / 2), ThumbSize / 2, thumbColor);

			// Thumb border
			if (IsFocused)
				drawContext.DrawCircle(.(thumbRect.X + ThumbSize / 2, thumbRect.Y + ThumbSize / 2), ThumbSize / 2, Color.Black, 1.5f);
		}
		else
		{
			// Draw vertical slider
			let trackX = bounds.X + (bounds.Width - TrackThickness) / 2;
			let thumbY = bounds.Bottom - ThumbSize / 2 - (bounds.Height - ThumbSize) * ratio;

			// Track background
			let trackRect = RectangleF(trackX, bounds.Y + ThumbSize / 2, TrackThickness, bounds.Height - ThumbSize);
			drawContext.FillRect(trackRect, trackColor);

			// Filled portion
			let fillRect = RectangleF(trackX, thumbY, TrackThickness, bounds.Bottom - thumbY - ThumbSize / 2);
			if (fillRect.Height > 0)
				drawContext.FillRect(fillRect, fillColor);

			// Thumb
			let thumbRect = RectangleF(bounds.X + (bounds.Width - ThumbSize) / 2, thumbY - ThumbSize / 2, ThumbSize, ThumbSize);
			drawContext.FillCircle(.(thumbRect.X + ThumbSize / 2, thumbRect.Y + ThumbSize / 2), ThumbSize / 2, thumbColor);

			// Thumb border
			if (IsFocused)
				drawContext.DrawCircle(.(thumbRect.X + ThumbSize / 2, thumbRect.Y + ThumbSize / 2), ThumbSize / 2, Color.Black, 1.5f);
		}
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		base.OnMouseDownRouted(args);

		if (args.Button == .Left && IsEnabled)
		{
			mIsDragging = true;
			Context?.CaptureMouse(this);
			UpdateValueFromPosition(args.LocalX, args.LocalY);
			UpdateControlState();
			args.Handled = true;
		}
	}

	protected override void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		base.OnMouseUpRouted(args);

		if (args.Button == .Left && mIsDragging)
		{
			mIsDragging = false;
			Context?.ReleaseMouseCapture();
			UpdateControlState();
			args.Handled = true;
		}
	}

	protected override void OnMouseMoveRouted(MouseEventArgs args)
	{
		base.OnMouseMoveRouted(args);

		if (mIsDragging)
		{
			UpdateValueFromPosition(args.LocalX, args.LocalY);
			args.Handled = true;
		}
	}

	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		base.OnKeyDownRouted(args);

		if (!IsEnabled)
			return;

		var handled = false;

		// Arrow keys
		if (mOrientation == .Horizontal)
		{
			if (args.Key == .Left)
				{ Value -= mSmallChange; handled = true; }
			else if (args.Key == .Right)
				{ Value += mSmallChange; handled = true; }
		}
		else
		{
			if (args.Key == .Up)
				{ Value += mSmallChange; handled = true; }
			else if (args.Key == .Down)
				{ Value -= mSmallChange; handled = true; }
		}

		// Page up/down
		if (args.Key == .PageUp)
			{ Value += mLargeChange; handled = true; }
		else if (args.Key == .PageDown)
			{ Value -= mLargeChange; handled = true; }

		// Home/End
		if (args.Key == .Home)
			{ Value = mMinimum; handled = true; }
		else if (args.Key == .End)
			{ Value = mMaximum; handled = true; }

		if (handled)
			args.Handled = true;
	}

	private void UpdateValueFromPosition(float localX, float localY)
	{
		let bounds = ContentBounds;
		let range = mMaximum - mMinimum;

		float ratio;
		if (mOrientation == .Horizontal)
		{
			let trackStart = ThumbSize / 2;
			let trackLength = bounds.Width - ThumbSize;
			ratio = Math.Clamp((localX - trackStart) / trackLength, 0, 1);
		}
		else
		{
			let trackStart = ThumbSize / 2;
			let trackLength = bounds.Height - ThumbSize;
			// Invert for vertical (bottom = min, top = max)
			ratio = 1.0f - Math.Clamp((localY - trackStart) / trackLength, 0, 1);
		}

		Value = mMinimum + range * ratio;
	}

	private float GetRatio()
	{
		let range = mMaximum - mMinimum;
		if (range <= 0) return 0;
		return (mValue - mMinimum) / range;
	}

	protected virtual void OnValueChanged()
	{
		mValueChangedEvent.[Friend]Invoke(this, mValue);
	}
}
