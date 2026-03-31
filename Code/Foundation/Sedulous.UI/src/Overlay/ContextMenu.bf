namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// A popup menu with a list of clickable items. Supports nested submenus.
public class ContextMenu : ViewGroup, IPopupOwner
{
	private List<MenuItem> mItems = new .() ~ {
		for (var item in _)
			item.Dispose();
		delete _;
	};
	private int mHoveredIndex = -1;
	private float mItemHeight = 28;
	private float mSeparatorHeight = 9;
	private float mHPadding = 12;
	private float mArrowPadding = 16;

	/// Currently open child submenu (reference only — owned by MenuItem).
	private ContextMenu mOpenSubmenu;

	/// Back-pointer to parent menu (null for root menus).
	public ContextMenu mParentMenu;

	/// Index of the item whose submenu is currently open (-1 if none).
	private int mSubmenuItemIndex = -1;

	/// Fixed height per item row.
	public float ItemHeight
	{
		get => mItemHeight;
		set { mItemHeight = Math.Max(16, value); Invalidate(); }
	}

	/// Number of items.
	public int ItemCount => mItems.Count;

	/// Add a clickable item. ContextMenu takes ownership of the action delegate.
	public void AddItem(StringView label, delegate void() action, bool enabled = true)
	{
		MenuItem item;
		item.Label = new String(label);
		item.Action = action;
		item.Enabled = enabled;
		item.IsSeparator = false;
		item.Submenu = null;
		mItems.Add(item);
		Invalidate();
	}

	/// Add a separator line.
	public void AddSeparator()
	{
		MenuItem item;
		item.Label = null;
		item.Action = null;
		item.Enabled = false;
		item.IsSeparator = true;
		item.Submenu = null;
		mItems.Add(item);
		Invalidate();
	}

	/// Add a submenu item. Returns the child ContextMenu for the caller to populate.
	/// The submenu is owned by the MenuItem and deleted when the parent menu is disposed.
	public ContextMenu AddSubmenu(StringView label, bool enabled = true)
	{
		let submenu = new ContextMenu();
		MenuItem item;
		item.Label = new String(label);
		item.Action = null;
		item.Enabled = enabled;
		item.IsSeparator = false;
		item.Submenu = submenu;
		mItems.Add(item);
		Invalidate();
		return submenu;
	}

	/// Get content inset: drawable padding if a background drawable is set,
	/// otherwise a small default padding to keep items away from the border.
	private Thickness GetContentInset()
	{
		let bgDrawable = Context?.Theme?.GetDrawable("ContextMenu", "background");
		if (bgDrawable != null)
		{
			let dp = bgDrawable.DrawablePadding;
			// Ensure minimum 2px padding even with drawable
			return .(Math.Max(2, dp.Left), Math.Max(2, dp.Top), Math.Max(2, dp.Right), Math.Max(2, dp.Bottom));
		}
		return .(2, 4, 2, 4); // Default: small padding from procedural border
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float maxTextWidth = 0;
		float totalHeight = 0;
		bool hasSubmenu = false;

		let fontService = Context?.FontService;

		for (let item in mItems)
		{
			if (item.IsSeparator)
			{
				totalHeight += mSeparatorHeight;
				continue;
			}

			totalHeight += mItemHeight;

			if (item.Submenu != null)
				hasSubmenu = true;

			if (item.Label != null)
			{
				float textW;
				if (fontService != null)
				{
					let font = fontService.GetFont(14);
					if (font != null)
					{
						textW = font.Font.MeasureString(item.Label);
						fontService.ReleaseFont(font);
					}
					else
					{
						textW = item.Label.Length * 8.4f;
					}
				}
				else
				{
					textW = item.Label.Length * 8.4f;
				}
				maxTextWidth = Math.Max(maxTextWidth, textW);
			}
		}

		// Account for drawable inset (nine-slice border) if present
		let inset = GetContentInset();
		float w = maxTextWidth + mHPadding * 2 + inset.Horizontal;
		if (hasSubmenu)
			w += mArrowPadding;
		float h = totalHeight + inset.Vertical;

		// Minimum width
		if (w < 120) w = 120;

		SetMeasuredDimension(
			widthSpec.Resolve(w, MinWidth, MaxWidth),
			heightSpec.Resolve(h, MinHeight, MaxHeight)
		);
	}

