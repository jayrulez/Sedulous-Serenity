using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// A dropdown selection control.
public class ComboBox : Control
{
	private List<String> mItems = new .() ~ DeleteContainerAndItems!(_);
	private int mSelectedIndex = -1;
	private String mPlaceholderText ~ delete _;
	private bool mIsDropDownOpen;
	private Popup mDropdownPopup;
	private ListBox mDropdownList ~ { }; // Owned by popup
	private float mMaxDropDownHeight = 200;

	public ~this()
	{
		// Delete popup - it's not part of the layout tree
		if (mDropdownPopup != null)
			delete mDropdownPopup;
	}

	// Events
	private EventAccessor<delegate void(ComboBox, int, int)> mSelectionChangedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(ComboBox)> mDropDownOpenedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(ComboBox)> mDropDownClosedEvent = new .() ~ delete _;

	/// The items in the dropdown list.
	public List<String> Items => mItems;

	/// The currently selected index (-1 if none).
	public int SelectedIndex
	{
		get => mSelectedIndex;
		set
		{
			var value;
			if (value < -1 || value >= mItems.Count)
				value = -1;

			if (mSelectedIndex != value)
			{
				let oldIndex = mSelectedIndex;
				mSelectedIndex = value;
				InvalidateVisual();
				mSelectionChangedEvent.[Friend]Invoke(this, oldIndex, mSelectedIndex);
			}
		}
	}

	/// The currently selected item text (empty if none).
	public StringView SelectedItem
	{
		get => mSelectedIndex >= 0 && mSelectedIndex < mItems.Count ? mItems[mSelectedIndex] : "";
	}

	/// Whether the dropdown is currently open.
	public bool IsDropDownOpen => mIsDropDownOpen;

	/// Maximum height of the dropdown popup.
	public float MaxDropDownHeight
	{
		get => mMaxDropDownHeight;
		set => mMaxDropDownHeight = Math.Max(50, value);
	}

	/// Placeholder text shown when nothing is selected.
	public StringView PlaceholderText
	{
		get => mPlaceholderText ?? "";
		set
		{
			if (mPlaceholderText == null)
				mPlaceholderText = new String();
			mPlaceholderText.Set(value);
			InvalidateVisual();
		}
	}

	/// Fired when selection changes.
	public EventAccessor<delegate void(ComboBox, int, int)> SelectionChanged => mSelectionChangedEvent;

	/// Fired when dropdown opens.
	public EventAccessor<delegate void(ComboBox)> DropDownOpened => mDropDownOpenedEvent;

	/// Fired when dropdown closes.
	public EventAccessor<delegate void(ComboBox)> DropDownClosed => mDropDownClosedEvent;

	public this()
	{
		Focusable = true;
		Cursor = .Pointer;
		Height = .Fixed(28);
		BorderThickness = Thickness(1);
		Padding = Thickness(6, 4, 24, 4); // Right padding for arrow

		// Create dropdown popup and list
		mDropdownPopup = new Popup();
		mDropdownPopup.Behavior = .CloseOnClickOutside | .CloseOnEscape;
		mDropdownPopup.Closed.Subscribe(new => OnDropdownClosed);

		mDropdownList = new ListBox();
		mDropdownList.SelectionMode = .Single;
		mDropdownList.BorderThickness = Thickness(0);
		mDropdownList.SelectionChanged.Subscribe(new => OnListSelectionChanged);
		mDropdownPopup.Content = mDropdownList;
	}

	/// Adds an item to the dropdown list.
	public void AddItem(StringView text)
	{
		let item = new String(text);
		mItems.Add(item);
	}

	/// Removes an item from the dropdown list.
	public void RemoveItem(int index)
	{
		if (index >= 0 && index < mItems.Count)
		{
			delete mItems[index];
			mItems.RemoveAt(index);

			if (mSelectedIndex >= mItems.Count)
				mSelectedIndex = mItems.Count - 1;
		}
	}

	/// Clears all items from the dropdown list.
	public void ClearItems()
	{
		DeleteContainerAndItems!(mItems);
		mItems = new .();
		mSelectedIndex = -1;
		InvalidateVisual();
	}

	/// Opens the dropdown.
	public void OpenDropDown()
	{
		if (mIsDropDownOpen || mItems.Count == 0)
			return;

		// Populate the dropdown list
		mDropdownList.ClearItems();
		for (let item in mItems)
			mDropdownList.AddItem(item);

		// Set initial selection
		if (mSelectedIndex >= 0)
			mDropdownList.SelectedIndex = mSelectedIndex;

		// Calculate popup size
		let itemCount = Math.Min(mItems.Count, (int)(mMaxDropDownHeight / mDropdownList.ItemHeight));
		let popupHeight = Math.Min(mMaxDropDownHeight, itemCount * mDropdownList.ItemHeight + 4);

		mDropdownPopup.Width = .Fixed(Bounds.Width);
		mDropdownPopup.Height = .Fixed(popupHeight);

		// Set context directly - popups are not part of the normal layout tree
		mDropdownPopup.[Friend]mContext = Context;

		// Open anchored below this control
		mDropdownPopup.OpenAt(this, .Bottom);

		mIsDropDownOpen = true;
		mDropDownOpenedEvent.[Friend]Invoke(this);
		InvalidateVisual();
	}

