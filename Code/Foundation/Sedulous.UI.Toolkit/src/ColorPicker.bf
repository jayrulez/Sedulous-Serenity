namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Interactive color picker with SV square, hue strip, alpha strip,
/// hex input, and R/G/B number fields.
public class ColorPicker : ViewGroup
{
	private float mHue = 0;         // 0-360
	private float mSaturation = 1;  // 0-1
	private float mValue = 1;       // 0-1
	private float mAlpha = 1;       // 0-1
	private Color mOriginalColor;
	private bool mSyncing;

	// Inner views
	private SVSquare mSVSquare;
	private HueStripView mHueStrip;
	private AlphaStripView mAlphaStrip;
	private EditText mHexInput;
	private NumberField mRField;
	private NumberField mGField;
	private NumberField mBField;
	private Panel mPreviewCurrent;
	private Panel mPreviewOriginal;

	// Layout constants
	private float mSquareSize = 180;
	private float mStripWidth = 20;
	private float mGap = 8;

	private EventAccessor<delegate void(ColorPicker, Color)> mOnColorChanged = new .() ~ delete _;

	/// Fired when the color changes.
	public EventAccessor<delegate void(ColorPicker, Color)> OnColorChanged => mOnColorChanged;

	/// Get or set the current color.
	public Color CurrentColor
	{
		get => HSVToRGB(mHue, mSaturation, mValue, mAlpha);
		set { SetColor(value); }
	}

	public this()
	{
		MinWidth = 360;
		MinHeight = 200;

		// SV Square
		mSVSquare = new SVSquare(this);
		AddView(mSVSquare);

		// Hue strip
		mHueStrip = new HueStripView(this);
		AddView(mHueStrip);

		// Alpha strip
		mAlphaStrip = new AlphaStripView(this);
		AddView(mAlphaStrip);

		// Preview panels
		mPreviewCurrent = new Panel();
		mPreviewCurrent.CornerRadius = 4;
		mPreviewCurrent.BorderWidth = 1;
		AddView(mPreviewCurrent);

		mPreviewOriginal = new Panel();
		mPreviewOriginal.CornerRadius = 4;
		mPreviewOriginal.BorderWidth = 1;
		AddView(mPreviewOriginal);

		// Hex input
		mHexInput = new EditText("Hex");
		mHexInput.MaxLength = 9;
		mHexInput.OnSubmit.Subscribe(new => OnHexSubmit);
		AddView(mHexInput);

		// RGB number fields
		mRField = new NumberField(255, 0, 255);
		mRField.DecimalPlaces = 0;
		mRField.Step = 1;
		mRField.OnValueChanged.Subscribe(new => OnRGBFieldChanged);
		AddView(mRField);

		mGField = new NumberField(255, 0, 255);
		mGField.DecimalPlaces = 0;
		mGField.Step = 1;
		mGField.OnValueChanged.Subscribe(new => OnRGBFieldChanged);
		AddView(mGField);

		mBField = new NumberField(255, 0, 255);
		mBField.DecimalPlaces = 0;
		mBField.Step = 1;
		mBField.OnValueChanged.Subscribe(new => OnRGBFieldChanged);
		AddView(mBField);

		mOriginalColor = CurrentColor;
		SyncFromHSV();
	}

	/// Set the current color and update all sub-views.
	public void SetColor(Color color)
	{
		if (mSyncing) return;
		mSyncing = true;

		float r = color.R / 255.0f;
		float g = color.G / 255.0f;
		float b = color.B / 255.0f;
		mAlpha = color.A / 255.0f;

		RGBToHSV(r, g, b, ref mHue, ref mSaturation, ref mValue);

		SyncViewsFromHSV();
		mSyncing = false;
	}

	/// Set the original color (shown in the "original" preview swatch).
	public void SetOriginalColor(Color color)
	{
		mOriginalColor = color;
		mPreviewOriginal.FillColor = color;
	}

	private void SyncFromHSV()
	{
		if (mSyncing) return;
		mSyncing = true;
		SyncViewsFromHSV();
		mOnColorChanged.[Friend]Invoke(this, CurrentColor);
		mSyncing = false;
	}