	protected override void OnLayout(float width, float height)
	{
		// No children to layout
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		float cornerRadius = theme?.GetDimension("ContextMenu", "cornerRadius") ?? 4;

		// Background — try drawable first, then color fallback
		let bgDrawable = theme?.GetDrawable("ContextMenu", "background");
		if (bgDrawable != null)
		{
			bgDrawable.Draw(ctx, .(0, 0, Width, Height));
		}
		else
		{
			Color bgColor = theme?.GetColor("ContextMenu", "background") ?? Color(60, 60, 60, 240);
			Color borderColor = theme?.GetColor("ContextMenu", "border") ?? Color(100, 100, 100, 200);
			if (cornerRadius > 0)
			{
				ctx.FillRoundedRect(.(0, 0, Width, Height), cornerRadius, bgColor);
				ctx.DrawBorderRoundedRect(.(0, 0, Width, Height), cornerRadius, borderColor, 1);
			}
			else
			{
				ctx.FillRect(.(0, 0, Width, Height), bgColor);
				ctx.DrawBorderRect(.(0, 0, Width, Height), borderColor, 1);
			}
		}

		Color hoverColor = theme?.GetColor("ContextMenu", "hoverBackground") ?? Color(80, 120, 200, 200);
		Color textColor = theme?.GetColor("ContextMenu", "text") ?? Color(230, 230, 230, 255);
		Color disabledColor = theme?.GetColor("ContextMenu", "disabledText") ?? Color(120, 120, 120, 255);
		Color separatorColor = theme?.GetColor("ContextMenu", "separator") ?? Color(100, 100, 100, 150);
		let itemHoverDrawable = theme?.GetDrawable("ContextMenu", "itemHover");

		// Offset content by drawable inset (nine-slice border within logical bounds)
		let inset = GetContentInset();
		float contentLeft = inset.Left;
		float contentWidth = Width - inset.Horizontal;
		float y = inset.Top;
		for (int i = 0; i < mItems.Count; i++)
		{
			let item = mItems[i];

			if (item.IsSeparator)
			{
				float sepY = y + mSeparatorHeight / 2;
				ctx.FillRect(.(contentLeft + mHPadding * 0.5f, sepY - 0.5f, contentWidth - mHPadding, 1), separatorColor);
				y += mSeparatorHeight;
				continue;
			}

			// Hover highlight — show when hovered or when this item's submenu is open
			bool isHighlighted = (i == mHoveredIndex || i == mSubmenuItemIndex) && item.Enabled;
			if (isHighlighted)
			{
				if (itemHoverDrawable != null)
					itemHoverDrawable.Draw(ctx, .(contentLeft + 2, y + 1, contentWidth - 4, mItemHeight - 2));
				else if (cornerRadius > 0)
					ctx.FillRoundedRect(.(contentLeft + 2, y + 1, contentWidth - 4, mItemHeight - 2), 3, hoverColor);
				else
					ctx.FillRect(.(contentLeft + 2, y + 1, contentWidth - 4, mItemHeight - 2), hoverColor);
			}

			// Text
			if (item.Label != null)
			{
				Color tc = item.Enabled ? textColor : disabledColor;
				ctx.DrawText(item.Label, 14, .(contentLeft + mHPadding, y + (mItemHeight - 14) / 2), tc);
			}

			// Submenu arrow indicator
			if (item.Submenu != null)
			{
				let arrowDrawable = theme?.GetDrawable("ContextMenu", "submenuArrow");
				Color arrowColor = item.Enabled ? textColor : disabledColor;
				float arrowX = contentLeft + contentWidth - mHPadding - 6;
				float arrowY = y + mItemHeight / 2;
				if (arrowDrawable != null)
				{
					let sz = arrowDrawable.IntrinsicSize;
					float aw = sz.Width > 0 ? sz.Width : 8;
					float ah = sz.Height > 0 ? sz.Height : 8;
					arrowDrawable.Draw(ctx, .(arrowX - aw / 2, arrowY - ah / 2, aw, ah));
				}
				else
				{
					// Fallback: draw a simple ">" character
					ctx.DrawText(">", 14, .(arrowX - 3, arrowY - 7), arrowColor);
				}
			}

			y += mItemHeight;
		}
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		int newIndex = GetItemIndexAt(e.LocalY);
		if (newIndex != mHoveredIndex)
		{
			mHoveredIndex = newIndex;

			// Handle submenu opening/closing based on hovered item
			if (newIndex >= 0 && newIndex < mItems.Count)
			{
				let item = mItems[newIndex];
				if (item.Submenu != null && item.Enabled && newIndex != mSubmenuItemIndex)
				{
					// Close old submenu and open new one
					CloseOpenSubmenu();
					OpenSubmenu(newIndex);
				}
				else if (item.Submenu == null && mOpenSubmenu != null)
				{
					// Hovering a leaf item — close any open submenu
					CloseOpenSubmenu();
				}
			}
			else if (mOpenSubmenu != null)
			{
				// Hovering separator or nothing — close submenu
				CloseOpenSubmenu();
			}

			Invalidate();
		}
	}

	public override void OnMouseLeave(MouseEventArgs e)
	{
		// Don't clear hover if mouse moved to the open submenu
		if (mOpenSubmenu == null)
		{
			mHoveredIndex = -1;
			Invalidate();
		}
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left) return;

		int idx = GetItemIndexAt(e.LocalY);
		if (idx >= 0 && idx < mItems.Count)
		{
			let item = mItems[idx];

			// If this item has a submenu, open it (or keep open) — don't close
			if (item.Submenu != null && item.Enabled)
			{
				if (idx != mSubmenuItemIndex)
				{
					CloseOpenSubmenu();
					OpenSubmenu(idx);
				}
				e.Handled = true;
				return;
			}

			// Leaf item — execute action and close entire chain
			if (!item.IsSeparator && item.Enabled && item.Action != null)
			{
				item.Action();
			}
		}

