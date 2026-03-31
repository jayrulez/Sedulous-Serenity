namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// A horizontal menu strip where each item opens a ContextMenu dropdown.
/// Follows the Toolbar pattern (extends LinearLayout).
public class MenuBar : LinearLayout, IPopupOwner
{
	private List<MenuBarItem> mMenuItems = new .() ~ DeleteContainerAndItems!(_);
	private int mActiveMenuIndex = -1;
	private bool mMenuMode = false;

	public this()
	{
		Orientation = .Horizontal;
		BaselineAligned = false;
		Padding = .(0, 0, 0, 0);
		Spacing = 0;
		MinHeight = 28;
	}

	/// Add a named menu. Returns the ContextMenu to populate with items.
	public ContextMenu AddMenu(StringView title)
	{
		let item = new MenuBarItem();
		item.Title = new .(title);
		item.Menu = new ContextMenu();

		let label = new MenuBarLabel(title);
		label.FontSize = 13;
		label.Padding = .(10, 4, 10, 4);
		label.VerticalAlignment = .Middle;
		item.ItemView = label;

		mMenuItems.Add(item);
		AddView(label);

		return item.Menu;
	}

	/// Number of menus.
	public int MenuCount => mMenuItems.Count;

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Background
		let bg = theme?.GetColor("MenuBar", "background") ?? Palette.Darken(palette.Surface, 0.05f);
		ctx.FillRect(.(0, 0, Width, Height), bg);

		// Bottom border
		let borderColor = theme?.GetColor("MenuBar", "border") ?? palette.Border;
		ctx.FillRect(.(0, Height - 1, Width, 1), borderColor);

		// Draw hover highlight on items
		let hoverColor = theme?.GetColor("MenuBar", "itemHover") ?? Palette.Lighten(palette.Surface, 0.1f);
		for (int i = 0; i < mMenuItems.Count; i++)
		{
			let item = mMenuItems[i];
			if (item.ItemView != null && (item.IsHovered || i == mActiveMenuIndex))
			{
				let v = item.ItemView;
				ctx.FillRect(.(v.Left, v.Top, v.Width, v.Height), hoverColor);
			}
		}

		// Draw children (labels)
		base.OnDraw(ctx);
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		// Track which item is hovered
		for (int i = 0; i < mMenuItems.Count; i++)
		{
			let item = mMenuItems[i];
			if (item.ItemView == null) continue;
			let v = item.ItemView;
			bool wasHovered = item.IsHovered;
			item.IsHovered = (e.LocalX >= v.Left && e.LocalX <= v.Left + v.Width &&
							  e.LocalY >= v.Top && e.LocalY <= v.Top + v.Height);

			if (item.IsHovered && !wasHovered && mMenuMode && i != mActiveMenuIndex)
			{
				// In menu mode: hovering a different item auto-switches
				OpenMenuAt(i);
			}
		}
		Invalidate();
	}

	public override void OnMouseLeave(MouseEventArgs e)
	{
		for (let item in mMenuItems)
			item.IsHovered = false;
		Invalidate();
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left) return;

		int clickedIndex = GetItemIndexAt(e.LocalX, e.LocalY);
		if (clickedIndex < 0) return;

		if (mMenuMode && clickedIndex == mActiveMenuIndex)
		{
			// Click on active menu item — close it
			CloseActiveMenu();
		}
		else
		{
			// Open or switch menu
			OpenMenuAt(clickedIndex);
		}

		e.Handled = true;
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!mMenuMode) return;

		if (e.Key == .Escape)
		{
			CloseActiveMenu();
			e.Handled = true;
		}
		else if (e.Key == .Left)
		{
			int next = (mActiveMenuIndex - 1 + mMenuItems.Count) % mMenuItems.Count;
			OpenMenuAt(next);
			e.Handled = true;
		}
		else if (e.Key == .Right)
		{
			int next = (mActiveMenuIndex + 1) % mMenuItems.Count;
			OpenMenuAt(next);
			e.Handled = true;
		}
	}

	/// IPopupOwner — called when the context menu popup is closed.
	public void OnPopupClosed(View popup)
	{
		// Find which menu was closed
		for (int i = 0; i < mMenuItems.Count; i++)
		{
			if (mMenuItems[i].Menu == popup)
			{
				if (i == mActiveMenuIndex)
				{
					mActiveMenuIndex = -1;
					mMenuMode = false;
					Invalidate();
				}
				return;
			}
		}
	}

	private int GetItemIndexAt(float localX, float localY)
	{
		for (int i = 0; i < mMenuItems.Count; i++)
		{
			let v = mMenuItems[i].ItemView;
			if (v == null) continue;
			if (localX >= v.Left && localX <= v.Left + v.Width &&
				localY >= v.Top && localY <= v.Top + v.Height)
				return i;
		}
		return -1;
	}

	private void OpenMenuAt(int index)
	{
		if (index < 0 || index >= mMenuItems.Count) return;

		let ctx = Context;
		if (ctx == null) return;

		// Close current menu if open
		if (mActiveMenuIndex >= 0 && mActiveMenuIndex < mMenuItems.Count)
		{
			ctx.ClosePopup(mMenuItems[mActiveMenuIndex].Menu);
		}

		let item = mMenuItems[index];
		let menu = item.Menu;
		let anchor = item.ItemView;

		if (anchor == null || menu == null || menu.ItemCount == 0) return;

		// Measure the menu
		float viewportW = ctx.LogicalWidth;
		float viewportH = ctx.LogicalHeight;
		menu.Measure(MeasureSpec.MakeAtMost(viewportW), MeasureSpec.MakeAtMost(viewportH));

		// Position below the anchor
		let anchorScreen = anchor.ToScreen(.(0, 0));
		float dpiScale = ctx.DpiScale;
		let anchorBounds = RectangleF(
			anchorScreen.X / dpiScale,
			anchorScreen.Y / dpiScale,
			anchor.Width,
			anchor.Height
		);

		let pos = PopupPositioner.PositionBelow(
			menu.MeasuredWidth, menu.MeasuredHeight,
			anchorBounds, viewportW, viewportH
		);

		ctx.ShowPopup(menu, this, pos.X, pos.Y, closeOnClickOutside: true, ownsView: false);

		mActiveMenuIndex = index;
		mMenuMode = true;
		Invalidate();
	}

	private void CloseActiveMenu()
	{
		if (mActiveMenuIndex >= 0 && mActiveMenuIndex < mMenuItems.Count)
		{
			let ctx = Context;
			ctx?.ClosePopup(mMenuItems[mActiveMenuIndex].Menu);
		}
		mActiveMenuIndex = -1;
		mMenuMode = false;
		Invalidate();
	}
}

/// Internal item data for a menu bar entry.
class MenuBarItem
{
	public String Title ~ delete _;
	public ContextMenu Menu ~ delete _;
	public View ItemView; // Owned by MenuBar as child view
	public bool IsHovered;
}

/// Simple label used as a menu bar item. Minimal — just text, no background.
class MenuBarLabel : Label
{
	public this(StringView text) : base(text)
	{
	}

	protected override void OnDraw(DrawContext ctx)
	{
		// Skip background — MenuBar draws hover highlight.
		// Just draw the text.
		base.OnDraw(ctx);
	}
}
