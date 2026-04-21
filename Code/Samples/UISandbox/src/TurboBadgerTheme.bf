namespace Sandbox;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.UI;
using Sedulous.ImageData;

/// TurboBadger default skin theme (Public Domain).
/// Demonstrates creating a complete custom theme using NineSliceDrawable,
/// ImageDrawable, LayerDrawable, and StateListDrawable.
static class TurboBadgerTheme
{
	public static Theme Create(
		IImageData btnNormal,
		IImageData btnPressed,
		IImageData btnFlatOutline,
		IImageData checkbox,
		IImageData checkboxMark,
		IImageData checkboxPressed,
		IImageData radio,
		IImageData radioMark,
		IImageData radioPressed,
		IImageData sliderBgX,
		IImageData sliderHandle,
		IImageData container,
		IImageData separatorX,
		IImageData selection,
		IImageData editField = null,
		IImageData scrollBgX = null,
		IImageData scrollBgY = null,
		IImageData scrollFgX = null,
		IImageData scrollFgY = null,
		IImageData focusR4 = null,
		IImageData arrowDown = null,
		IImageData arrowRight = null,
		IImageData window = null,
		IImageData windowActive = null,
		IImageData itemHover = null,
		IImageData itemSelected = null,
		IImageData arrowUp = null,
		IImageData tabTopActive = null,
		IImageData tabTopInactive = null,
		IImageData tabBottomActive = null,
		IImageData tabBottomInactive = null,
		IImageData tabLeftActive = null,
		IImageData tabLeftInactive = null,
		IImageData tabRightActive = null,
		IImageData tabRightInactive = null)
	{
		let theme = new Theme();
		theme.Name = new String("TurboBadger");

		// Dark theme palette matching TB's default look
		theme.Palette = .()
		{
			Primary    = .(0.35f, 0.35f, 0.38f, 1.0f),
			Secondary  = .(0.25f, 0.25f, 0.28f, 1.0f),
			Accent     = .(0.3f, 0.55f, 0.9f, 1.0f),
			Background = .(0.22f, 0.22f, 0.25f, 1.0f),
			Surface    = .(0.28f, 0.28f, 0.31f, 1.0f),
			Error      = .(0.9f, 0.3f, 0.3f, 1.0f),
			Text       = .(0.996f, 0.996f, 0.996f, 1.0f),
			Border     = .(0.4f, 0.4f, 0.43f, 1.0f)
		};

		let p = theme.Palette;

		// TB "cut" and "expand" values from skin.tb.txt
		// cut: uniform nine-slice insets
		// expand: visual extends beyond logical bounds (shadows, glows)
		let btnCut = NineSlice(17, 17, 17, 17);
		let btnExpand = Thickness(7);
		let btnFlatCut = NineSlice(15, 15, 15, 15);
		let btnFlatExpand = Thickness(6);
		let containerCut = NineSlice(12, 12, 12, 12);
		let containerExpand = Thickness(6);
		let windowCut = NineSlice(16, 16, 16, 16);
		let windowExpand = Thickness(12);

		// === Button ===
		if (btnNormal != null)
		{
			let stateList = new StateListDrawable();
			stateList.SetDefault(new NineSliceDrawable(btnNormal, btnCut, btnExpand));
			if (btnFlatOutline != null)
				stateList.SetDrawable(.Hover, new NineSliceDrawable(btnFlatOutline, btnFlatCut, btnFlatExpand));
			if (btnPressed != null)
				stateList.SetDrawable(.Pressed, new NineSliceDrawable(btnPressed, btnCut, btnExpand));
			theme.SetDrawable("Button", "background", stateList);
		}

		// === ToggleButton ===
		if (btnNormal != null && btnPressed != null)
		{
			let uncheckedList = new StateListDrawable();
			uncheckedList.SetDefault(new NineSliceDrawable(btnNormal, btnCut, btnExpand));
			if (btnFlatOutline != null)
				uncheckedList.SetDrawable(.Hover, new NineSliceDrawable(btnFlatOutline, btnFlatCut, btnFlatExpand));
			theme.SetDrawable("ToggleButton", "background", uncheckedList);

			theme.SetDrawable("ToggleButton", "checkedBackground", new NineSliceDrawable(btnPressed, btnCut, btnExpand));
		}

		// === CheckBox ===
		// TB: checkbox.png is nine-slice base (cut 19, expand 7) — visual extends beyond widget.
		// checkbox_pressed.png is overlay (no expand) — drawn at widget bounds, appears INSIDE base border.
		// checkbox_mark.png is overlay (expand 7 in TB, but ImageDrawable doesn't support expand).
		let checkboxCut = NineSlice(19, 19, 19, 19);
		let checkboxExpand = Thickness(7);
		if (checkbox != null)
		{
			let uncheckedList = new StateListDrawable();
			uncheckedList.SetDefault(new NineSliceDrawable(checkbox, checkboxCut, checkboxExpand));
			if (checkboxPressed != null)
			{
				// Pressed/hover: expanded base + glow overlay at widget bounds (inside border)
				let pressedUnchecked = new LayerDrawable();
				pressedUnchecked.AddLayer(new NineSliceDrawable(checkbox, checkboxCut, checkboxExpand));
				pressedUnchecked.AddLayer(new ImageDrawable(checkboxPressed));
				uncheckedList.SetDrawable(.Pressed, pressedUnchecked);

				let hoverUnchecked = new LayerDrawable();
				hoverUnchecked.AddLayer(new NineSliceDrawable(checkbox, checkboxCut, checkboxExpand));
				hoverUnchecked.AddLayer(new ImageDrawable(checkboxPressed));
				uncheckedList.SetDrawable(.Hover, hoverUnchecked);
			}
			theme.SetDrawable("CheckBox", "unchecked", uncheckedList);

			if (checkboxMark != null)
			{
				let checkedList = new StateListDrawable();
				let defaultChecked = new LayerDrawable();
				defaultChecked.AddLayer(new NineSliceDrawable(checkbox, checkboxCut, checkboxExpand));
				defaultChecked.AddLayer(new ImageDrawable(checkboxMark));
				checkedList.SetDefault(defaultChecked);

				if (checkboxPressed != null)
				{
					let pressedChecked = new LayerDrawable();
					pressedChecked.AddLayer(new NineSliceDrawable(checkbox, checkboxCut, checkboxExpand));
					pressedChecked.AddLayer(new ImageDrawable(checkboxPressed));
					pressedChecked.AddLayer(new ImageDrawable(checkboxMark));
					checkedList.SetDrawable(.Pressed, pressedChecked);

					let hoverChecked = new LayerDrawable();
					hoverChecked.AddLayer(new NineSliceDrawable(checkbox, checkboxCut, checkboxExpand));
					hoverChecked.AddLayer(new ImageDrawable(checkboxPressed));
					hoverChecked.AddLayer(new ImageDrawable(checkboxMark));
					checkedList.SetDrawable(.Hover, hoverChecked);
				}
				theme.SetDrawable("CheckBox", "checked", checkedList);
			}
		}

		// === RadioButton ===
		// TB: radio.png is nine-slice base (cut 19, expand 7) — visual extends beyond widget.
		// radio_pressed.png is overlay with expand 7 (unlike checkbox which has no expand on pressed).
		// radio_mark.png is overlay with expand 7.
		let radioCut = NineSlice(19, 19, 19, 19);
		let radioExpand = Thickness(7);
		if (radio != null)
		{
			let uncheckedList = new StateListDrawable();
			uncheckedList.SetDefault(new NineSliceDrawable(radio, radioCut, radioExpand));
			if (radioPressed != null)
			{
				let pressedUnchecked = new LayerDrawable();
				pressedUnchecked.AddLayer(new NineSliceDrawable(radio, radioCut, radioExpand));
				pressedUnchecked.AddLayer(new ImageDrawable(radioPressed, radioExpand));
				uncheckedList.SetDrawable(.Pressed, pressedUnchecked);

				let hoverUnchecked = new LayerDrawable();
				hoverUnchecked.AddLayer(new NineSliceDrawable(radio, radioCut, radioExpand));
				hoverUnchecked.AddLayer(new ImageDrawable(radioPressed, radioExpand));
				uncheckedList.SetDrawable(.Hover, hoverUnchecked);
			}
			theme.SetDrawable("RadioButton", "unchecked", uncheckedList);

			if (radioMark != null)
			{
				let checkedList = new StateListDrawable();
				let defaultChecked = new LayerDrawable();
				defaultChecked.AddLayer(new NineSliceDrawable(radio, radioCut, radioExpand));
				defaultChecked.AddLayer(new ImageDrawable(radioMark, radioExpand));
				checkedList.SetDefault(defaultChecked);

				if (radioPressed != null)
				{
					let pressedChecked = new LayerDrawable();
					pressedChecked.AddLayer(new NineSliceDrawable(radio, radioCut, radioExpand));
					pressedChecked.AddLayer(new ImageDrawable(radioPressed, radioExpand));
					pressedChecked.AddLayer(new ImageDrawable(radioMark, radioExpand));
					checkedList.SetDrawable(.Pressed, pressedChecked);

					let hoverChecked = new LayerDrawable();
					hoverChecked.AddLayer(new NineSliceDrawable(radio, radioCut, radioExpand));
					hoverChecked.AddLayer(new ImageDrawable(radioPressed, radioExpand));
					hoverChecked.AddLayer(new ImageDrawable(radioMark, radioExpand));
					checkedList.SetDrawable(.Hover, hoverChecked);
				}
				theme.SetDrawable("RadioButton", "checked", checkedList);
			}
		}

		// === Slider ===
		// TB slider uses slider_bg_x (cut 9, no expand), but we reuse scroll images.
		// No expand for Slider since TB's actual slider images don't have expand.
		let scrollCut = NineSlice(11, 11, 11, 11);
		let scrollExpand = Thickness(5);
		if (scrollBgX != null)
			theme.SetDrawable("Slider", "track", new NineSliceDrawable(scrollBgX, scrollCut));
		if (scrollFgX != null)
			theme.SetDrawable("Slider", "fill", new NineSliceDrawable(scrollFgX, scrollCut));
		if (sliderHandle != null)
			theme.SetDrawable("Slider", "thumb", new ImageDrawable(sliderHandle));

		// === ProgressBar ===
		// Same scroll pill images as Slider and ScrollBar.
		if (scrollBgX != null)
			theme.SetDrawable("ProgressBar", "track", new NineSliceDrawable(scrollBgX, scrollCut));
		if (scrollFgX != null)
			theme.SetDrawable("ProgressBar", "fill", new NineSliceDrawable(scrollFgX, scrollCut));
		theme.SetDimension("ProgressBar", "height", 23);

		// === Panel ===
		if (container != null)
			theme.SetDrawable("Panel", "background", new NineSliceDrawable(container, containerCut, containerExpand));

		// === Separator ===
		if (separatorX != null)
			theme.SetDrawable("Separator", "line", new ImageDrawable(separatorX));
		theme.SetDimension("Separator", "thickness", 2);

		// === EditText ===
		let editFieldCut = NineSlice(12, 12, 12, 12);
		let editFieldExpand = Thickness(4);
		if (editField != null)
			theme.SetDrawable("EditText", "background", new NineSliceDrawable(editField, editFieldCut, editFieldExpand));

		// === ScrollBar ===
		// Scroll images have expand 5 in TB. Logical thickness reduced accordingly.
		if (scrollBgY != null)
			theme.SetDrawable("ScrollBar", "trackVertical", new NineSliceDrawable(scrollBgY, scrollCut, scrollExpand));
		if (scrollFgY != null)
			theme.SetDrawable("ScrollBar", "thumbVertical", new NineSliceDrawable(scrollFgY, scrollCut, scrollExpand));
		if (scrollBgX != null)
			theme.SetDrawable("ScrollBar", "trackHorizontal", new NineSliceDrawable(scrollBgX, scrollCut, scrollExpand));
		if (scrollFgX != null)
			theme.SetDrawable("ScrollBar", "thumbHorizontal", new NineSliceDrawable(scrollFgX, scrollCut, scrollExpand));
		theme.SetDimension("ScrollBar", "thickness", 13);

		// === Focus Indicator ===
		let focusCut = NineSlice(11, 11, 11, 11);
		let focusExpand = Thickness(4);
		if (focusR4 != null)
			theme.SetDrawable("Focus", "indicator", new NineSliceDrawable(focusR4, focusCut, focusExpand));

		// === TreeView ===
		if (arrowDown != null && arrowRight != null)
		{
			theme.SetDrawable("TreeView", "expandedIcon", new ImageDrawable(arrowDown));
			theme.SetDrawable("TreeView", "collapsedIcon", new ImageDrawable(arrowRight));
		}
		else
		{
			theme.SetString("TreeView", "expandedSymbol", "- ");
			theme.SetString("TreeView", "collapsedSymbol", "+ ");
			theme.SetString("TreeView", "leafPrefix", "  ");
		}

		// === Dialog / PopupWindow / ContextMenu (window.png, cut 16, expand 12) ===
		// windowCut and windowExpand defined above
		if (window != null)
		{
			// Dialog uses window_active.png (active/focused look) or window.png as fallback
			if (windowActive != null)
				theme.SetDrawable("Dialog", "background", new NineSliceDrawable(windowActive, windowCut, windowExpand));
			else
				theme.SetDrawable("Dialog", "background", new NineSliceDrawable(window, windowCut, windowExpand));

			// PopupWindow and ContextMenu use window.png (same as TBPopupWindow/TBMenuWindow)
			theme.SetDrawable("PopupWindow", "background", new NineSliceDrawable(window, windowCut, windowExpand));
			theme.SetDrawable("ContextMenu", "background", new NineSliceDrawable(window, windowCut, windowExpand));

			// Tooltip uses window.png too
			theme.SetDrawable("Tooltip", "background", new NineSliceDrawable(window, windowCut, windowExpand));
		}

		// === ContextMenu item highlights (item_hover.png, item_selected.png, cut 7) ===
		let itemCut = NineSlice(7, 7, 7, 7);
		if (itemHover != null)
			theme.SetDrawable("ContextMenu", "itemHover", new NineSliceDrawable(itemHover, itemCut));
		if (itemSelected != null)
			theme.SetDrawable("ContextMenu", "itemSelected", new NineSliceDrawable(itemSelected, itemCut));
		if (arrowRight != null)
			theme.SetDrawable("ContextMenu", "submenuArrow", new ImageDrawable(arrowRight));

		// === Colors ===
		theme.SetColor("Button", "text", p.Text);
		theme.SetColor("ToggleButton", "text", p.Text);
		theme.SetColor("CheckBox", "text", p.Text);
		theme.SetColor("RadioButton", "text", p.Text);
		theme.SetDimension("Button", "cornerRadius", 0);
		theme.SetDimension("ToggleButton", "cornerRadius", 0);

		// Panel fallback colors (used when no drawable or explicit colors set)
		theme.SetColor("Panel", "background", p.Surface);
		theme.SetColor("Panel", "border", p.Border);
		theme.SetColor("Separator", "color", p.Border);

		// Dialog
		theme.SetColor("Dialog", "background", p.Surface);
		theme.SetColor("Dialog", "border", p.Border);
		theme.SetColor("Dialog", "titleText", p.Text);
		theme.SetDimension("Dialog", "cornerRadius", 0);

		// ContextMenu
		theme.SetColor("ContextMenu", "background", p.Surface);
		theme.SetColor("ContextMenu", "border", p.Border);
		theme.SetColor("ContextMenu", "hoverBackground", p.Accent);
		theme.SetColor("ContextMenu", "text", p.Text);
		theme.SetColor("ContextMenu", "disabledText", .(0.45f, 0.45f, 0.5f, 1.0f));
		theme.SetColor("ContextMenu", "separator", .(0.35f, 0.35f, 0.4f, 0.6f));
		theme.SetDimension("ContextMenu", "cornerRadius", 0);

		// PopupWindow
		theme.SetColor("PopupWindow", "background", p.Surface);
		theme.SetColor("PopupWindow", "border", p.Border);
		theme.SetDimension("PopupWindow", "cornerRadius", 0);

		// Tooltip
		theme.SetColor("Tooltip", "background", .(0.12f, 0.12f, 0.15f, 0.95f));
		theme.SetColor("Tooltip", "border", .(0.35f, 0.35f, 0.4f, 0.8f));
		theme.SetColor("Tooltip", "text", p.Text);
		theme.SetDimension("Tooltip", "cornerRadius", 0);

		// ModalBackdrop — TB uses #00000088
		theme.SetColor("ModalBackdrop", "dimColor", .(0.0f, 0.0f, 0.0f, 0.533f));

		// EditText
		theme.SetColor("EditText", "background", .(0.15f, 0.15f, 0.18f, 1.0f));
		theme.SetColor("EditText", "border", p.Border);
		theme.SetColor("EditText", "focusBorder", p.Accent);
		theme.SetColor("EditText", "selection", .(0.3f, 0.55f, 0.9f, 0.4f));
		theme.SetColor("EditText", "cursor", p.Text);
		theme.SetColor("EditText", "hint", .(0.5f, 0.5f, 0.53f, 1.0f));
		theme.SetColor("EditText", "text", p.Text);
		theme.SetDimension("EditText", "cornerRadius", 0);

		// Focus border
		theme.SetColor("Focus", "borderColor", .(0.2f, 0.5f, 0.9f, 0.9f));

		// === Toolkit controls ===

		// TabView — all placements: inactive cut 12 expand 6, active cut 13 expand 6
		let tabInactiveCut = NineSlice(12, 12, 12, 12);
		let tabInactiveExpand = Thickness(6);
		let tabActiveCut = NineSlice(13, 13, 13, 13);
		let tabActiveExpand = Thickness(6);

		// Content background — TBTabContainer.container clones TBContainer (container.png, cut 12, expand 6)
		if (container != null)
			theme.SetDrawable("TabView", "contentBackground", new NineSliceDrawable(container, containerCut, containerExpand));

		// Top
		if (tabTopActive != null)
			theme.SetDrawable("TabView", "activeTabTop", new NineSliceDrawable(tabTopActive, tabActiveCut, tabActiveExpand));
		if (tabTopInactive != null)
			theme.SetDrawable("TabView", "inactiveTabTop", new NineSliceDrawable(tabTopInactive, tabInactiveCut, tabInactiveExpand));
		// Bottom
		if (tabBottomActive != null)
			theme.SetDrawable("TabView", "activeTabBottom", new NineSliceDrawable(tabBottomActive, tabActiveCut, tabActiveExpand));
		if (tabBottomInactive != null)
			theme.SetDrawable("TabView", "inactiveTabBottom", new NineSliceDrawable(tabBottomInactive, tabInactiveCut, tabInactiveExpand));
		// Left
		if (tabLeftActive != null)
			theme.SetDrawable("TabView", "activeTabLeft", new NineSliceDrawable(tabLeftActive, tabActiveCut, tabActiveExpand));
		if (tabLeftInactive != null)
			theme.SetDrawable("TabView", "inactiveTabLeft", new NineSliceDrawable(tabLeftInactive, tabInactiveCut, tabInactiveExpand));
		// Right
		if (tabRightActive != null)
			theme.SetDrawable("TabView", "activeTabRight", new NineSliceDrawable(tabRightActive, tabActiveCut, tabActiveExpand));
		if (tabRightInactive != null)
			theme.SetDrawable("TabView", "inactiveTabRight", new NineSliceDrawable(tabRightInactive, tabInactiveCut, tabInactiveExpand));

		// Expander — use arrow images (same as TreeView)
		if (arrowDown != null && arrowRight != null)
		{
			theme.SetDrawable("Expander", "expandedIcon", new ImageDrawable(arrowDown));
			theme.SetDrawable("Expander", "collapsedIcon", new ImageDrawable(arrowRight));
		}

		// NumberField — arrow_up and arrow_down for spinners
		if (arrowUp != null)
			theme.SetDrawable("NumberField", "spinnerUpIcon", new ImageDrawable(arrowUp));
		if (arrowDown != null)
			theme.SetDrawable("NumberField", "spinnerDownIcon", new ImageDrawable(arrowDown));
		// Reuse editfield for NumberField background
		if (editField != null)
			theme.SetDrawable("NumberField", "spinnerBackground", new NineSliceDrawable(editField, editFieldCut, editFieldExpand));

		// ComboBox — clones TBButton (cut 17, expand 7) with arrow_down
		if (btnNormal != null)
		{
			let comboList = new StateListDrawable();
			comboList.SetDefault(new NineSliceDrawable(btnNormal, btnCut, btnExpand));
			if (btnFlatOutline != null)
				comboList.SetDrawable(.Hover, new NineSliceDrawable(btnFlatOutline, btnFlatCut, btnFlatExpand));
			if (btnPressed != null)
				comboList.SetDrawable(.Pressed, new NineSliceDrawable(btnPressed, btnCut, btnExpand));
			theme.SetDrawable("ComboBox", "background", comboList);
		}
		if (arrowDown != null)
			theme.SetDrawable("ComboBox", "arrowIcon", new ImageDrawable(arrowDown));

		// SplitView
		theme.SetColor("SplitView", "dividerColor", p.Border);
		theme.SetColor("SplitView", "dividerHoverColor", p.Accent);

		// Apply registered extensions (ToolkitThemeExtension sets palette-relative colors)
		Theme.ApplyRegisteredExtensions(theme);

		return theme;
	}
}
