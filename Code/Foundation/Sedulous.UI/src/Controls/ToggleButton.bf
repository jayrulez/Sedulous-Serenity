namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Fonts;
using Sedulous.Core;

/// Button with on/off state. Uses accent color when checked.
public class ToggleButton : View
{
	private String mText = new .() ~ delete _;
	private float mFontSize = 16;
	private Color mTextColor = default;
	private bool mIsChecked;

	private EventAccessor<delegate void(ToggleButton, bool)> mOnCheckedChanged = new .() ~ delete _;

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
	public EventAccessor<delegate void(ToggleButton, bool)> OnCheckedChanged => mOnCheckedChanged;

	public this()
	{
		Focusable = true;
		CursorType = .Pointer;
		Padding = .(12, 8, 12, 8);
	}

	public this(StringView text) : this()
	{
		mText.Set(text);
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float desiredW = Padding.Horizontal;
		float desiredH = Padding.Vertical;

		if (!mText.IsEmpty && Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				desiredW += font.Font.MeasureString(mText);
				desiredH += font.Font.Metrics.LineHeight;
				Context.FontService.ReleaseFont(font);
			}
		}
		else
		{
			desiredH += mFontSize;
		}

		// Respect background drawable's intrinsic size (like Android)
		let theme = Context?.Theme;
		let bgDrawable = theme?.GetDrawable("ToggleButton", "background");
		if (bgDrawable != null)
		{
			let intrinsic = bgDrawable.IntrinsicSize;
			if (intrinsic.Height > 0)
				desiredH = Math.Max(desiredH, intrinsic.Height);
		}

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Try theme drawables first (checked/unchecked variants)
		let drawableKey = mIsChecked ? "checkedBackground" : "background";
		let bgDrawable = theme?.GetDrawable("ToggleButton", drawableKey);
		if (bgDrawable != null)
		{
			bgDrawable.Draw(ctx, .(0, 0, Width, Height), GetControlState());
		}
		else
		{
			let cornerRadius = theme?.GetDimension("ToggleButton", "cornerRadius") ?? 4;
			Color baseColor;
			if (mIsChecked)
				baseColor = theme?.GetColor("ToggleButton", "checkedBackground") ?? palette.Accent;
			else
				baseColor = theme?.GetColor("ToggleButton", "background") ?? palette.Primary;
			let bg = Palette.ResolveState(baseColor, GetControlState(), palette.Accent);
			ctx.FillRoundedRect(.(0, 0, Width, Height), cornerRadius, bg);
		}

		if (IsFocused)
		{
			let cornerRadius = theme?.GetDimension("ToggleButton", "cornerRadius") ?? 4;
			DrawFocusIndicator(ctx, .(0, 0, Width, Height), cornerRadius);
		}

		if (!mText.IsEmpty && Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let baseTextColor = (mTextColor.A > 0) ? mTextColor : (theme?.GetColor("ToggleButton", "text") ?? palette.Text);
				let textColor = Enabled ? baseTextColor : Palette.ComputeDisabled(baseTextColor);
					ctx.DrawText(mText, font.Font, font.Atlas, atlasTexture, ContentBounds, .Center, .Middle, textColor);
				}
				Context.FontService.ReleaseFont(font);
			}
		}
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		e.Handled = true;
		Context?.FocusManager.SetCapture(this);
	}

	public override void OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return;

		Context?.FocusManager.ReleaseCapture();

		if (!Enabled)
			return;

		if (e.LocalX >= 0 && e.LocalY >= 0 && e.LocalX <= Width && e.LocalY <= Height)
			IsChecked = !mIsChecked;

		e.Handled = true;
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled)
			return;

		if (e.Key == .Space || e.Key == .Return)
		{
			IsChecked = !mIsChecked;
			e.Handled = true;
		}
	}
}
