namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Fonts;
using Sedulous.Core;

/// Where the tab headers are placed relative to content.
public enum TabPlacement
{
	Top,
	Bottom,
	Left,
	Right
}

/// Tabbed container that displays tab headers and a content area.
/// Only the selected tab's content is visible at any time.
/// Tabs can be placed on any edge via TabPlacement.
public class TabView : ViewGroup
{
	private struct TabItem
	{
		public String Title;
		public View Content;
	}

	private List<TabItem> mTabs = new .() ~ {
		for (var tab in _)
			delete tab.Title;
		delete _;
	};
	private int mSelectedIndex = -1;
	private int mHoveredTabIndex = -1;
	private TabPlacement mTabPlacement = .Top;
	private float mTabHeight = 32;
	private float mFontSize = 14;
	private float mTabPadding = 16;
	private float mMinTabWidth = 50;
	private float mStripPadding = 10; // Padding at start/end of the tab strip (TB: tablayout_x/y padding)
	private float mComputedStripSize; // Cached during measure: width for Left/Right, height for Top/Bottom

	// Cached tab rectangles (in local coords), updated each draw.
	// Used for reliable hit-testing that exactly matches visual positions.
	private List<RectangleF> mTabRects = new .() ~ delete _;

	private EventAccessor<delegate void(TabView, int)> mOnTabChanged = new .() ~ delete _;

	/// Currently selected tab index, or -1 if no tabs.
	public int SelectedIndex
	{
		get => mSelectedIndex;
		set
		{
			var val = value;
			if (val < -1) val = -1;
			if (val >= mTabs.Count) val = mTabs.Count - 1;
			if (mSelectedIndex != val)
			{
				// Hide old
				if (mSelectedIndex >= 0 && mSelectedIndex < mTabs.Count)
					mTabs[mSelectedIndex].Content.Visibility = .Gone;

				mSelectedIndex = val;

				// Show new
				if (mSelectedIndex >= 0 && mSelectedIndex < mTabs.Count)
					mTabs[mSelectedIndex].Content.Visibility = .Visible;

				InvalidateLayout();
				mOnTabChanged.[Friend]Invoke(this, val);
			}
		}
	}

	public int TabCount => mTabs.Count;

	/// Where tab headers are placed (Top, Bottom, Left, Right).
	public TabPlacement Placement
	{
		get => mTabPlacement;
		set { mTabPlacement = value; InvalidateLayout(); }
	}

	/// Height of each tab header (also used as individual tab height for Left/Right placement).
	public float TabHeight
	{
		get => mTabHeight;
		set { mTabHeight = Math.Max(16, value); InvalidateLayout(); }
	}

	public float FontSize
	{
		get => mFontSize;
		set { mFontSize = Math.Max(1, value); InvalidateLayout(); }
	}

	public EventAccessor<delegate void(TabView, int)> OnTabChanged => mOnTabChanged;

	public this()
	{
		Focusable = true;
	}

	/// Add a tab with the given title and content view. Returns the tab index.
	public int AddTab(StringView title, View content)
	{
		TabItem tab;
		tab.Title = new String(title);
		tab.Content = content;

		let index = mTabs.Count;
		mTabs.Add(tab);

		content.Visibility = .Gone;
		AddView(content);

		if (mSelectedIndex == -1)
			SelectedIndex = 0;

		return index;
	}

	/// Remove a tab by index.
	public void RemoveTab(int index)
	{
		if (index < 0 || index >= mTabs.Count)
			return;

		let tab = mTabs[index];
		RemoveView(tab.Content);
		delete tab.Title;
		mTabs.RemoveAt(index);

		if (mSelectedIndex >= mTabs.Count)
			SelectedIndex = mTabs.Count - 1;
		else if (mSelectedIndex == index)
		{
			mSelectedIndex = -1;
			SelectedIndex = Math.Min(index, mTabs.Count - 1);
		}
	}

	private bool IsHorizontalStrip => mTabPlacement == .Top || mTabPlacement == .Bottom;

