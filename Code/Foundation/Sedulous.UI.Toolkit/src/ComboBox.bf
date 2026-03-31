namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Fonts;
using Sedulous.Core;

/// Drop-down selector control. Displays selected item text with a dropdown arrow.
/// Click to open a popup list of items.
public class ComboBox : View, IPopupOwner
{
	private List<String> mItems = new .() ~ { for (let s in _) delete s; delete _; };
	private int mSelectedIndex = -1;
	private bool mIsOpen;
	private float mFontSize = 14;
	private float mArrowAreaWidth = 24;

	private EventAccessor<delegate void(ComboBox, int)> mOnSelectionChanged = new .() ~ delete _;

	public int SelectedIndex
	{
		get => mSelectedIndex;
		set
		{
			int clamped = Math.Clamp(value, -1, mItems.Count - 1);
			if (mSelectedIndex != clamped)
			{
				mSelectedIndex = clamped;
				Invalidate();
				mOnSelectionChanged.[Friend]Invoke(this, clamped);
			}
		}
	}

	/// Text of the currently selected item, or empty string.
	public StringView SelectedText
	{
		get => (mSelectedIndex >= 0 && mSelectedIndex < mItems.Count) ? mItems[mSelectedIndex] : "";
	}

	public int ItemCount => mItems.Count;

	public float FontSize
	{
		get => mFontSize;
		set { mFontSize = Math.Max(1, value); InvalidateLayout(); }
	}

	/// Whether the dropdown is currently open.
	public bool IsOpen => mIsOpen;

	/// Subscribe to selection change events.
	public EventAccessor<delegate void(ComboBox, int)> OnSelectionChanged => mOnSelectionChanged;

	public this()
	{
		Focusable = true;
		CursorType = .Pointer;
		Padding = .(8, 6, 8, 6);
	}

	/// Add an item. Returns the item index.
	public int AddItem(StringView text)
	{
		let index = mItems.Count;
		mItems.Add(new String(text));
		InvalidateLayout();
		return index;
	}

	/// Remove an item by index.
	public void RemoveItem(int index)
	{
		if (index < 0 || index >= mItems.Count)
			return;

		delete mItems[index];
		mItems.RemoveAt(index);

		if (mSelectedIndex >= mItems.Count)
			mSelectedIndex = mItems.Count - 1;

		InvalidateLayout();
	}

	/// Remove all items.
	public void ClearItems()
	{
		for (let s in mItems)
			delete s;
		mItems.Clear();
		mSelectedIndex = -1;
		InvalidateLayout();
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float maxTextW = 0;
		float textH = mFontSize;

		if (Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				textH = font.Font.Metrics.LineHeight;
				for (let item in mItems)
				{
					float w = font.Font.MeasureString(item);
					if (w > maxTextW) maxTextW = w;
				}
				Context.FontService.ReleaseFont(font);
			}
		}

		float desiredW = Padding.Horizontal + maxTextW + mArrowAreaWidth;
		float desiredH = Padding.Vertical + textH;

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Background — prefer drawable, fall back to rounded rect
		let bgDrawable = theme?.GetDrawable("ComboBox", "background");
		if (bgDrawable != null)
		{
			bgDrawable.Draw(ctx, .(0, 0, Width, Height), GetControlState());
		}
		else
		{
			let bg = theme?.GetColor("ComboBox", "background") ?? Palette.Darken(palette.Surface, 0.1f);
			let borderColor = mIsOpen
				? (theme?.GetColor("ComboBox", "focusBorder") ?? palette.Accent)
				: (theme?.GetColor("ComboBox", "border") ?? palette.Border);
			let cornerRadius = theme?.GetDimension("ComboBox", "cornerRadius") ?? 4;

			let bgColor = Palette.ResolveState(bg, GetControlState(), palette.Accent);
			ctx.FillRoundedRect(.(0, 0, Width, Height), cornerRadius, bgColor);
			ctx.DrawBorderRoundedRect(.(0, 0, Width, Height), cornerRadius, borderColor, 1);
		}

