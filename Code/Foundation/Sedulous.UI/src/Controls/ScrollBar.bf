namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Scrollbar control with proportional thumb and track.
/// Usable inside ScrollView or independently.
public class ScrollBar : View
{
	private float mValue = 0;
	private float mMin = 0;
	private float mMax = 100;
	private float mViewportSize = 0;
	private float mSmallChange = 20;
	private float mLargeChange = 0; // 0 = auto: 90% of viewport
	private Orientation mOrientation = .Vertical;
	private bool mIsDragging;
	private float mDragStartValue;
	private float mDragStartMouse;

	private const float MinThumbSize = 20;
	private const float DefaultThickness = 12;
	private const float TrackPadding = 2;
	private const float ThumbCornerRadius = 3;

	private EventAccessor<delegate void(ScrollBar, float)> mOnValueChanged = new .() ~ delete _;

	public float Value
	{
		get => mValue;
		set
		{
			float clamped = Math.Clamp(value, mMin, MaxScrollValue);
			if (mValue != clamped)
			{
				mValue = clamped;
				Invalidate();
				mOnValueChanged.[Friend]Invoke(this, clamped);
			}
		}
	}

	public float Min
	{
		get => mMin;
		set { mMin = value; if (mMax < mMin) mMax = mMin; Value = mValue; }
	}

	public float Max
	{
		get => mMax;
		set { mMax = value; if (mMin > mMax) mMin = mMax; Value = mValue; }
	}

	public float ViewportSize
	{
		get => mViewportSize;
		set { mViewportSize = Math.Max(0, value); Value = mValue; Invalidate(); }
	}

	public float SmallChange
	{
		get => mSmallChange;
		set { mSmallChange = Math.Max(0, value); }
	}

	public float LargeChange
	{
		get => mLargeChange;
		set { mLargeChange = Math.Max(0, value); }
	}

	public Orientation Orientation
	{
		get => mOrientation;
		set { mOrientation = value; InvalidateLayout(); }
	}

	/// Total range: Max - Min.
	public float Range => Math.Max(0, mMax - mMin);

	/// Maximum scroll value: Max - ViewportSize (clamped to Min).
	public float MaxScrollValue => Math.Max(mMin, mMax - mViewportSize);

	/// Whether the scrollbar is needed (content exceeds viewport).
	public bool IsNeeded => (mMax - mMin) > mViewportSize;

	/// Effective large change: if LargeChange is 0, uses 90% of viewport.
	public float EffectiveLargeChange => (mLargeChange > 0) ? mLargeChange : mViewportSize * 0.9f;

	/// Preferred thickness (width for vertical, height for horizontal).
	/// Reads from theme "ScrollBar"/"thickness", falls back to DefaultThickness.
	public float Thickness
	{
		get
		{
			let t = Context?.Theme?.GetDimension("ScrollBar", "thickness");
			return (t != null) ? t.Value : DefaultThickness;
		}
	}

	/// Subscribe to value change events.
	public EventAccessor<delegate void(ScrollBar, float)> OnValueChanged => mOnValueChanged;

	public this()
	{
		IsHitTestVisible = true;
	}

