namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Fonts;
using Sedulous.Core;

/// Collapsible content panel with a clickable header.
/// Click the header to toggle expanded/collapsed state.
public class Expander : ViewGroup
{
	private String mHeaderText = new .("Expander") ~ delete _;
	private View mContentView;
	private bool mIsExpanded = true;
	private float mHeaderHeight = 28;
	private float mFontSize = 14;

	private EventAccessor<delegate void(Expander, bool)> mOnExpandedChanged = new .() ~ delete _;

	public bool IsExpanded
	{
		get => mIsExpanded;
		set
		{
			if (mIsExpanded != value)
			{
				mIsExpanded = value;
				if (mContentView != null)
					mContentView.Visibility = mIsExpanded ? .Visible : .Gone;
				InvalidateLayout();
				mOnExpandedChanged.[Friend]Invoke(this, value);
			}
		}
	}

	public StringView HeaderText
	{
		get => mHeaderText;
		set
		{
			mHeaderText.Set(value);
			Invalidate();
		}
	}

	public float HeaderHeight
	{
		get => mHeaderHeight;
		set { mHeaderHeight = Math.Max(16, value); InvalidateLayout(); }
	}

	public float FontSize
	{
		get => mFontSize;
		set { mFontSize = Math.Max(1, value); InvalidateLayout(); }
	}

	/// Subscribe to expanded state change events.
	public EventAccessor<delegate void(Expander, bool)> OnExpandedChanged => mOnExpandedChanged;

	public this()
	{
		Focusable = true;
		CursorType = .Pointer;
	}

	public this(StringView headerText) : this()
	{
		mHeaderText.Set(headerText);
	}

	/// Set the content view. Only one content view is supported.
	public void SetContent(View content)
	{
		if (mContentView != null)
			RemoveView(mContentView);

		mContentView = content;
		if (content != null)
		{
			content.Visibility = mIsExpanded ? .Visible : .Gone;
			AddView(content);
		}
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		// Expander fills available width — use spec size when constrained.
		float w = (widthSpec.SpecMode != .Unspecified) ? widthSpec.Size : 200;
		if (MinWidth > 0) w = Math.Max(w, MinWidth);
		if (MaxWidth > 0) w = Math.Min(w, MaxWidth);

		float h = mHeaderHeight;

		if (mIsExpanded && mContentView != null && mContentView.Visibility != .Gone)
		{
			// Build a child height spec that subtracts the header from available space
			MeasureSpec contentHeightSpec;
			if (heightSpec.SpecMode == .Exactly || heightSpec.SpecMode == .AtMost)
				contentHeightSpec = MeasureSpec.MakeAtMost(Math.Max(0, heightSpec.Size - mHeaderHeight));
			else
				contentHeightSpec = MeasureSpec.MakeUnspecified();

			mContentView.Measure(MeasureSpec.MakeExactly(w), contentHeightSpec);
			h += mContentView.MeasuredHeight;
		}

		SetMeasuredDimension(w, heightSpec.Resolve(h, MinHeight, MaxHeight));
	}

	protected override void OnLayout(float width, float height)
	{
		if (mIsExpanded && mContentView != null && mContentView.Visibility != .Gone)
		{
			float contentHeight = height - mHeaderHeight;
			if (contentHeight < 0) contentHeight = 0;
			mContentView.Layout(0, mHeaderHeight, width, contentHeight);
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Header background
		let headerBg = IsHovered
			? (theme?.GetColor("Expander", "headerHoverBackground") ?? Palette.Darken(palette.Surface, 0.05f))
			: (theme?.GetColor("Expander", "headerBackground") ?? Palette.Darken(palette.Surface, 0.1f));
		ctx.FillRoundedRect(.(0, 0, Width, mHeaderHeight), 3, headerBg);

		// Indicator — prefer drawable icons, fall back to text
		let indicatorKey = mIsExpanded ? "expandedIcon" : "collapsedIcon";
		let indicatorDrawable = theme?.GetDrawable("Expander", indicatorKey);
		float textStartX = 8;

		if (indicatorDrawable != null)
		{
			let iconSize = indicatorDrawable.IntrinsicSize;
			float iconW = (iconSize.Width > 0) ? iconSize.Width : 10;
			float iconH = (iconSize.Height > 0) ? iconSize.Height : 10;
			float iconX = 6;
			float iconY = (mHeaderHeight - iconH) * 0.5f;
			indicatorDrawable.Draw(ctx, .(iconX, iconY, iconW, iconH));
			textStartX = iconX + iconW + 4;
		}
		else if (Context != null && Context.FontService != null)
		{
			let indicatorColor = theme?.GetColor("Expander", "indicator") ?? palette.Accent;
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let indicator = mIsExpanded ? "v " : "> ";
					ctx.DrawText(indicator, font.Font, font.Atlas, atlasTexture,
						.(8, 0, 20, mHeaderHeight), .Left, .Middle, indicatorColor);
				}
				Context.FontService.ReleaseFont(font);
			}
			textStartX = 24;
		}

		// Header text
		if (Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let textColor = theme?.GetColor("Expander", "headerText") ?? palette.Text;
					ctx.DrawText(mHeaderText, font.Font, font.Atlas, atlasTexture,
						.(textStartX, 0, Width - textStartX - 8, mHeaderHeight), .Left, .Middle, textColor);
				}
				Context.FontService.ReleaseFont(font);
			}
		}

		// Focus indicator
		if (IsFocused)
			DrawFocusIndicator(ctx, .(0, 0, Width, mHeaderHeight), 3);

		// Content background
		if (mIsExpanded && mContentView != null && mContentView.Visibility != .Gone)
		{
			let contentBg = theme?.GetColor("Expander", "contentBackground") ?? palette.Surface;
			ctx.FillRect(.(0, mHeaderHeight, Width, Height - mHeaderHeight), contentBg);

			// Draw content child
			mContentView.Draw(ctx);
		}
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		// Click in header area toggles expansion
		if (e.LocalY >= 0 && e.LocalY <= mHeaderHeight)
		{
			IsExpanded = !mIsExpanded;
			e.Handled = true;
		}
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled)
			return;

		if (e.Key == .Space || e.Key == .Return)
		{
			IsExpanded = !mIsExpanded;
			e.Handled = true;
		}
	}
}