	private void SyncViewsFromHSV()
	{
		let color = HSVToRGB(mHue, mSaturation, mValue, mAlpha);

		// Update RGB fields
		mRField.Value = color.R;
		mGField.Value = color.G;
		mBField.Value = color.B;

		// Update hex
		let hex = scope String();
		hex.AppendF("#{0:X2}{1:X2}{2:X2}", (int)color.R, (int)color.G, (int)color.B);
		mHexInput.Text = hex;

		// Update preview
		mPreviewCurrent.FillColor = color;

		// Invalidate visual strips
		mSVSquare.Invalidate();
		mHueStrip.Invalidate();
		mAlphaStrip.Invalidate();
	}

	private void SyncFromRGB()
	{
		if (mSyncing) return;
		mSyncing = true;

		float r = mRField.Value / 255.0f;
		float g = mGField.Value / 255.0f;
		float b = mBField.Value / 255.0f;

		RGBToHSV(r, g, b, ref mHue, ref mSaturation, ref mValue);

		SyncViewsFromHSV();
		mOnColorChanged.[Friend]Invoke(this, CurrentColor);
		mSyncing = false;
	}

	private void OnRGBFieldChanged(NumberField nf, float val)
	{
		SyncFromRGB();
	}

	private void OnHexSubmit(EditText edit)
	{
		if (mSyncing) return;

		let text = scope String(edit.Text);
		if (text.StartsWith('#'))
			text.Remove(0, 1);

		if (text.Length == 6)
		{
			uint32 hexVal = 0;
			if (uint32.Parse(text, .HexNumber) case .Ok(let v))
			{
				hexVal = v;
				float r = ((hexVal >> 16) & 0xFF) / 255.0f;
				float g = ((hexVal >> 8) & 0xFF) / 255.0f;
				float b = (hexVal & 0xFF) / 255.0f;

				mSyncing = true;
				RGBToHSV(r, g, b, ref mHue, ref mSaturation, ref mValue);
				SyncViewsFromHSV();
				mOnColorChanged.[Friend]Invoke(this, CurrentColor);
				mSyncing = false;
			}
		}
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		// Layout: [SV square] [gap] [Hue strip] [gap] [Alpha strip] [gap] [inputs column]
		float inputsW = 80;
		float totalW = mSquareSize + mGap + mStripWidth + mGap + mStripWidth + mGap + inputsW;
		float totalH = mSquareSize;

		SetMeasuredDimension(
			widthSpec.Resolve(totalW, MinWidth, MaxWidth),
			heightSpec.Resolve(totalH, MinHeight, MaxHeight)
		);
	}

	protected override void OnLayout(float width, float height)
	{
		float sqSize = Math.Min(mSquareSize, height);
		float x = 0;

		// SV Square
		mSVSquare.Layout(x, 0, sqSize, sqSize);
		x += sqSize + mGap;

		// Hue strip
		mHueStrip.Layout(x, 0, mStripWidth, sqSize);
		x += mStripWidth + mGap;

		// Alpha strip
		mAlphaStrip.Layout(x, 0, mStripWidth, sqSize);
		x += mStripWidth + mGap;

		// Input column
		float inputW = Math.Max(width - x, 70);
		float inputH = 24;
		float y = 0;

		// Current / Original preview
		float previewH = 30;
		float halfW = (inputW - 4) * 0.5f;
		mPreviewCurrent.Layout(x, y, halfW, previewH);
		mPreviewOriginal.Layout(x + halfW + 4, y, halfW, previewH);
		y += previewH + 8;

		// Hex input
		mHexInput.Layout(x, y, inputW, inputH);
		y += inputH + 6;

		// R/G/B fields
		mRField.Layout(x, y, inputW, inputH);
		y += inputH + 4;
		mGField.Layout(x, y, inputW, inputH);
		y += inputH + 4;
		mBField.Layout(x, y, inputW, inputH);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		let bgColor = theme?.GetColor("ColorPicker", "background") ?? palette.Surface;
		ctx.FillRoundedRect(.(0, 0, Width, Height), 4, bgColor);

		// Draw all children
		for (let child in GetChildren())
		{
			if (child.Visibility != .Gone)
				child.Draw(ctx);
		}
	}

	// ===== HSV Helpers =====

