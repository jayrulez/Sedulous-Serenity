namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;

/// Factory for a light theme.
public static class LightTheme
{
	public static Theme Create()
	{
		let theme = new Theme();
		theme.Name = new String("Light");
		theme.Palette = Palette.Light;

		let p = theme.Palette;

		// Button
		theme.SetColor("Button", "background", p.Primary);
		theme.SetColor("Button", "text", p.Text);
		theme.SetDimension("Button", "cornerRadius", 4);

		// ToggleButton
		theme.SetColor("ToggleButton", "background", p.Primary);
		theme.SetColor("ToggleButton", "checkedBackground", p.Accent);
		theme.SetColor("ToggleButton", "text", p.Text);
		theme.SetDimension("ToggleButton", "cornerRadius", 4);

		// CheckBox
		theme.SetColor("CheckBox", "boxBackground", .(0.92f, 0.92f, 0.94f, 1.0f));
		theme.SetColor("CheckBox", "boxBorder", p.Border);
		theme.SetColor("CheckBox", "checkColor", p.Accent);
		theme.SetColor("CheckBox", "text", p.Text);
		theme.SetDimension("CheckBox", "cornerRadius", 3);

		// RadioButton
		theme.SetColor("RadioButton", "circleBackground", .(0.92f, 0.92f, 0.94f, 1.0f));
		theme.SetColor("RadioButton", "circleBorder", p.Border);
		theme.SetColor("RadioButton", "dotColor", p.Accent);
		theme.SetColor("RadioButton", "text", p.Text);

		// Slider
		theme.SetColor("Slider", "track", .(0.8f, 0.8f, 0.82f, 1.0f));
		theme.SetColor("Slider", "fill", p.Accent);
		theme.SetColor("Slider", "thumb", .(0.3f, 0.3f, 0.35f, 1.0f));
		theme.SetColor("Slider", "thumbHover", .(0.15f, 0.15f, 0.2f, 1.0f));

		// ProgressBar
		theme.SetColor("ProgressBar", "track", .(0.8f, 0.8f, 0.82f, 1.0f));
		theme.SetColor("ProgressBar", "fill", p.Accent);
		theme.SetDimension("ProgressBar", "height", 6);

		// Panel
		theme.SetColor("Panel", "background", p.Surface);
		theme.SetColor("Panel", "border", p.Border);

		// Separator
		theme.SetColor("Separator", "color", p.Border);

		// EditText
		theme.SetColor("EditText", "background", .(1.0f, 1.0f, 1.0f, 1.0f));
		theme.SetColor("EditText", "border", p.Border);
		theme.SetColor("EditText", "focusBorder", p.Accent);
		theme.SetColor("EditText", "selection", .(0.2f, 0.4f, 0.8f, 0.3f));
		theme.SetColor("EditText", "cursor", p.Text);
		theme.SetColor("EditText", "hint", .(0.6f, 0.6f, 0.65f, 1.0f));
		theme.SetColor("EditText", "text", p.Text);
		theme.SetDimension("EditText", "cornerRadius", 4);

		// ScrollBar
		theme.SetColor("ScrollBar", "track", .(0.85f, 0.85f, 0.9f, 0.5f));
		theme.SetColor("ScrollBar", "thumb", .(0.6f, 0.6f, 0.65f, 0.8f));
		theme.SetColor("ScrollBar", "thumbHover", .(0.5f, 0.5f, 0.55f, 0.9f));
		theme.SetColor("ScrollBar", "thumbDrag", .(0.4f, 0.4f, 0.45f, 1.0f));

		// Focus
		theme.SetColor("Focus", "borderColor", .(0.2f, 0.4f, 0.8f, 0.7f));

		// Dialog
		theme.SetColor("Dialog", "background", .(0.97f, 0.97f, 0.98f, 1.0f));
		theme.SetColor("Dialog", "border", p.Border);
		theme.SetColor("Dialog", "titleText", p.Text);
		theme.SetDimension("Dialog", "cornerRadius", 8);

		// ContextMenu
		theme.SetColor("ContextMenu", "background", .(0.97f, 0.97f, 0.98f, 0.98f));
		theme.SetColor("ContextMenu", "border", p.Border);
		theme.SetColor("ContextMenu", "hoverBackground", p.Accent);
		theme.SetColor("ContextMenu", "text", p.Text);
		theme.SetColor("ContextMenu", "disabledText", .(0.6f, 0.6f, 0.65f, 1.0f));
		theme.SetColor("ContextMenu", "separator", .(0.75f, 0.75f, 0.8f, 0.6f));
		theme.SetDimension("ContextMenu", "cornerRadius", 4);

		// PopupWindow
		theme.SetColor("PopupWindow", "background", .(0.97f, 0.97f, 0.98f, 0.98f));
		theme.SetColor("PopupWindow", "border", p.Border);
		theme.SetDimension("PopupWindow", "cornerRadius", 4);

		// Tooltip
		theme.SetColor("Tooltip", "background", .(0.2f, 0.2f, 0.25f, 0.95f));
		theme.SetColor("Tooltip", "border", .(0.4f, 0.4f, 0.45f, 0.8f));
		theme.SetColor("Tooltip", "text", .(1.0f, 1.0f, 1.0f, 1.0f));
		theme.SetDimension("Tooltip", "cornerRadius", 3);

		// ModalBackdrop
		theme.SetColor("ModalBackdrop", "dimColor", .(0.0f, 0.0f, 0.0f, 0.3f));

		// TreeView
		theme.SetString("TreeView", "expandedSymbol", "- ");
		theme.SetString("TreeView", "collapsedSymbol", "+ ");
		theme.SetString("TreeView", "leafPrefix", "  ");

		// Apply registered extensions from external libraries
		Theme.ApplyRegisteredExtensions(theme);

		return theme;
	}
}
