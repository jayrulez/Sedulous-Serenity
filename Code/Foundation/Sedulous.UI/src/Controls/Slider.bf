namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Value slider with mouse capture drag.
public class Slider : View
{
	private float mValue = 0;
	private float mMin = 0;
	private float mMax = 1;
	private float mStep = 0; // 0 = continuous
	private Orientation mOrientation = .Horizontal;
	private bool mIsDragging;

	private EventAccessor<delegate void(Slider, float)> mOnValueChanged = new .() ~ delete _;

	// Visual constants
	private const float TrackHeight = 4;
	private const float ThumbSize = 14;

	public float Value
	{
		get => mValue;
		set
		{
			float clamped = Math.Clamp(value, mMin, mMax);
			if (mStep > 0)
				clamped = SnapToStep(clamped);

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
		set
		{
			mMin = value;
			if (mMax < mMin) mMax = mMin;
			Value = mValue; // re-clamp
		}
	}

	public float Max
	{
		get => mMax;
		set
		{
			mMax = value;
			if (mMin > mMax) mMin = mMax;
			Value = mValue; // re-clamp
		}
	}

	public float Step
	{
		get => mStep;
		set { mStep = Math.Max(0, value); Value = mValue; }
	}

	public Orientation Orientation
	{
		get => mOrientation;
		set { mOrientation = value; InvalidateLayout(); }
	}

	/// Subscribe to value change events.
	public EventAccessor<delegate void(Slider, float)> OnValueChanged => mOnValueChanged;

	public this()
	{
		Focusable = true;
		CursorType = .Pointer;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float desiredW, desiredH;

		if (mOrientation == .Horizontal)
		{
			desiredW = 0; // fill available
			desiredH = 24;
		}
		else
		{
			desiredW = 24;
			desiredH = 0; // fill available
		}

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		float ratio = (mMax > mMin) ? (mValue - mMin) / (mMax - mMin) : 0;

		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;
		let trackBg = theme?.GetColor("Slider", "track") ?? .(0.2f, 0.2f, 0.25f, 1.0f);
		let fillColor = theme?.GetColor("Slider", "fill") ?? palette.Accent;
		let thumbNormal = theme?.GetColor("Slider", "thumb") ?? .(0.85f, 0.85f, 0.9f, 1.0f);
		let thumbHoverColor = theme?.GetColor("Slider", "thumbHover") ?? .(0.95f, 0.95f, 1.0f, 1.0f);
		let focusBorder = GetFocusBorderColor();

		if (mOrientation == .Horizontal)
			DrawHorizontal(ctx, ratio, trackBg, fillColor, thumbNormal, thumbHoverColor, focusBorder);
		else
			DrawVertical(ctx, ratio, trackBg, fillColor, thumbNormal, thumbHoverColor, focusBorder);
	}

	private void DrawHorizontal(DrawContext ctx, float ratio, Color trackBg, Color fillColor,
		Color thumbNormal, Color thumbHoverColor, Color focusBorder)
	{
		let theme = Context?.Theme;
		float thumbHalf = ThumbSize * 0.5f;
		float trackStart = thumbHalf;
		float trackEnd = Width - thumbHalf;
		float trackW = trackEnd - trackStart;

		// Track background — use drawable's intrinsic height if available
		let trackDrawable = theme?.GetDrawable("Slider", "track");
		float trackH = TrackHeight;
		if (trackDrawable != null)
		{
			let intrinsic = trackDrawable.IntrinsicSize;
			if (intrinsic.Height > 0)
				trackH = intrinsic.Height;
		}
		float trackY = (Height - trackH) * 0.5f;

		if (trackDrawable != null)
			trackDrawable.Draw(ctx, .(trackStart, trackY, trackW, trackH), GetControlState());
		else
			ctx.FillRoundedRect(.(trackStart, trackY, trackW, trackH), trackH * 0.5f, trackBg);

		// Fill
		float fillW = trackW * ratio;
		if (fillW > 0)
		{
			let fillDrawable = theme?.GetDrawable("Slider", "fill");
			if (fillDrawable != null)
			{
				ctx.PushClipRect(.(trackStart, trackY, fillW, trackH));
				fillDrawable.Draw(ctx, .(trackStart, trackY, trackW, trackH), GetControlState());
				ctx.PopClip();
			}
			else
				ctx.FillRoundedRect(.(trackStart, trackY, fillW, trackH), trackH * 0.5f, fillColor);
		}

		// Thumb
		float thumbX = trackStart + trackW * ratio;
		float thumbY = Height * 0.5f;
		let thumbDrawable = theme?.GetDrawable("Slider", "thumb");
		if (thumbDrawable != null)
		{
			let thumbSize = thumbDrawable.IntrinsicSize;
			let tw = (thumbSize.Width > 0) ? thumbSize.Width : ThumbSize;
			let th = (thumbSize.Height > 0) ? thumbSize.Height : ThumbSize;
			thumbDrawable.Draw(ctx, .(thumbX - tw * 0.5f, thumbY - th * 0.5f, tw, th), GetControlState());
		}
		else
		{
			Color thumbColor = (IsHovered || mIsDragging) ? thumbHoverColor : thumbNormal;
			ctx.FillCircle(.(thumbX, thumbY), thumbHalf, thumbColor);
		}

		if (IsFocused && thumbDrawable == null)
			ctx.DrawCircle(.(thumbX, thumbY), thumbHalf + 2, focusBorder, 2);
	}

	private void DrawVertical(DrawContext ctx, float ratio, Color trackBg, Color fillColor,
		Color thumbNormal, Color thumbHoverColor, Color focusBorder)
	{
		let theme = Context?.Theme;
		float thumbHalf = ThumbSize * 0.5f;
		float trackStart = thumbHalf;
		float trackEnd = Height - thumbHalf;
		float trackLen = trackEnd - trackStart;

		// Track background — use drawable's intrinsic width if available
		let trackDrawable = theme?.GetDrawable("Slider", "track");
		float trackW = TrackHeight;
		if (trackDrawable != null)
		{
			let intrinsic = trackDrawable.IntrinsicSize;
			if (intrinsic.Width > 0)
				trackW = intrinsic.Width;
		}
		float trackX = (Width - trackW) * 0.5f;

		if (trackDrawable != null)
			trackDrawable.Draw(ctx, .(trackX, trackStart, trackW, trackLen), GetControlState());
		else
			ctx.FillRoundedRect(.(trackX, trackStart, trackW, trackLen), trackW * 0.5f, trackBg);

		// Fill
		float fillH = trackLen * ratio;
		if (fillH > 0)
		{
			let fillDrawable = theme?.GetDrawable("Slider", "fill");
			if (fillDrawable != null)
			{
				ctx.PushClipRect(.(trackX, trackEnd - fillH, trackW, fillH));
				fillDrawable.Draw(ctx, .(trackX, trackStart, trackW, trackLen), GetControlState());
				ctx.PopClip();
			}
			else
				ctx.FillRoundedRect(.(trackX, trackEnd - fillH, trackW, fillH), trackW * 0.5f, fillColor);
		}

		// Thumb
		float thumbX = Width * 0.5f;
		float thumbY = trackEnd - trackLen * ratio;
		let thumbDrawable = theme?.GetDrawable("Slider", "thumb");
		if (thumbDrawable != null)
		{
			let thumbSize = thumbDrawable.IntrinsicSize;
			let tw = (thumbSize.Width > 0) ? thumbSize.Width : ThumbSize;
			let th = (thumbSize.Height > 0) ? thumbSize.Height : ThumbSize;
			thumbDrawable.Draw(ctx, .(thumbX - tw * 0.5f, thumbY - th * 0.5f, tw, th), GetControlState());
		}
		else
		{
			Color thumbColor = (IsHovered || mIsDragging) ? thumbHoverColor : thumbNormal;
			ctx.FillCircle(.(thumbX, thumbY), thumbHalf, thumbColor);
		}

		if (IsFocused && thumbDrawable == null)
			ctx.DrawCircle(.(thumbX, thumbY), thumbHalf + 2, focusBorder, 2);
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		e.Handled = true;
		mIsDragging = true;
		Context?.FocusManager.SetCapture(this);
		UpdateValueFromMouse(e.LocalX, e.LocalY);
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		if (mIsDragging)
			UpdateValueFromMouse(e.LocalX, e.LocalY);
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

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled)
			return;

		float stepAmount = mStep > 0 ? mStep : (mMax - mMin) * 0.05f;

		if (mOrientation == .Horizontal)
		{
			if (e.Key == .Right) { Value = mValue + stepAmount; e.Handled = true; }
			else if (e.Key == .Left) { Value = mValue - stepAmount; e.Handled = true; }
		}
		else
		{
			if (e.Key == .Up) { Value = mValue + stepAmount; e.Handled = true; }
			else if (e.Key == .Down) { Value = mValue - stepAmount; e.Handled = true; }
		}

		if (e.Key == .Home) { Value = mMin; e.Handled = true; }
		else if (e.Key == .End) { Value = mMax; e.Handled = true; }
	}

	private void UpdateValueFromMouse(float localX, float localY)
	{
		float thumbHalf = ThumbSize * 0.5f;
		float ratio;

		if (mOrientation == .Horizontal)
		{
			float trackStart = thumbHalf;
			float trackW = Width - ThumbSize;
			ratio = (trackW > 0) ? (localX - trackStart) / trackW : 0;
		}
		else
		{
			float trackStart = thumbHalf;
			float trackH = Height - ThumbSize;
			ratio = (trackH > 0) ? 1.0f - (localY - trackStart) / trackH : 0;
		}

		ratio = Math.Clamp(ratio, 0, 1);
		Value = mMin + ratio * (mMax - mMin);
	}

	private float SnapToStep(float value)
	{
		if (mStep <= 0)
			return value;

		float snapped = mMin + Math.Round((value - mMin) / mStep) * mStep;
		return Math.Clamp(snapped, mMin, mMax);
	}
}