		// Selected text
		if (mSelectedIndex >= 0 && mSelectedIndex < mItems.Count && Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let textColor = theme?.GetColor("ComboBox", "text") ?? palette.Text;
					let textBounds = RectangleF(Padding.Left, 0, Width - Padding.Horizontal - mArrowAreaWidth, Height);
					ctx.DrawText(mItems[mSelectedIndex], font.Font, font.Atlas, atlasTexture,
						textBounds, .Left, .Middle, textColor);
				}
				Context.FontService.ReleaseFont(font);
			}
		}

		// Dropdown arrow — prefer drawable icon, fall back to polygon
		let arrowDrawable = theme?.GetDrawable("ComboBox", "arrowIcon");
		if (arrowDrawable != null)
		{
			let sz = arrowDrawable.IntrinsicSize;
			float iw = (sz.Width > 0) ? sz.Width : 10;
			float ih = (sz.Height > 0) ? sz.Height : 5;
			float ix = Width - mArrowAreaWidth * 0.5f - iw * 0.5f;
			float iy = (Height - ih) * 0.5f;
			arrowDrawable.Draw(ctx, .(ix, iy, iw, ih));
		}
		else
		{
			let arrowColor = theme?.GetColor("ComboBox", "arrowColor") ?? palette.Text;
			float arrowX = Width - mArrowAreaWidth * 0.5f;
			float arrowY = Height * 0.5f;
			float arrowSize = 4;
			Vector2[3] arrowPoints = .(
				.(arrowX - arrowSize, arrowY - arrowSize * 0.5f),
				.(arrowX + arrowSize, arrowY - arrowSize * 0.5f),
				.(arrowX, arrowY + arrowSize * 0.5f)
			);
			ctx.FillPolygon(arrowPoints, arrowColor);
		}

		// Focus indicator
		if (IsFocused)
		{
			let cornerRadius = theme?.GetDimension("ComboBox", "cornerRadius") ?? 4;
			DrawFocusIndicator(ctx, .(0, 0, Width, Height), cornerRadius);
		}
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		if (mIsOpen)
			CloseDropdown();
		else
			OpenDropdown();

		e.Handled = true;
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled)
			return;

		if (e.Key == .Space || e.Key == .Return)
		{
			if (!mIsOpen)
				OpenDropdown();
			e.Handled = true;
		}
		else if (e.Key == .Up)
		{
			if (mSelectedIndex > 0)
				SelectedIndex = mSelectedIndex - 1;
			e.Handled = true;
		}
		else if (e.Key == .Down)
		{
			if (mSelectedIndex < mItems.Count - 1)
				SelectedIndex = mSelectedIndex + 1;
			e.Handled = true;
		}
		else if (e.Key == .Escape && mIsOpen)
		{
			CloseDropdown();
			e.Handled = true;
		}
	}

	/// Open the dropdown popup.
	public void OpenDropdown()
	{
		if (mIsOpen || mItems.Count == 0 || Context == null)
			return;

		let menu = new ContextMenu();
		for (int i = 0; i < mItems.Count; i++)
		{
			int capturedIndex = i;
			menu.AddItem(mItems[i], new () =>
			{
				this.SelectedIndex = capturedIndex;
			});
		}

		// Measure the menu
		float viewportW = Context.Width / Context.DpiScale;
		float viewportH = Context.Height / Context.DpiScale;
		menu.Measure(MeasureSpec.MakeAtMost(viewportW), MeasureSpec.MakeAtMost(viewportH));

		// Position below this ComboBox
		let screenPos = ToScreen(.(0, 0));
		let logicalPos = Vector2(screenPos.X / Context.DpiScale, screenPos.Y / Context.DpiScale);
		let anchorBounds = RectangleF(logicalPos.X, logicalPos.Y, Width, Height);
		let pos = PopupPositioner.PositionBestFit(menu.MeasuredWidth, menu.MeasuredHeight,
			anchorBounds, viewportW, viewportH);

		// Match menu width to combobox width (at minimum)
		if (menu.MeasuredWidth < Width)
			menu.MinWidth = Width;

		Context.ShowPopup(menu, this, pos.X, pos.Y, true, true);
		mIsOpen = true;
		Invalidate();
	}

	/// Close the dropdown popup.
	public void CloseDropdown()
	{
		if (!mIsOpen || Context == null)
			return;

		// The popup will be closed via PopupLayer (click-outside or item click)
		// We just mark our state
		mIsOpen = false;
		Invalidate();
	}

	/// IPopupOwner implementation — called when our dropdown popup is closed.
	public void OnPopupClosed(View popup)
	{
		mIsOpen = false;
		Invalidate();
	}
}