	public static Color HSVToRGB(float h, float s, float v, float a = 1.0f)
	{
		float c = v * s;
		float hPrime = h / 60.0f;
		float x = c * (1.0f - Math.Abs(hPrime % 2.0f - 1.0f));
		float m = v - c;

		float r1 = 0, g1 = 0, b1 = 0;

		if (hPrime < 1) { r1 = c; g1 = x; b1 = 0; }
		else if (hPrime < 2) { r1 = x; g1 = c; b1 = 0; }
		else if (hPrime < 3) { r1 = 0; g1 = c; b1 = x; }
		else if (hPrime < 4) { r1 = 0; g1 = x; b1 = c; }
		else if (hPrime < 5) { r1 = x; g1 = 0; b1 = c; }
		else { r1 = c; g1 = 0; b1 = x; }

		return Color(r1 + m, g1 + m, b1 + m, a);
	}

	public static void RGBToHSV(float r, float g, float b, ref float h, ref float s, ref float v)
	{
		float cMax = Math.Max(r, Math.Max(g, b));
		float cMin = Math.Min(r, Math.Min(g, b));
		float delta = cMax - cMin;

		v = cMax;
		s = (cMax == 0) ? 0 : delta / cMax;

		if (delta == 0)
			h = 0;
		else if (cMax == r)
			h = 60.0f * (((g - b) / delta) % 6.0f);
		else if (cMax == g)
			h = 60.0f * (((b - r) / delta) + 2.0f);
		else
			h = 60.0f * (((r - g) / delta) + 4.0f);

		if (h < 0) h += 360.0f;
	}

	// ===== Inner Views =====

	/// Saturation/Value square: S on X, V on Y (inverted: top=1, bottom=0).
	private class SVSquare : View
	{
		private ColorPicker mPicker;
		private bool mDragging;

		public this(ColorPicker picker) { mPicker = picker; }

		protected override void OnDraw(DrawContext ctx)
		{
			int steps = 30;
			float cellW = Width / steps;
			float cellH = Height / steps;

			for (int iy = 0; iy < steps; iy++)
			{
				float v = 1.0f - (float)iy / (steps - 1);
				for (int ix = 0; ix < steps; ix++)
				{
					float s = (float)ix / (steps - 1);
					let color = HSVToRGB(mPicker.mHue, s, v);
					ctx.FillRect(.(ix * cellW, iy * cellH, cellW + 1, cellH + 1), color);
				}
			}

			// Circle indicator
			float cx = mPicker.mSaturation * Width;
			float cy = (1.0f - mPicker.mValue) * Height;
			let indicatorColor = (mPicker.mValue > 0.5f) ? Color(0, 0, 0, 1.0f) : Color(1.0f, 1.0f, 1.0f, 1.0f);
			ctx.DrawBorderRect(.(cx - 5, cy - 5, 10, 10), indicatorColor, 2);

			// Border
			let border = mPicker.Context?.Theme?.GetColor("ColorPicker", "border") ?? Color(0.3f, 0.3f, 0.3f, 1.0f);
			ctx.DrawBorderRect(.(0, 0, Width, Height), border, 1);
		}

		public override void OnMouseDown(MouseButtonEventArgs e)
		{
			if (e.Button != .Left) return;
			mDragging = true;
			Context?.FocusManager.SetCapture(this);
			UpdateFromMouse(e.LocalX, e.LocalY);
			e.Handled = true;
		}

		public override void OnMouseMove(MouseEventArgs e)
		{
			if (mDragging)
				UpdateFromMouse(e.LocalX, e.LocalY);
		}

		public override void OnMouseUp(MouseButtonEventArgs e)
		{
			if (mDragging && e.Button == .Left)
			{
				mDragging = false;
				Context?.FocusManager.ReleaseCapture();
				e.Handled = true;
			}
		}

		private void UpdateFromMouse(float x, float y)
		{
			mPicker.mSaturation = Math.Clamp(x / Width, 0, 1);
			mPicker.mValue = Math.Clamp(1.0f - y / Height, 0, 1);
			mPicker.SyncFromHSV();
		}
	}

	/// Vertical hue rainbow strip.
	private class HueStripView : View
	{
		private ColorPicker mPicker;
		private bool mDragging;

		public this(ColorPicker picker) { mPicker = picker; }

		protected override void OnDraw(DrawContext ctx)
		{
			int steps = 36;
			float cellH = Height / steps;

			for (int i = 0; i < steps; i++)
			{
				float hue = (float)i / (steps - 1) * 360.0f;
				let color = HSVToRGB(hue, 1, 1);
				ctx.FillRect(.(0, i * cellH, Width, cellH + 1), color);
			}

			// Line indicator
			float iy = (mPicker.mHue / 360.0f) * Height;
			ctx.FillRect(.(0, iy - 1, Width, 3), Color(1.0f, 1.0f, 1.0f, 0.9f));
			ctx.DrawBorderRect(.(0, iy - 1, Width, 3), Color(0, 0, 0, 0.5f), 1);

			// Border
			let border = mPicker.Context?.Theme?.GetColor("ColorPicker", "border") ?? Color(0.3f, 0.3f, 0.3f, 1.0f);
			ctx.DrawBorderRect(.(0, 0, Width, Height), border, 1);
		}

