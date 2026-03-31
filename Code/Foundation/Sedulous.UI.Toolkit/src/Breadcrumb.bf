namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Breadcrumb navigation control showing clickable path segments with separators.
/// Click a segment to navigate back to that level (truncating segments after it).
public class Breadcrumb : View
{
	private List<String> mSegments = new .() ~ { for (var s in _) delete s; delete _; };
	private String mSeparator = new .(" > ") ~ delete _;
	private int mHoveredIndex = -1;
	private List<RectangleF> mSegmentRects = new .() ~ delete _;
	private float mFontSize = 14;
	private float mSegmentPadding = 6;
	private float mSeparatorPadding = 4;

	private EventAccessor<delegate void(Breadcrumb, int)> mOnNavigate = new .() ~ delete _;

	/// Fired when a segment is clicked. The int parameter is the segment index navigated to.
	public EventAccessor<delegate void(Breadcrumb, int)> OnNavigate => mOnNavigate;

	public float FontSize
	{
		get => mFontSize;
		set { mFontSize = Math.Max(1, value); InvalidateLayout(); }
	}

	public int SegmentCount => mSegments.Count;

	public this()
	{
		MinHeight = 24;
	}

	/// Replace all segments with the given path.
	public void SetPath(Span<StringView> segments)
	{
		ClearInternal();
		for (let seg in segments)
			mSegments.Add(new String(seg));
		InvalidateLayout();
	}

	/// Append a new segment to the end.
	public void PushSegment(StringView segment)
	{
		mSegments.Add(new String(segment));
		InvalidateLayout();
	}

	/// Remove the last segment.
	public void PopSegment()
	{
		if (mSegments.Count > 0)
		{
			let last = mSegments[mSegments.Count - 1];
			mSegments.RemoveAt(mSegments.Count - 1);
			delete last;
			InvalidateLayout();
		}
	}

	/// Navigate to the given level: removes all segments after it and fires OnNavigate.
	public void NavigateTo(int level)
	{
		if (level < 0 || level >= mSegments.Count)
			return;

		while (mSegments.Count > level + 1)
		{
			let last = mSegments[mSegments.Count - 1];
			mSegments.RemoveAt(mSegments.Count - 1);
			delete last;
		}

		mOnNavigate.[Friend]Invoke(this, level);
		InvalidateLayout();
	}

	/// Remove all segments.
	public void Clear()
	{
		ClearInternal();
		InvalidateLayout();
	}

	/// Get the text of a segment at the given index.
	public StringView GetSegment(int index)
	{
		if (index >= 0 && index < mSegments.Count)
			return mSegments[index];
		return "";
	}

	private void ClearInternal()
	{
		for (var s in mSegments)
			delete s;
		mSegments.Clear();
		mHoveredIndex = -1;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		// Estimate width from character count and font size
		float estimatedWidth = 0;
		float charWidth = mFontSize * 0.6f;

		for (int i = 0; i < mSegments.Count; i++)
		{
			estimatedWidth += mSegments[i].Length * charWidth + mSegmentPadding * 2;
			if (i < mSegments.Count - 1)
				estimatedWidth += mSeparator.Length * charWidth + mSeparatorPadding * 2;
		}

		SetMeasuredDimension(
			widthSpec.Resolve(Math.Max(estimatedWidth, 40), MinWidth, MaxWidth),
			heightSpec.Resolve(Math.Max(mFontSize + 8, MinHeight), MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Background
		let bgColor = theme?.GetColor("Breadcrumb", "background") ?? Color(0, 0, 0, 0);
		if (bgColor.A > 0)
			ctx.FillRect(.(0, 0, Width, Height), bgColor);

		mSegmentRects.Clear();

		if (mSegments.Count == 0 || Context?.FontService == null)
			return;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null) return;

		let atlasTexture = Context.FontService.GetAtlasTexture(font);
		if (atlasTexture == null) { Context.FontService.ReleaseFont(font); return; }

		let textColor = theme?.GetColor("Breadcrumb", "text") ?? palette.Text;
		let hoverText = theme?.GetColor("Breadcrumb", "hoverText") ?? palette.Accent;
		let sepColor = theme?.GetColor("Breadcrumb", "separator") ?? Palette.WithAlpha(palette.Text, 128);
		let hoverBg = theme?.GetColor("Breadcrumb", "hoverBackground") ?? Palette.WithAlpha(palette.Accent, 30);

		float x = mSegmentPadding;

		for (int i = 0; i < mSegments.Count; i++)
		{
			let seg = mSegments[i];
			float textW = font.Font.MeasureString(seg);
			float segW = textW + mSegmentPadding * 2;
			let segRect = RectangleF(x - mSegmentPadding, 0, segW, Height);
			mSegmentRects.Add(segRect);

			// Hover background highlight
			if (i == mHoveredIndex)
				ctx.FillRoundedRect(segRect, 3, hoverBg);

			// Segment text
			let color = (i == mHoveredIndex) ? hoverText : textColor;
			ctx.DrawText(seg, font.Font, font.Atlas, atlasTexture,
				.(x, 0, textW, Height), .Left, .Middle, color);

			x += textW + mSegmentPadding;

			// Separator between segments
			if (i < mSegments.Count - 1)
			{
				x += mSeparatorPadding;
				float sepW = font.Font.MeasureString(mSeparator);
				ctx.DrawText(mSeparator, font.Font, font.Atlas, atlasTexture,
					.(x, 0, sepW, Height), .Left, .Middle, sepColor);
				x += sepW + mSeparatorPadding;
			}
		}

		Context.FontService.ReleaseFont(font);
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		int idx = GetSegmentAtPoint(e.LocalX, e.LocalY);
		if (idx >= 0)
		{
			NavigateTo(idx);
			e.Handled = true;
		}
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		int idx = GetSegmentAtPoint(e.LocalX, e.LocalY);
		if (idx != mHoveredIndex)
		{
			mHoveredIndex = idx;
			CursorType = (idx >= 0) ? .Pointer : .Default;
			Invalidate();
		}
	}

	public override void OnMouseLeave(MouseEventArgs e)
	{
		if (mHoveredIndex != -1)
		{
			mHoveredIndex = -1;
			CursorType = .Default;
			Invalidate();
		}
	}

	private int GetSegmentAtPoint(float x, float y)
	{
		for (int i = 0; i < mSegmentRects.Count; i++)
		{
			let r = mSegmentRects[i];
			if (x >= r.X && x < r.X + r.Width && y >= r.Y && y < r.Y + r.Height)
				return i;
		}
		return -1;
	}
}
