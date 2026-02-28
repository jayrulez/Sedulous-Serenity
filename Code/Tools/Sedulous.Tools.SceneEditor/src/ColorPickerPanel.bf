namespace Sedulous.Tools.SceneEditor;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;
using Sedulous.Core.Core;
using Sedulous.GUI;

/// HSV color picker with a saturation/value square and a hue bar.
class ColorPickerPanel : Control
{
	private const float SVSize = 180;
	private const float HueBarWidth = 20;
	private const float Gap = 8;
	private const float TotalWidth = SVSize + Gap + HueBarWidth;
	private const float TotalHeight = SVSize;

	// HSV state (H in 0-360, S and V in 0-1)
	private float mHue = 0;
	private float mSaturation = 1;
	private float mValue = 1;

	// Drag state
	private enum DragTarget { None, SVSquare, HueBar }
	private DragTarget mDragTarget = .None;

	// Events
	private EventAccessor<delegate void(Vector3)> mColorChanged = new .() ~ delete _;

	/// Fires when the color changes. Payload is RGB as Vector3 (0-1).
	public EventAccessor<delegate void(Vector3)> ColorChanged => mColorChanged;

	public this()
	{
		IsFocusable = true;
	}

	/// Sets the current color from RGB (0-1). Converts to HSV internally.
	public void SetColor(Vector3 rgb)
	{
		RgbToHsv(rgb, out mHue, out mSaturation, out mValue);
	}

	/// Gets the current color as RGB (0-1).
	public Vector3 GetColor()
	{
		return HsvToRgb(mHue, mSaturation, mValue);
	}