		public override void OnMouseDown(MouseButtonEventArgs e)
		{
			if (e.Button != .Left) return;
			mDragging = true;
			Context?.FocusManager.SetCapture(this);
			UpdateFromMouse(e.LocalY);
			e.Handled = true;
		}

		public override void OnMouseMove(MouseEventArgs e)
		{
			if (mDragging)
				UpdateFromMouse(e.LocalY);
		}

		public override void OnMouseUp(MouseButtonEventArgs e)
		{
			if (mDragging && e.Button == .Left)
			{
				mDragging = false;
				Context?.FocusManager.ReleaseCapture();
				e.Handled = true;
			}
		}

		private void UpdateFromMouse(float y)
		{
			mPicker.mHue = Math.Clamp(y / Height, 0, 1) * 360.0f;
			mPicker.SyncFromHSV();
		}
	}

	/// Vertical alpha strip with checkerboard background.
	private class AlphaStripView : View
	{
		private ColorPicker mPicker;
		private bool mDragging;

		public this(ColorPicker picker) { mPicker = picker; }

		protected override void OnDraw(DrawContext ctx)
		{
			// Checkerboard background
			float checkSize = 5;
			Color light = Color(0.8f, 0.8f, 0.8f, 1.0f);
			Color dark2 = Color(0.5f, 0.5f, 0.5f, 1.0f);

			int cols = (int)Math.Ceiling(Width / checkSize);
			int rows = (int)Math.Ceiling(Height / checkSize);
			for (int ry = 0; ry < rows; ry++)
			{
				for (int cx2 = 0; cx2 < cols; cx2++)
				{
					let c = ((ry + cx2) % 2 == 0) ? light : dark2;
					ctx.FillRect(.(cx2 * checkSize, ry * checkSize,
						Math.Min(checkSize, Width - cx2 * checkSize),
						Math.Min(checkSize, Height - ry * checkSize)), c);
				}
			}

			// Color gradient from opaque (top) to transparent (bottom)
			let baseColor = HSVToRGB(mPicker.mHue, mPicker.mSaturation, mPicker.mValue);
			int steps = 20;
			float cellH = Height / steps;
			for (int i = 0; i < steps; i++)
			{
				float alpha = 1.0f - (float)i / (steps - 1);
				let c = Color(baseColor.R / 255.0f, baseColor.G / 255.0f, baseColor.B / 255.0f, alpha);
				ctx.FillRect(.(0, i * cellH, Width, cellH + 1), c);
			}

			// Line indicator
			float iy = (1.0f - mPicker.mAlpha) * Height;
			ctx.FillRect(.(0, iy - 1, Width, 3), Color(1.0f, 1.0f, 1.0f, 0.9f));
			ctx.DrawBorderRect(.(0, iy - 1, Width, 3), Color(0, 0, 0, 0.5f), 1);

			// Border
			let border = mPicker.Context?.Theme?.GetColor("ColorPicker", "border") ?? Color(0.3f, 0.3f, 0.3f, 1.0f);
			ctx.DrawBorderRect(.(0, 0, Width, Height), border, 1);
		}

		public override void OnMouseDown(MouseButtonEventArgs e)
		{
			if (e.Button != .Left) return;
			mDragging = true;
			Context?.FocusManager.SetCapture(this);
			UpdateFromMouse(e.LocalY);
			e.Handled = true;
		}

		public override void OnMouseMove(MouseEventArgs e)
		{
			if (mDragging)
				UpdateFromMouse(e.LocalY);
		}

		public override void OnMouseUp(MouseButtonEventArgs e)
		{
			if (mDragging && e.Button == .Left)
			{
				mDragging = false;
				Context?.FocusManager.ReleaseCapture();
				e.Handled = true;
			}
		}

		private void UpdateFromMouse(float y)
		{
			mPicker.mAlpha = Math.Clamp(1.0f - y / Height, 0, 1);
			mPicker.SyncFromHSV();
		}
	}
}
