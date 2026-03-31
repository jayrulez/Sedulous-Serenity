namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Fonts;
using Sedulous.Core;

/// Interactive clickable button with text.
public class Button : View
{
	private String mText = new .() ~ delete _;
	private float mFontSize = 16;
	private Color mTextColor = default;

	private EventAccessor<delegate void(Button)> mOnClick = new .() ~ delete _;
	private ICommand mCommand;
	private delegate void() mCanExecuteChangedHandler /*~ delete _*/;

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

	/// Subscribe to click events.
	public EventAccessor<delegate void(Button)> OnClick => mOnClick;

	/// Optional command executed on click. Button auto-disables when CanExecute returns false.
	public ICommand Command
	{
		get => mCommand;
		set
		{
			if (mCommand != null && mCanExecuteChangedHandler != null)
				mCommand.OnCanExecuteChanged.Unsubscribe(mCanExecuteChangedHandler, false);

			mCommand = value;

			if (mCommand != null)
			{
				if (mCanExecuteChangedHandler == null)
					mCanExecuteChangedHandler = new () => { UpdateCommandEnabled(); };
				mCommand.OnCanExecuteChanged.Subscribe(mCanExecuteChangedHandler);
				UpdateCommandEnabled();
			}
		}
	}

	private void UpdateCommandEnabled()
	{
		if (mCommand != null)
			Enabled = mCommand.CanExecute();
	}

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

	public override float GetBaseline()
	{
		if (Context == null || Context.FontService == null)
			return -1;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null)
			return -1;

		// Text is centered vertically in content bounds
		float contentH = Height - Padding.Vertical;
		float lineH = font.Font.Metrics.LineHeight;
		float baseline = Padding.Top + (contentH - lineH) * 0.5f + font.Font.Metrics.Ascent;
		Context.FontService.ReleaseFont(font);
		return baseline;
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
			desiredH += mFontSize; // approximate
		}

		// Respect background drawable's intrinsic size (like Android)
		let theme = Context?.Theme;
		let bgDrawable = theme?.GetDrawable("Button", "background");
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

		// Try theme drawable first
		let bgDrawable = theme?.GetDrawable("Button", "background");
		if (bgDrawable != null)
		{
			bgDrawable.Draw(ctx, .(0, 0, Width, Height), GetControlState());
		}
		else
		{
			let baseColor = theme?.GetColor("Button", "background") ?? palette.Primary;
			let cornerRadius = theme?.GetDimension("Button", "cornerRadius") ?? 4;
			let bg = Palette.ResolveState(baseColor, GetControlState(), palette.Accent);
			ctx.FillRoundedRect(.(0, 0, Width, Height), cornerRadius, bg);
		}

		if (IsFocused)
		{
			let cornerRadius = theme?.GetDimension("Button", "cornerRadius") ?? 4;
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
					let baseTextColor = (mTextColor.A > 0) ? mTextColor : (theme?.GetColor("Button", "text") ?? palette.Text);
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

		// Fire click if mouse is still within bounds
		if (e.LocalX >= 0 && e.LocalY >= 0 && e.LocalX <= Width && e.LocalY <= Height)
		{
			if (mCommand != null && mCommand.CanExecute())
				mCommand.Execute();
			mOnClick.[Friend]Invoke(this);
		}

		e.Handled = true;
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled)
			return;

		// Space or Enter triggers click
		if (e.Key == .Space || e.Key == .Return)
		{
			if (mCommand != null && mCommand.CanExecute())
				mCommand.Execute();
			mOnClick.[Friend]Invoke(this);
			e.Handled = true;
		}
	}
}