	// === Layout ===

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		return .(TotalWidth, TotalHeight);
	}

	// === Rendering ===

	protected override void RenderOverride(DrawContext ctx)
	{
		let bounds = ArrangedBounds;
		let svRect = RectangleF(bounds.X, bounds.Y, SVSize, SVSize);
		let hueRect = RectangleF(bounds.X + SVSize + Gap, bounds.Y, HueBarWidth, SVSize);

		RenderSVSquare(ctx, svRect);
		RenderHueBar(ctx, hueRect);
		RenderSVIndicator(ctx, svRect);
		RenderHueIndicator(ctx, hueRect);
	}

	private void RenderSVSquare(DrawContext ctx, RectangleF rect)
	{
		// Layer 1: White → pure hue color (left to right = saturation)
		let hueColor = HsvToColor(mHue, 1, 1);
		let hGrad = scope LinearGradientBrush(
			.(rect.X, rect.Y), .(rect.Right, rect.Y),
			Color.White, hueColor);
		ctx.FillRect(rect, hGrad);

		// Layer 2: Transparent → black (top to bottom = value)
		let vGrad = scope LinearGradientBrush(
			.(rect.X, rect.Y), .(rect.X, rect.Bottom),
			Color(0, 0, 0, 0), Color(0, 0, 0, 255));
		ctx.FillRect(rect, vGrad);

		// Border
		ctx.DrawRect(rect, Color(80, 80, 80), 1);
	}

	private void RenderHueBar(DrawContext ctx, RectangleF rect)
	{
		// 6 rainbow segments
		Color[7] hueColors = .(
			Color(255, 0, 0),     // Red      (0°)
			Color(255, 255, 0),   // Yellow   (60°)
			Color(0, 255, 0),     // Green    (120°)
			Color(0, 255, 255),   // Cyan     (180°)
			Color(0, 0, 255),     // Blue     (240°)
			Color(255, 0, 255),   // Magenta  (300°)
			Color(255, 0, 0)      // Red      (360°)
		);

		let segHeight = rect.Height / 6;
		for (int i = 0; i < 6; i++)
		{
			let segRect = RectangleF(rect.X, rect.Y + segHeight * i, rect.Width, segHeight);
			let grad = scope LinearGradientBrush(
				.(segRect.X, segRect.Y), .(segRect.X, segRect.Bottom),
				hueColors[i], hueColors[i + 1]);
			ctx.FillRect(segRect, grad);
		}

		// Border
		ctx.DrawRect(rect, Color(80, 80, 80), 1);
	}

	private void RenderSVIndicator(DrawContext ctx, RectangleF rect)
	{
		let x = rect.X + mSaturation * rect.Width;
		let y = rect.Y + (1 - mValue) * rect.Height;

		// Crosshair
		let indicatorColor = (mValue > 0.5f) ? Color(0, 0, 0) : Color(255, 255, 255);
		ctx.DrawLine(.(x - 5, y), .(x + 5, y), indicatorColor, 1);
		ctx.DrawLine(.(x, y - 5), .(x, y + 5), indicatorColor, 1);
	}

	private void RenderHueIndicator(DrawContext ctx, RectangleF rect)
	{
		let y = rect.Y + (mHue / 360) * rect.Height;

		// Horizontal line markers
		ctx.DrawLine(.(rect.X - 1, y), .(rect.Right + 1, y), Color.White, 2);
		ctx.DrawLine(.(rect.X - 1, y), .(rect.Right + 1, y), Color(0, 0, 0), 1);
	}

	// === Input ===

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		base.OnMouseDown(e);
		if (e.Button != .Left) return;

		let x = e.LocalX;
		let y = e.LocalY;

		// Check SV square
		if (x >= 0 && x < SVSize && y >= 0 && y < SVSize)
		{
			mDragTarget = .SVSquare;
			UpdateSV(x, y);
			Context?.FocusManager?.SetCapture(this);
			e.Handled = true;
		}
		// Check hue bar
		else if (x >= SVSize + Gap && x < TotalWidth && y >= 0 && y < SVSize)
		{
			mDragTarget = .HueBar;
			UpdateHue(y);
			Context?.FocusManager?.SetCapture(this);
			e.Handled = true;
		}
	}

	protected override void OnMouseMove(MouseEventArgs e)
	{
		base.OnMouseMove(e);

		switch (mDragTarget)
		{
		case .SVSquare:
			UpdateSV(e.LocalX, e.LocalY);
		case .HueBar:
			UpdateHue(e.LocalY);
		case .None:
		}
	}

	protected override void OnMouseUp(MouseButtonEventArgs e)
	{
		base.OnMouseUp(e);
		if (e.Button == .Left && mDragTarget != .None)
		{
			mDragTarget = .None;
			Context?.FocusManager?.ReleaseCapture();
			e.Handled = true;
		}
	}

	private void UpdateSV(float x, float y)
	{
		mSaturation = Math.Clamp(x / SVSize, 0, 1);
		mValue = Math.Clamp(1 - y / SVSize, 0, 1);
		EmitColorChanged();
	}

	private void UpdateHue(float y)
	{
		mHue = Math.Clamp(y / SVSize * 360, 0, 360);
		EmitColorChanged();
	}

	private void EmitColorChanged()
	{
		let rgb = HsvToRgb(mHue, mSaturation, mValue);
		mColorChanged.[Friend]Invoke(rgb);
	}

	// === HSV ↔ RGB Conversion ===

	public static Vector3 HsvToRgb(float h, float s, float v)
	{
		if (s <= 0)
			return .(v, v, v);

		var hh = h;
		if (hh >= 360) hh = 0;
		hh /= 60;
		let i = (int)hh;
		let ff = hh - i;
		let p = v * (1 - s);
		let q = v * (1 - s * ff);
		let t = v * (1 - s * (1 - ff));

		switch (i)
		{
		case 0: return .(v, t, p);
		case 1: return .(q, v, p);
		case 2: return .(p, v, t);
		case 3: return .(p, q, v);
		case 4: return .(t, p, v);
		default: return .(v, p, q);
		}
	}

	public static void RgbToHsv(Vector3 rgb, out float h, out float s, out float v)
	{
		let r = rgb.X;
		let g = rgb.Y;
		let b = rgb.Z;
		let max = Math.Max(r, Math.Max(g, b));
		let min = Math.Min(r, Math.Min(g, b));
		let delta = max - min;

		v = max;
		s = (max > 0) ? (delta / max) : 0;

		if (delta <= 0)
		{
			h = 0;
			return;
		}

		if (r >= max)
			h = (g - b) / delta;
		else if (g >= max)
			h = 2 + (b - r) / delta;
		else
			h = 4 + (r - g) / delta;

		h *= 60;
		if (h < 0) h += 360;
	}

	private static Color HsvToColor(float h, float s, float v)
	{
		let rgb = HsvToRgb(h, s, v);
		return Color(rgb.X, rgb.Y, rgb.Z);
	}
}
