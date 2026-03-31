namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Fonts;
using Sedulous.Core;

/// Radio button with circle indicator and text label.
/// Use inside a RadioGroup for mutual exclusion.
public class RadioButton : View
{
	private String mText = new .() ~ delete _;
	private float mFontSize = 16;
	private Color mTextColor = default;
	private bool mIsChecked;

	private EventAccessor<delegate void(RadioButton, bool)> mOnCheckedChanged = new .() ~ delete _;

	// Visual constants
	private const float CircleRadius = 8;
	private const float CircleDiameter = CircleRadius * 2;
	private const float CircleTextSpacing = 8;

	/// Effective indicator size: uses drawable's intrinsic size when available.
	private float GetIndicatorSize()
	{
		let theme = Context?.Theme;
		if (theme != null)
		{
			let drawable = theme.GetDrawable("RadioButton", "unchecked");
			if (drawable != null)
			{
				let sz = drawable.IntrinsicSize;
				if (sz.Width > 0 && sz.Height > 0)
					return Math.Max(sz.Width, sz.Height);
			}
		}
		return CircleDiameter;
	}

	public bool IsChecked
	{
		get => mIsChecked;
		set
		{
			if (mIsChecked != value)
			{
				mIsChecked = value;
				Invalidate();
				mOnCheckedChanged.[Friend]Invoke(this, value);
			}
		}
	}

	public StringView Text
	{
		get => mText;
		set
		{
			mText.Set(value);
			InvalidateLayout();
		}
	}

	public float FontSize
	{
		get => mFontSize;
		set
		{
			mFontSize = Math.Max(1, value);
			InvalidateLayout();
		}
	}

	public Color TextColor
	{
		get => mTextColor;
		set { mTextColor = value; Invalidate(); }
	}

	/// Subscribe to checked state change events.
	public EventAccessor<delegate void(RadioButton, bool)> OnCheckedChanged => mOnCheckedChanged;

	public this()
	{
		Focusable = true;
		CursorType = .Pointer;
		Padding = .(4, 4, 4, 4);
	}

	public this(StringView text) : this()
	{
		mText.Set(text);
	}

	public override float GetBaseline()
	{
		if (Context == null || Context.FontService == null)
			return -1;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null)
			return -1;

		// Text is drawn with .Middle vertical alignment in content bounds
		float contentH = Height - Padding.Vertical;
		float lineH = font.Font.Metrics.LineHeight;
		float baseline = Padding.Top + (contentH - lineH) * 0.5f + font.Font.Metrics.Ascent;
		Context.FontService.ReleaseFont(font);
		return baseline;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float textW = 0;
		float textH = mFontSize;

		if (!mText.IsEmpty && Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				textW = font.Font.MeasureString(mText);
				textH = font.Font.Metrics.LineHeight;
				Context.FontService.ReleaseFont(font);
			}
		}

		float indicatorSize = GetIndicatorSize();
		float desiredW = Padding.Horizontal + indicatorSize + (mText.IsEmpty ? 0 : CircleTextSpacing + textW);
		float desiredH = Padding.Vertical + Math.Max(indicatorSize, textH);

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;
		let content = ContentBounds;
		float contentH = content.Height;
		float indicatorSize = GetIndicatorSize();
		float indicatorRadius = indicatorSize * 0.5f;

		float centerY = content.Y + contentH * 0.5f;
		float centerX = content.X + indicatorRadius;

		// Try theme drawable first (e.g. Kenney sprite-based indicators)
		let indicatorKey = mIsChecked ? "checked" : "unchecked";
		let indicatorDrawable = theme?.GetDrawable("RadioButton", indicatorKey);
		if (indicatorDrawable != null)
		{
			indicatorDrawable.Draw(ctx, .(content.X, centerY - indicatorRadius, indicatorSize, indicatorSize), GetControlState());
		}
		else
		{
			let circleBg = theme?.GetColor("RadioButton", "circleBackground") ?? .(0.15f, 0.15f, 0.2f, 1.0f);
			let circleBorder = theme?.GetColor("RadioButton", "circleBorder") ?? palette.Border;
			let dotColor = theme?.GetColor("RadioButton", "dotColor") ?? palette.Accent;

			Color borderColor = IsHovered && Enabled ? Palette.Lighten(circleBorder, 0.3f) : circleBorder;
			ctx.FillCircle(.(centerX, centerY), indicatorRadius, circleBg);
			ctx.DrawCircle(.(centerX, centerY), indicatorRadius, borderColor, 1.5f);

			if (mIsChecked)
			{
				let dc = Enabled ? dotColor : Palette.ComputeDisabled(dotColor);
				ctx.FillCircle(.(centerX, centerY), indicatorRadius - 4, dc);
			}
		}

		if (IsFocused && indicatorDrawable == null)
			ctx.DrawCircle(.(centerX, centerY), indicatorRadius + 3, GetFocusBorderColor(), 2);

		if (!mText.IsEmpty && Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let textX = content.X + indicatorSize + CircleTextSpacing;
					let textBounds = RectangleF(textX, content.Y, content.Width - indicatorSize - CircleTextSpacing, contentH);
					let baseTextColor = (mTextColor.A > 0) ? mTextColor : (theme?.GetColor("RadioButton", "text") ?? palette.Text);
				let textColor = Enabled ? baseTextColor : Palette.ComputeDisabled(baseTextColor);
					ctx.DrawText(mText, font.Font, font.Atlas, atlasTexture, textBounds, .Left, .Middle, textColor);
				}
				Context.FontService.ReleaseFont(font);
			}
		}
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		// Radio buttons can only be checked, not unchecked by direct click
		if (!mIsChecked)
			IsChecked = true;

		e.Handled = true;
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled)
			return;

		if (e.Key == .Space || e.Key == .Return)
		{
			if (!mIsChecked)
				IsChecked = true;
			e.Handled = true;
		}
	}
}
