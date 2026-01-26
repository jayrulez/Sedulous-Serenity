using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// A popup menu containing menu items.
/// Can be used as a context menu (right-click) or dropdown menu.
public class ContextMenu : Popup
{
	private StackPanel mItemsPanel; // Owned by parent via Content property
	private int mSelectedIndex = -1;

	/// The menu items in this context menu.
	public List<UIElement> Items => mItemsPanel.Children;

	/// The currently selected/highlighted item index.
	public int SelectedIndex
	{
		get => mSelectedIndex;
		set
		{
			if (mSelectedIndex != value)
			{
				mSelectedIndex = Math.Clamp(value, -1, Items.Count - 1);
				InvalidateVisual();
			}
		}
	}

	public this()
	{
		Behavior = .Default;
		Padding = Thickness(2);
		Focusable = true; // Enable keyboard navigation

		// Create items panel
		mItemsPanel = new StackPanel();
		mItemsPanel.Orientation = .Vertical;
		mItemsPanel.Spacing = 0;
		Content = mItemsPanel;
	}

	/// Opens the context menu and gives it keyboard focus.
	public new void Open()
	{
		base.Open();
		RequestFocusForKeyboard();
	}

	/// Opens the context menu at the specified screen position.
	public new void OpenAt(float x, float y)
	{
		base.OpenAt(x, y);
		RequestFocusForKeyboard();
	}

	/// Opens the context menu anchored to an element.
	public new void OpenAt(UIElement anchor, PopupPlacement placement = .Bottom)
	{
		base.OpenAt(anchor, placement);
		RequestFocusForKeyboard();
	}

	/// Requests keyboard focus for navigation.
	private void RequestFocusForKeyboard()
	{
		Context?.SetFocus(this);
		// Select first item if none selected
		if (mSelectedIndex < 0 && Items.Count > 0)
			SelectNext();
	}

	/// Adds a menu item to this context menu.
	public void AddItem(MenuItem item)
	{
		mItemsPanel.AddChild(item);
		InvalidateMeasure();
	}

	/// Adds a separator to this context menu.
	public void AddSeparator()
	{
		AddItem(MenuItem.Separator());
	}

	/// Adds a text item with a click handler.
	public MenuItem AddItem(StringView text, delegate void(MenuItem) onClick)
	{
		let item = new MenuItem(text);
		if (onClick != null)
			item.Click.Subscribe(onClick);
		AddItem(item);
		return item;
	}

	/// Adds a text item with shortcut text and click handler.
	public MenuItem AddItem(StringView text, StringView shortcut, delegate void(MenuItem) onClick)
	{
		let item = new MenuItem(text);
		item.ShortcutText = shortcut;
		if (onClick != null)
			item.Click.Subscribe(onClick);
		AddItem(item);
		return item;
	}

	/// Removes all menu items.
	public void ClearItems()
	{
		mItemsPanel.ClearChildren();
		mSelectedIndex = -1;
		InvalidateMeasure();
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Shadow
		let shadowOffset = 3.0f;
		let shadowBounds = RectangleF(bounds.X + shadowOffset, bounds.Y + shadowOffset, bounds.Width, bounds.Height);
		drawContext.FillRect(shadowBounds, Color(0, 0, 0, 100));

		// Background
		let bg = Background ?? theme?.GetColor("Surface") ?? Color(45, 45, 50);
		drawContext.FillRect(bounds, bg);

		// Border
		let border = BorderBrush ?? theme?.GetColor("Border") ?? Color(70, 70, 80);
		drawContext.DrawRect(bounds, border, 1.0f);

		// Render menu items
		RenderContent(drawContext);
	}

	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		switch (args.Key)
		{
		case .Up:
			SelectPrevious();
			args.Handled = true;
		case .Down:
			SelectNext();
			args.Handled = true;
		case .Return, .KeypadEnter:
			ActivateSelected();
			args.Handled = true;
		case .Escape:
			Close();
			args.Handled = true;
		case .Right:
			// Open submenu if selected item has one
			if (mSelectedIndex >= 0 && mSelectedIndex < Items.Count)
			{
				if (let menuItem = Items[mSelectedIndex] as MenuItem)
				{
					if (menuItem.HasSubmenu)
					{
						menuItem.Submenu.Open();
						args.Handled = true;
					}
				}
			}
		default:
		}

		if (!args.Handled)
			base.OnKeyDownRouted(args);
	}

	private void SelectNext()
	{
		let count = Items.Count;
		if (count == 0) return;

		var newIndex = mSelectedIndex + 1;

		// Skip separators
		while (newIndex < count)
		{
			if (let item = Items[newIndex] as MenuItem)
			{
				if (!item.IsSeparator)
					break;
			}
			newIndex++;
		}

		if (newIndex >= count)
			newIndex = 0;

		// Skip separators from beginning
		while (newIndex < count)
		{
			if (let item = Items[newIndex] as MenuItem)
			{
				if (!item.IsSeparator)
					break;
			}
			newIndex++;
		}

		SelectedIndex = newIndex;
	}

	private void SelectPrevious()
	{
		let count = Items.Count;
		if (count == 0) return;

		var newIndex = mSelectedIndex - 1;

		// Skip separators
		while (newIndex >= 0)
		{
			if (let item = Items[newIndex] as MenuItem)
			{
				if (!item.IsSeparator)
					break;
			}
			newIndex--;
		}

		if (newIndex < 0)
			newIndex = count - 1;

		// Skip separators from end
		while (newIndex >= 0)
		{
			if (let item = Items[newIndex] as MenuItem)
			{
				if (!item.IsSeparator)
					break;
			}
			newIndex--;
		}

		SelectedIndex = newIndex;
	}

	private void ActivateSelected()
	{
		if (mSelectedIndex < 0 || mSelectedIndex >= Items.Count)
			return;

		if (let menuItem = Items[mSelectedIndex] as MenuItem)
		{
			if (!menuItem.IsSeparator && menuItem.IsEnabled)
			{
				if (menuItem.HasSubmenu)
				{
					menuItem.Submenu.Open();
				}
				else
				{
					menuItem.[Friend]mClickEvent.[Friend]Invoke(menuItem);
					Close();
				}
			}
		}
	}
}