	/// Compute the tab strip width for Left/Right placement (max text width + padding).
	private float ComputeVerticalStripWidth()
	{
		float maxTextW = 0;
		if (Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				for (let tab in mTabs)
				{
					float tw = font.Font.MeasureString(tab.Title);
					if (tw > maxTextW) maxTextW = tw;
				}
				Context.FontService.ReleaseFont(font);
			}
		}
		return Math.Max(mMinTabWidth, maxTextW + mTabPadding * 2);
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		if (IsHorizontalStrip)
		{
			mComputedStripSize = mTabHeight;
			float w = widthSpec.Resolve(0, MinWidth, MaxWidth);
			float contentH = 0;

			if (mSelectedIndex >= 0 && mSelectedIndex < mTabs.Count)
			{
				let content = mTabs[mSelectedIndex].Content;
				if (content.Visibility != .Gone)
				{
					MeasureSpec contentHeightSpec;
					if (heightSpec.SpecMode == .Exactly)
						contentHeightSpec = MeasureSpec.MakeAtMost(Math.Max(0, heightSpec.Size - mTabHeight));
					else if (heightSpec.SpecMode == .AtMost)
						contentHeightSpec = MeasureSpec.MakeAtMost(Math.Max(0, heightSpec.Size - mTabHeight));
					else
						contentHeightSpec = MeasureSpec.MakeUnspecified();

					content.Measure(MeasureSpec.MakeAtMost(w), contentHeightSpec);
					contentH = content.MeasuredHeight;
				}
			}

			SetMeasuredDimension(
				widthSpec.Resolve(w, MinWidth, MaxWidth),
				heightSpec.Resolve(mTabHeight + contentH, MinHeight, MaxHeight)
			);
		}
		else
		{
			// Left/Right — vertical tab strip
			mComputedStripSize = ComputeVerticalStripWidth();
			float h = heightSpec.Resolve(0, MinHeight, MaxHeight);
			float contentW = 0;

			if (mSelectedIndex >= 0 && mSelectedIndex < mTabs.Count)
			{
				let content = mTabs[mSelectedIndex].Content;
				if (content.Visibility != .Gone)
				{
					MeasureSpec contentWidthSpec;
					if (widthSpec.SpecMode == .Exactly)
						contentWidthSpec = MeasureSpec.MakeAtMost(Math.Max(0, widthSpec.Size - mComputedStripSize));
					else if (widthSpec.SpecMode == .AtMost)
						contentWidthSpec = MeasureSpec.MakeAtMost(Math.Max(0, widthSpec.Size - mComputedStripSize));
					else
						contentWidthSpec = MeasureSpec.MakeUnspecified();

					content.Measure(contentWidthSpec, MeasureSpec.MakeAtMost(h));
					contentW = content.MeasuredWidth;
				}
			}

			SetMeasuredDimension(
				widthSpec.Resolve(mComputedStripSize + contentW, MinWidth, MaxWidth),
				heightSpec.Resolve(h, MinHeight, MaxHeight)
			);
		}
	}

	protected override void OnLayout(float width, float height)
	{
		if (mSelectedIndex < 0 || mSelectedIndex >= mTabs.Count)
			return;

		let content = mTabs[mSelectedIndex].Content;
		if (content.Visibility == .Gone)
			return;

		switch (mTabPlacement)
		{
		case .Top:
			float ch = Math.Max(0, height - mTabHeight);
			content.Layout(0, mTabHeight, width, ch);
		case .Bottom:
			float ch2 = Math.Max(0, height - mTabHeight);
			content.Layout(0, 0, width, ch2);
		case .Left:
			float cw = Math.Max(0, width - mComputedStripSize);
			content.Layout(mComputedStripSize, 0, cw, height);
		case .Right:
			float cw2 = Math.Max(0, width - mComputedStripSize);
			content.Layout(0, 0, cw2, height);
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Rebuild cached tab rects
		RebuildTabRects();

		// Draw order: container bg → strip bg → inactive tabs → content → active tab
		// The active tab MUST be painted last so its expand covers the container border.
		if (IsHorizontalStrip)
			DrawHorizontalBackground(ctx, theme, palette);
		else
			DrawVerticalBackground(ctx, theme, palette);

		// Draw selected content (between background and active tab)
		if (mSelectedIndex >= 0 && mSelectedIndex < mTabs.Count)
		{
			let content = mTabs[mSelectedIndex].Content;
			if (content.Visibility != .Gone)
				content.Draw(ctx);
		}

		// Draw active tab LAST — on top of content and container border
		if (IsHorizontalStrip)
			DrawActiveHorizontalTab(ctx, theme, palette);
		else
			DrawActiveVerticalTab(ctx, theme, palette);
	}

	/// Rebuild the cached tab rectangles from current font metrics.
	private void RebuildTabRects()
	{
		mTabRects.Clear();

		if (IsHorizontalStrip)
		{
			float stripY = (mTabPlacement == .Top) ? 0 : Height - mTabHeight;
			float x = mStripPadding; // TB: tablayout_x padding 0 10

			if (Context != null && Context.FontService != null)
			{
				let font = Context.FontService.GetFont(mFontSize);
				if (font != null)
				{
					for (let tab in mTabs)
					{
						float textW = font.Font.MeasureString(tab.Title);
						float tabW = Math.Max(mMinTabWidth, textW + mTabPadding * 2);
						mTabRects.Add(.(x, stripY, tabW, mTabHeight));
						x += tabW;
					}
					Context.FontService.ReleaseFont(font);
				}
			}

			// Fallback: distribute evenly if font unavailable
			if (mTabRects.Count == 0 && mTabs.Count > 0)
			{
				float tabW = Math.Max(mMinTabWidth, (mTabs.Count > 0) ? Width / mTabs.Count : Width);
				float fx = mStripPadding;
				for (int i = 0; i < mTabs.Count; i++)
				{
					mTabRects.Add(.(fx, stripY, tabW, mTabHeight));
					fx += tabW;
				}
			}
		}
		else
		{
			// Vertical tab strip
			float stripX = (mTabPlacement == .Left) ? 0 : Width - mComputedStripSize;
			float y = mStripPadding; // TB: tablayout_y padding 10 0

			for (int i = 0; i < mTabs.Count; i++)
			{
				mTabRects.Add(.(stripX, y, mComputedStripSize, mTabHeight));
				y += mTabHeight;
			}
		}
	}

	/// Draw container background, strip background, and inactive tabs (everything except active tab).
	private void DrawHorizontalBackground(DrawContext ctx, Theme theme, Palette palette)
	{
		float stripY = (mTabPlacement == .Top) ? 0 : Height - mTabHeight;
		float contentH = Height - mTabHeight;
		if (contentH < 0) contentH = 0;

		let contentBgDrawable = theme?.GetDrawable("TabView", "contentBackground");
		bool hasDrawableContent = contentBgDrawable != null;

		float contentY = (mTabPlacement == .Top) ? mTabHeight : 0;

		let stripBg = theme?.GetColor("TabView", "tabBackground") ?? Palette.Darken(palette.Surface, 0.15f);

		// Content background drawn FIRST — its NineSlice expand bleeds freely.
		if (hasDrawableContent)
		{
			contentBgDrawable.Draw(ctx, .(0, contentY, Width, contentH));
		}
		else
		{
			let contentBg = theme?.GetColor("TabView", "contentBackground") ?? palette.Surface;
			ctx.FillRect(.(0, contentY, Width, contentH), contentBg);
		}

		// Tab strip background drawn AFTER the container — covers container bleed in the strip area.
		// The active tab (drawn last in a separate pass) covers the container border at the junction.
		ctx.FillRect(.(0, stripY, Width, mTabHeight), stripBg);

		// Placement-specific drawable keys
		StringView placementKey = (mTabPlacement == .Top) ? "Top" : "Bottom";
		let inactiveDrawableKey = scope String()..AppendF("inactiveTab{}", placementKey);

		let inactiveDrawable = theme?.GetDrawable("TabView", inactiveDrawableKey)
			?? theme?.GetDrawable("TabView", "inactiveTab");

		if (Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let inactiveText = theme?.GetColor("TabView", "inactiveTabText") ?? Palette.WithAlpha(palette.Text, 153);
					let hoverText = theme?.GetColor("TabView", "hoverTabText") ?? palette.Text;

					// Pass 1: draw inactive tabs (skip selected and hovered)
					for (int i = 0; i < mTabs.Count && i < mTabRects.Count; i++)
					{
						if (i == mSelectedIndex || i == mHoveredTabIndex)
							continue;

						let tab = mTabs[i];
						let tabRect = mTabRects[i];

						if (inactiveDrawable != null)
							inactiveDrawable.Draw(ctx, tabRect);

						ctx.DrawText(tab.Title, font.Font, font.Atlas, atlasTexture,
							tabRect, .Center, .Middle, inactiveText);
					}

					// Pass 2: draw hovered inactive tab
					if (mHoveredTabIndex >= 0 && mHoveredTabIndex != mSelectedIndex
						&& mHoveredTabIndex < mTabs.Count && mHoveredTabIndex < mTabRects.Count)
					{
						let tab = mTabs[mHoveredTabIndex];
						let tabRect = mTabRects[mHoveredTabIndex];

						if (inactiveDrawable != null)
						{
							inactiveDrawable.Draw(ctx, tabRect);
						}
						else
						{
							let hoverColor = theme?.GetColor("TabView", "tabHover") ?? Palette.WithAlpha(palette.Accent, 30);
							ctx.FillRect(tabRect, hoverColor);
						}

						ctx.DrawText(tab.Title, font.Font, font.Atlas, atlasTexture,
							tabRect, .Center, .Middle, hoverText);
					}

					// Pass 3: border line — only when no content drawable
					if (!hasDrawableContent)
					{
						let borderColor = theme?.GetColor("TabView", "tabBorder") ?? palette.Border;
						if (mTabPlacement == .Top)
							ctx.FillRect(.(0, stripY + mTabHeight - 1, Width, 1), borderColor);
						else
							ctx.FillRect(.(0, stripY, Width, 1), borderColor);
					}
				}
				Context.FontService.ReleaseFont(font);
			}
		}
	}

	/// Draw the active tab on top of everything (including content) so its expand covers the container border.
	private void DrawActiveHorizontalTab(DrawContext ctx, Theme theme, Palette palette)
	{
		if (mSelectedIndex < 0 || mSelectedIndex >= mTabs.Count || mSelectedIndex >= mTabRects.Count)
			return;

		float stripY = (mTabPlacement == .Top) ? 0 : Height - mTabHeight;

		StringView placementKey = (mTabPlacement == .Top) ? "Top" : "Bottom";
		let activeDrawableKey = scope String()..AppendF("activeTab{}", placementKey);

		let activeDrawable = theme?.GetDrawable("TabView", activeDrawableKey)
			?? theme?.GetDrawable("TabView", "activeTab");

		let tab = mTabs[mSelectedIndex];
		let tabRect = mTabRects[mSelectedIndex];

		if (activeDrawable != null)
			activeDrawable.Draw(ctx, tabRect);
		else
		{
			let activeBg = theme?.GetColor("TabView", "activeTabBackground") ?? palette.Surface;
			ctx.FillRect(tabRect, activeBg);
			if (mTabPlacement == .Top)
				ctx.FillRect(.(tabRect.X, stripY + mTabHeight - 2, tabRect.Width, 2), palette.Accent);
			else
				ctx.FillRect(.(tabRect.X, stripY, tabRect.Width, 2), palette.Accent);
		}

		if (Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let activeText = theme?.GetColor("TabView", "activeTabText") ?? palette.Text;
					ctx.DrawText(tab.Title, font.Font, font.Atlas, atlasTexture,
						tabRect, .Center, .Middle, activeText);
				}
				Context.FontService.ReleaseFont(font);
			}
		}
	}

	/// Draw container background, strip background, and inactive tabs for vertical layout.
	private void DrawVerticalBackground(DrawContext ctx, Theme theme, Palette palette)
	{
		float stripX = (mTabPlacement == .Left) ? 0 : Width - mComputedStripSize;
		float contentW = Width - mComputedStripSize;
		if (contentW < 0) contentW = 0;

		let contentBgDrawable = theme?.GetDrawable("TabView", "contentBackground");
		bool hasDrawableContent = contentBgDrawable != null;

		float contentX = (mTabPlacement == .Left) ? mComputedStripSize : 0;

		let stripBg = theme?.GetColor("TabView", "tabBackground") ?? Palette.Darken(palette.Surface, 0.15f);

		// Content background drawn FIRST — its NineSlice expand bleeds freely.
		if (hasDrawableContent)
		{
			contentBgDrawable.Draw(ctx, .(contentX, 0, contentW, Height));
		}
		else
		{
			let contentBg = theme?.GetColor("TabView", "contentBackground") ?? palette.Surface;
			ctx.FillRect(.(contentX, 0, contentW, Height), contentBg);
		}

		// Tab strip background drawn AFTER — covers container bleed in the strip area.
		ctx.FillRect(.(stripX, 0, mComputedStripSize, Height), stripBg);

		// Placement-specific drawable keys
		StringView placementKey = (mTabPlacement == .Left) ? "Left" : "Right";
		let inactiveDrawableKey = scope String()..AppendF("inactiveTab{}", placementKey);

		let inactiveDrawable = theme?.GetDrawable("TabView", inactiveDrawableKey)
			?? theme?.GetDrawable("TabView", "inactiveTab");

		if (Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let inactiveText = theme?.GetColor("TabView", "inactiveTabText") ?? Palette.WithAlpha(palette.Text, 153);
					let hoverText = theme?.GetColor("TabView", "hoverTabText") ?? palette.Text;

					// Pass 1: draw inactive tabs (skip selected and hovered)
					for (int i = 0; i < mTabs.Count && i < mTabRects.Count; i++)
					{
						if (i == mSelectedIndex || i == mHoveredTabIndex)
							continue;

						let tab = mTabs[i];
						let tabRect = mTabRects[i];

						if (inactiveDrawable != null)
							inactiveDrawable.Draw(ctx, tabRect);

						ctx.DrawText(tab.Title, font.Font, font.Atlas, atlasTexture,
							tabRect, .Center, .Middle, inactiveText);
					}

					// Pass 2: draw hovered inactive tab
					if (mHoveredTabIndex >= 0 && mHoveredTabIndex != mSelectedIndex
						&& mHoveredTabIndex < mTabs.Count && mHoveredTabIndex < mTabRects.Count)
					{
						let tab = mTabs[mHoveredTabIndex];
						let tabRect = mTabRects[mHoveredTabIndex];

						if (inactiveDrawable != null)
						{
							inactiveDrawable.Draw(ctx, tabRect);
						}
						else
						{
							let hoverColor = theme?.GetColor("TabView", "tabHover") ?? Palette.WithAlpha(palette.Accent, 30);
							ctx.FillRect(tabRect, hoverColor);
						}

						ctx.DrawText(tab.Title, font.Font, font.Atlas, atlasTexture,
							tabRect, .Center, .Middle, hoverText);
					}

					// Pass 3: border line — only when no content drawable
					if (!hasDrawableContent)
					{
						let borderColor = theme?.GetColor("TabView", "tabBorder") ?? palette.Border;
						if (mTabPlacement == .Left)
							ctx.FillRect(.(stripX + mComputedStripSize - 1, 0, 1, Height), borderColor);
						else
							ctx.FillRect(.(stripX, 0, 1, Height), borderColor);
					}
				}
				Context.FontService.ReleaseFont(font);
			}
		}
	}

	/// Draw the active tab on top of everything for vertical layout.
	private void DrawActiveVerticalTab(DrawContext ctx, Theme theme, Palette palette)
	{
		if (mSelectedIndex < 0 || mSelectedIndex >= mTabs.Count || mSelectedIndex >= mTabRects.Count)
			return;

		float stripX = (mTabPlacement == .Left) ? 0 : Width - mComputedStripSize;

		StringView placementKey = (mTabPlacement == .Left) ? "Left" : "Right";
		let activeDrawableKey = scope String()..AppendF("activeTab{}", placementKey);

		let activeDrawable = theme?.GetDrawable("TabView", activeDrawableKey)
			?? theme?.GetDrawable("TabView", "activeTab");

		let tab = mTabs[mSelectedIndex];
		let tabRect = mTabRects[mSelectedIndex];

		if (activeDrawable != null)
			activeDrawable.Draw(ctx, tabRect);
		else
		{
			let activeBg = theme?.GetColor("TabView", "activeTabBackground") ?? palette.Surface;
			ctx.FillRect(tabRect, activeBg);
			if (mTabPlacement == .Left)
				ctx.FillRect(.(stripX + mComputedStripSize - 2, tabRect.Y, 2, mTabHeight), palette.Accent);
			else
				ctx.FillRect(.(stripX, tabRect.Y, 2, mTabHeight), palette.Accent);
		}

		if (Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let activeText = theme?.GetColor("TabView", "activeTabText") ?? palette.Text;
					ctx.DrawText(tab.Title, font.Font, font.Atlas, atlasTexture,
						tabRect, .Center, .Middle, activeText);
				}
				Context.FontService.ReleaseFont(font);
			}
		}
	}

	public override View HitTest(Vector2 point)
	{
		if (Visibility != .Visible || !IsHitTestVisible || IsPendingDeletion)
			return null;

		let localPoint = PointToLocal(point);
		if (localPoint.X < 0 || localPoint.Y < 0 || localPoint.X > Width || localPoint.Y > Height)
			return null;

		// Check if point is in tab strip — we handle this ourselves
		if (IsPointInStrip(localPoint))
			return this;

		// Content area — delegate to children
		for (int i = ChildCount - 1; i >= 0; i--)
		{
			let child = GetChildAt(i);
			let hit = child.HitTest(localPoint);
			if (hit != null) return hit;
		}

		return this;
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		// Use pre-computed local coordinates from InputManager
		let localX = e.LocalX;
		let localY = e.LocalY;

		if (IsPointInStrip(.(localX, localY)))
		{
			int tabIndex = GetTabIndexAtPoint(localX, localY);
			if (tabIndex >= 0 && tabIndex < mTabs.Count)
				SelectedIndex = tabIndex;

			// Always consume clicks on the tab strip
			e.Handled = true;
		}
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		let localX = e.LocalX;
		let localY = e.LocalY;
		if (IsPointInStrip(.(localX, localY)))
		{
			int tabIdx = GetTabIndexAtPoint(localX, localY);
			mHoveredTabIndex = tabIdx;
			CursorType = (tabIdx >= 0) ? .Pointer : .Default;
		}
		else
		{
			mHoveredTabIndex = -1;
			CursorType = .Default;
		}
	}

	public override void OnMouseLeave(MouseEventArgs e)
	{
		mHoveredTabIndex = -1;
		CursorType = .Default;
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled || mTabs.Count == 0)
			return;

		// For Top/Bottom: Left/Right cycle tabs. For Left/Right: Up/Down cycle tabs.
		bool prev = IsHorizontalStrip ? (e.Key == .Left) : (e.Key == .Up);
		bool next = IsHorizontalStrip ? (e.Key == .Right) : (e.Key == .Down);

		if (prev)
		{
			if (mSelectedIndex > 0)
				SelectedIndex = mSelectedIndex - 1;
			e.Handled = true;
		}
		else if (next)
		{
			if (mSelectedIndex < mTabs.Count - 1)
				SelectedIndex = mSelectedIndex + 1;
			e.Handled = true;
		}
	}

	/// Check if a local-space point is within the tab strip area.
	private bool IsPointInStrip(Vector2 local)
	{
		switch (mTabPlacement)
		{
		case .Top:    return local.Y >= 0 && local.Y <= mTabHeight;
		case .Bottom: return local.Y >= Height - mTabHeight && local.Y <= Height;
		case .Left:   return local.X >= 0 && local.X <= mComputedStripSize;
		case .Right:  return local.X >= Width - mComputedStripSize && local.X <= Width;
		}
	}

	/// Determine which tab is at the given local coordinates using cached rects.
	private int GetTabIndexAtPoint(float localX, float localY)
	{
		for (int i = 0; i < mTabRects.Count; i++)
		{
			let r = mTabRects[i];
			if (localX >= r.X && localX < r.X + r.Width &&
				localY >= r.Y && localY < r.Y + r.Height)
				return i;
		}
		return -1;
	}
}