	public this(Orientation orientation) : this()
	{
		mOrientation = orientation;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float thick = Thickness;
		float desiredW, desiredH;
		if (mOrientation == .Vertical)
		{
			desiredW = thick;
			desiredH = 0; // fill available
		}
		else
		{
			desiredW = 0; // fill available
			desiredH = thick;
		}

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let trackColor = theme?.GetColor("ScrollBar", "track") ?? .(0.15f, 0.15f, 0.2f, 0.5f);
		let thumbColor = GetThumbColor();

		// Track background — try orientation-specific drawable, fall back to generic
		let trackKey = (mOrientation == .Vertical) ? "trackVertical" : "trackHorizontal";
		let trackDrawable = theme?.GetDrawable("ScrollBar", trackKey) ?? theme?.GetDrawable("ScrollBar", "track");
		if (trackDrawable != null)
			trackDrawable.Draw(ctx, .(0, 0, Width, Height), GetControlState());
		else
			ctx.FillRoundedRect(.(TrackPadding, TrackPadding, Width - TrackPadding * 2, Height - TrackPadding * 2), ThumbCornerRadius, trackColor);

		// Thumb
		let scrollRange = MaxScrollValue - mMin;
		if (scrollRange <= 0 || Range <= 0)
			return;

		let (thumbStart, thumbLength) = GetThumbGeometry();

		let thumbKey = (mOrientation == .Vertical) ? "thumbVertical" : "thumbHorizontal";
		let thumbDrawable = theme?.GetDrawable("ScrollBar", thumbKey) ?? theme?.GetDrawable("ScrollBar", "thumb");
		if (mOrientation == .Vertical)
		{
			if (thumbDrawable != null)
				thumbDrawable.Draw(ctx, .(0, thumbStart, Width, thumbLength), GetControlState());
			else
				ctx.FillRoundedRect(.(TrackPadding, thumbStart, Width - TrackPadding * 2, thumbLength), ThumbCornerRadius, thumbColor);
		}
		else
		{
			if (thumbDrawable != null)
				thumbDrawable.Draw(ctx, .(thumbStart, 0, thumbLength, Height), GetControlState());
			else
				ctx.FillRoundedRect(.(thumbStart, TrackPadding, thumbLength, Height - TrackPadding * 2), ThumbCornerRadius, thumbColor);
		}
	}

	private Color GetThumbColor()
	{
		let theme = Context?.Theme;
		if (mIsDragging)
			return theme?.GetColor("ScrollBar", "thumbDrag") ?? .(0.55f, 0.55f, 0.7f, 1.0f);
		if (IsHovered)
			return theme?.GetColor("ScrollBar", "thumbHover") ?? .(0.5f, 0.5f, 0.6f, 0.9f);
		return theme?.GetColor("ScrollBar", "thumb") ?? .(0.4f, 0.4f, 0.5f, 0.8f);
	}

	/// Returns (start position, length) of the thumb in pixels along the main axis.
	public (float start, float length) GetThumbGeometry()
	{
		float trackLength = (mOrientation == .Vertical) ? Height : Width;
		float scrollRange = MaxScrollValue - mMin;

		// Thumb size proportional to viewport/range
		float thumbRatio = Math.Clamp(mViewportSize / Range, 0, 1);
		float thumbLength = Math.Max(MinThumbSize, thumbRatio * trackLength);

		// Thumb position
		float thumbTravel = trackLength - thumbLength;
		float thumbPos = (scrollRange > 0) ? ((mValue - mMin) / scrollRange) * thumbTravel : 0;

		return (thumbPos, thumbLength);
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return;

		e.Handled = true;
		let scrollRange = MaxScrollValue - mMin;
		if (scrollRange <= 0)
			return;

		float mousePos = (mOrientation == .Vertical) ? e.LocalY : e.LocalX;
		let (thumbStart, thumbLength) = GetThumbGeometry();

		if (mousePos >= thumbStart && mousePos <= thumbStart + thumbLength)
		{
			// Drag thumb
			mIsDragging = true;
			mDragStartValue = mValue;
			mDragStartMouse = mousePos;
			Context?.FocusManager.SetCapture(this);
		}
		else if (mousePos < thumbStart)
		{
			// Page up/left
			Value = mValue - EffectiveLargeChange;
		}
		else
		{
			// Page down/right
			Value = mValue + EffectiveLargeChange;
		}
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		if (!mIsDragging)
			return;

		float mousePos = (mOrientation == .Vertical) ? e.LocalY : e.LocalX;
		float trackLength = (mOrientation == .Vertical) ? Height : Width;
		let (_, thumbLength) = GetThumbGeometry();
		float thumbTravel = trackLength - thumbLength;

		if (thumbTravel <= 0)
			return;

		float mouseDelta = mousePos - mDragStartMouse;
		float scrollRange = MaxScrollValue - mMin;
		float valueDelta = mouseDelta * (scrollRange / thumbTravel);
		Value = mDragStartValue + valueDelta;
	}

	public override void OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return;

		if (mIsDragging)
		{
			mIsDragging = false;
			Context?.FocusManager.ReleaseCapture();
			e.Handled = true;
		}
	}
}