		// Defer closing entire chain to avoid use-after-free
		CloseEntireChain();
		e.Handled = true;
	}

	public override View HitTest(Vector2 point)
	{
		if (Visibility != .Visible || IsPendingDeletion)
			return null;

		var localPoint = PointToLocal(point);
		if (localPoint.X >= 0 && localPoint.Y >= 0 && localPoint.X <= Width && localPoint.Y <= Height)
			return this;

		return null;
	}

	/// Show a context menu at the given screen position.
	public static void Show(UIContext ctx, float x, float y, ContextMenu menu)
	{
		if (ctx == null || menu == null) return;

		// Measure to get size
		menu.Measure(
			MeasureSpec.MakeAtMost(ctx.Width / ctx.DpiScale),
			MeasureSpec.MakeAtMost(ctx.Height / ctx.DpiScale)
		);

		// Position with viewport clamping
		float logicalX = x / ctx.DpiScale;
		float logicalY = y / ctx.DpiScale;

		let pos = PopupPositioner.PositionBestFit(
			menu.MeasuredWidth, menu.MeasuredHeight,
			.(logicalX, logicalY, 0, 0),
			ctx.Width / ctx.DpiScale,
			ctx.Height / ctx.DpiScale
		);

		ctx.ShowPopup(menu, null, pos.X, pos.Y);
	}

	private int GetItemIndexAt(float localY)
	{
		let inset = GetContentInset();
		float y = inset.Top;
		for (int i = 0; i < mItems.Count; i++)
		{
			let item = mItems[i];
			float h = item.IsSeparator ? mSeparatorHeight : mItemHeight;

			if (localY >= y && localY < y + h)
				return item.IsSeparator ? -1 : i;

			y += h;
		}
		return -1;
	}

	/// Get the bounds of an item in local coordinates (for submenu positioning).
	private RectangleF GetItemBounds(int index)
	{
		let inset = GetContentInset();
		float contentLeft = inset.Left;
		float contentWidth = Width - inset.Horizontal;
		float y = inset.Top;
		for (int i = 0; i < mItems.Count; i++)
		{
			let item = mItems[i];
			float h = item.IsSeparator ? mSeparatorHeight : mItemHeight;
			if (i == index)
				return .(contentLeft, y, contentWidth, h);
			y += h;
		}
		return .(0, 0, 0, 0);
	}

	/// Open the submenu for the item at the given index.
	private void OpenSubmenu(int index)
	{
		if (index < 0 || index >= mItems.Count) return;
		let item = mItems[index];
		if (item.Submenu == null || !item.Enabled) return;

		let ctx = Context;
		if (ctx == null) return;

		let submenu = item.Submenu;
		submenu.mParentMenu = this;

		// Measure the submenu
		float viewportW = ctx.Width / ctx.DpiScale;
		float viewportH = ctx.Height / ctx.DpiScale;
		submenu.Measure(MeasureSpec.MakeAtMost(viewportW), MeasureSpec.MakeAtMost(viewportH));

		// Get anchor bounds in PopupLayer coordinates (same as root logical coords)
		let itemBounds = GetItemBounds(index);
		let anchorBounds = RectangleF(
			Left + itemBounds.X,
			Top + itemBounds.Y,
			itemBounds.Width,
			itemBounds.Height
		);

		let pos = PopupPositioner.PositionSubmenu(
			submenu.MeasuredWidth, submenu.MeasuredHeight,
			anchorBounds, viewportW, viewportH
		);

		// Show as popup — ownsView=false because MenuItem owns the submenu
		ctx.ShowPopup(submenu, this, pos.X, pos.Y, closeOnClickOutside: true, ownsView: false);

		mOpenSubmenu = submenu;
		mSubmenuItemIndex = index;
	}

	/// Close the currently open child submenu.
	private void CloseOpenSubmenu()
	{
		if (mOpenSubmenu != null)
		{
			// First close any grandchild submenus
			mOpenSubmenu.CloseOpenSubmenu();

			let ctx = Context;
			ctx?.ClosePopup(mOpenSubmenu);
			mOpenSubmenu = null;
			mSubmenuItemIndex = -1;
		}
	}

	/// Close the entire menu chain from leaf to root. Deferred via MutationQueue.
	private void CloseEntireChain()
	{
		// Walk up to find the root menu
		ContextMenu root = this;
		while (root.mParentMenu != null)
			root = root.mParentMenu;

		// Defer closing root — PopupLayer will close it (and it owns the view)
		let ctx = Context;
		if (ctx != null)
		{
			// Close all submenus first (they are ownsView=false, just detached)
			root.CloseOpenSubmenu();

			let rootRef = root;
			ctx.MutationQueue.QueueAction(new () => {
				ctx.ClosePopup(rootRef);
			});
		}
	}

	/// IPopupOwner — called when a child popup (submenu) is closed.
	public void OnPopupClosed(View popup)
	{
		if (mOpenSubmenu != null && popup == mOpenSubmenu)
		{
			mOpenSubmenu.mParentMenu = null;
			mOpenSubmenu = null;
			mSubmenuItemIndex = -1;
			Invalidate();
		}
	}
}