	/// Closes the dropdown.
	public void CloseDropDown()
	{
		if (!mIsDropDownOpen)
			return;

		mDropdownPopup.Close();
		// OnDropdownClosed will be called by popup's Closed event
	}

	private void OnDropdownClosed(Popup popup)
	{
		if (mIsDropDownOpen)
		{
			mIsDropDownOpen = false;
			mDropDownClosedEvent.[Friend]Invoke(this);
			InvalidateVisual();
		}
	}

	private void OnListSelectionChanged(ListBox list, int oldIndex, int newIndex)
	{
		if (newIndex >= 0 && newIndex < mItems.Count)
		{
			SelectedIndex = newIndex;
			CloseDropDown();
		}
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		let fontSize = FontSize;
		let height = fontSize * 1.4f + Padding.TotalVertical;
		return .(constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : 120, height);
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Background
		Color bgColor;
		if (!IsEnabled)
			bgColor = theme?.GetColor("Disabled") ?? Color(243, 243, 243);
		else if (mIsDropDownOpen)
			bgColor = theme?.GetColor("Pressed") ?? Color(204, 228, 247);
		else if (IsMouseOver)
			bgColor = theme?.GetColor("Hover") ?? Color(229, 241, 251);
		else
			bgColor = Background ?? theme?.GetColor("Background") ?? Color.White;

		drawContext.FillRect(bounds, bgColor);

		// Border
		let borderColor = IsFocused || mIsDropDownOpen
			? (theme?.GetColor("BorderFocused") ?? Color(0, 120, 215))
			: (BorderBrush ?? theme?.GetColor("Border") ?? Color(204, 204, 204));

		drawContext.DrawRect(bounds, borderColor, 1);

		// Text
		let contentBounds = ContentBounds;
		let textToShow = mSelectedIndex >= 0 && mSelectedIndex < mItems.Count
			? mItems[mSelectedIndex]
			: mPlaceholderText;

		if (textToShow != null && textToShow.Length > 0)
		{
			let foreground = mSelectedIndex >= 0
				? (Foreground ?? theme?.GetColor("Foreground") ?? Color.Black)
				: (theme?.GetColor("ForegroundSecondary") ?? Color(128, 128, 128));

			let fontService = GetFontService();
			let cachedFont = fontService?.GetFont(FontFamily, FontSize);

			if (fontService != null && cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);

				if (atlas != null && atlasTexture != null)
				{
					// Clip text area (leave room for arrow)
					let textBounds = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width - 20, contentBounds.Height);
					drawContext.DrawText(textToShow, font, atlas, atlasTexture, textBounds, .Left, .Middle, foreground);
				}
			}
		}

		// Dropdown arrow
		let arrowColor = IsEnabled
			? (theme?.GetColor("Foreground") ?? Color.Black)
			: (theme?.GetColor("ForegroundDisabled") ?? Color(160, 160, 160));

		let arrowX = bounds.Right - 16;
		let arrowY = bounds.Y + bounds.Height / 2;

		// Draw triangle pointing down
		drawContext.FillRect(.(arrowX - 4, arrowY - 2, 8, 1), arrowColor);
		drawContext.FillRect(.(arrowX - 3, arrowY - 1, 6, 1), arrowColor);
		drawContext.FillRect(.(arrowX - 2, arrowY, 4, 1), arrowColor);
		drawContext.FillRect(.(arrowX - 1, arrowY + 1, 2, 1), arrowColor);
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		base.OnMouseDownRouted(args);

		if (args.Button == .Left && IsEnabled)
		{
			if (mIsDropDownOpen)
				CloseDropDown();
			else
				OpenDropDown();

			Context?.SetFocus(this);
			args.Handled = true;
		}
	}

	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		base.OnKeyDownRouted(args);

		if (!IsEnabled)
			return;

		switch (args.Key)
		{
		case .Up:
			if (!mIsDropDownOpen && mSelectedIndex > 0)
			{
				SelectedIndex = mSelectedIndex - 1;
				args.Handled = true;
			}

		case .Down:
			if (!mIsDropDownOpen && mSelectedIndex < mItems.Count - 1)
			{
				SelectedIndex = mSelectedIndex + 1;
				args.Handled = true;
			}
			else if (!mIsDropDownOpen && args.HasModifier(.Alt))
			{
				OpenDropDown();
				args.Handled = true;
			}

		case .Return, .Space:
			if (mIsDropDownOpen)
				CloseDropDown();
			else
				OpenDropDown();
			args.Handled = true;

		case .Escape:
			if (mIsDropDownOpen)
			{
				CloseDropDown();
				args.Handled = true;
			}

		case .F4:
			if (mIsDropDownOpen)
				CloseDropDown();
			else
				OpenDropDown();
			args.Handled = true;

		default:
		}
	}

	protected override void OnMouseEnter()
	{
		base.OnMouseEnter();
		InvalidateVisual();
	}

	protected override void OnMouseLeave()
	{
		base.OnMouseLeave();
		InvalidateVisual();
	}

	protected override void OnGotFocus()
	{
		base.OnGotFocus();
		InvalidateVisual();
	}

	protected override void OnLostFocus()
	{
		base.OnLostFocus();
		InvalidateVisual();
	}

	/// Gets the font service from the context.
	private IFontService GetFontService()
	{
		let context = Context;
		if (context != null)
		{
			if (context.GetService<IFontService>() case .Ok(let service))
				return service;
		}
		return null;
	}
}
