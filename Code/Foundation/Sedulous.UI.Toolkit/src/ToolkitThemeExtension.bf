namespace Sedulous.UI.Toolkit;

using Sedulous.UI;
using Sedulous.Core.Mathematics;

/// Theme extension that registers default colors for all toolkit controls.
/// Uses palette-relative colors so it works for both dark and light themes.
public class ToolkitThemeExtension : IThemeExtension
{
	public void ApplyDefaults(Theme theme)
	{
		let p = theme.Palette;

		// TabView
		theme.SetColor("TabView", "tabBackground", Palette.Darken(p.Surface, 0.15f));
		theme.SetColor("TabView", "activeTabBackground", p.Surface);
		theme.SetColor("TabView", "activeTabText", p.Text);
		theme.SetColor("TabView", "inactiveTabText", Palette.WithAlpha(p.Text, 153));
		theme.SetColor("TabView", "tabBorder", p.Border);
		theme.SetColor("TabView", "contentBackground", p.Surface);

		// SplitView
		theme.SetColor("SplitView", "dividerColor", p.Border);
		theme.SetColor("SplitView", "dividerHoverColor", p.Accent);
		theme.SetDimension("SplitView", "dividerSize", 6);

		// ComboBox
		theme.SetColor("ComboBox", "background", Palette.Darken(p.Surface, 0.1f));
		theme.SetColor("ComboBox", "border", p.Border);
		theme.SetColor("ComboBox", "text", p.Text);
		theme.SetColor("ComboBox", "arrowColor", p.Text);
		theme.SetDimension("ComboBox", "cornerRadius", 4);

		// NumberField
		theme.SetColor("NumberField", "spinnerBackground", Palette.Darken(p.Surface, 0.05f));
		theme.SetColor("NumberField", "spinnerArrow", p.Text);
		theme.SetColor("NumberField", "spinnerBorder", p.Border);

		// Toolbar
		theme.SetColor("Toolbar", "background", Palette.Darken(p.Surface, 0.1f));
		theme.SetColor("Toolbar", "border", p.Border);

		// StatusBar
		theme.SetColor("StatusBar", "background", Palette.Darken(p.Surface, 0.15f));
		theme.SetColor("StatusBar", "borderColor", p.Border);
		theme.SetColor("StatusBar", "text", Palette.WithAlpha(p.Text, 204));

		// Expander
		theme.SetColor("Expander", "headerBackground", Palette.Darken(p.Surface, 0.1f));
		theme.SetColor("Expander", "headerHoverBackground", Palette.Darken(p.Surface, 0.05f));
		theme.SetColor("Expander", "headerText", p.Text);
		theme.SetColor("Expander", "indicator", p.Accent);
		theme.SetColor("Expander", "contentBackground", p.Surface);

		// Breadcrumb
		theme.SetColor("Breadcrumb", "text", p.Text);
		theme.SetColor("Breadcrumb", "hoverText", p.Accent);
		theme.SetColor("Breadcrumb", "separator", Palette.WithAlpha(p.Text, 128));
		theme.SetColor("Breadcrumb", "background", Color(0, 0, 0, 0));
		theme.SetColor("Breadcrumb", "hoverBackground", Palette.WithAlpha(p.Accent, 30));

		// LogView
		theme.SetColor("LogView", "background", Palette.Darken(p.Surface, 0.1f));
		theme.SetColor("LogView", "debugColor", Color(0.6f, 0.6f, 0.6f, 1.0f));
		theme.SetColor("LogView", "infoColor", Color(0.3f, 0.7f, 1.0f, 1.0f));
		theme.SetColor("LogView", "warningColor", p.Warning);
		theme.SetColor("LogView", "errorColor", p.Error);

		// ColorPicker
		theme.SetColor("ColorPicker", "background", p.Surface);
		theme.SetColor("ColorPicker", "border", p.Border);
		theme.SetColor("ColorPicker", "indicatorColor", p.Text);

		// PropertyGrid
		theme.SetColor("PropertyGrid", "background", p.Surface);
		theme.SetColor("PropertyGrid", "labelColor", p.Text);
		theme.SetColor("PropertyGrid", "categoryBackground", Palette.Darken(p.Surface, 0.08f));
		theme.SetColor("PropertyGrid", "divider", p.Border);
		theme.SetColor("PropertyGrid", "rowBackground", p.Surface);
		theme.SetColor("PropertyGrid", "rowAltBackground", Palette.Darken(p.Surface, 0.03f));

		// DraggableTreeView
		theme.SetColor("DraggableTreeView", "dropIndicator", p.Accent);

		// DockManager
		theme.SetColor("DockManager", "background", Palette.Darken(p.Background, 0.05f));

		// DockTabGroup
		theme.SetColor("DockTabGroup", "tabBackground", Palette.Darken(p.Surface, 0.15f));
		theme.SetColor("DockTabGroup", "activeTabBackground", p.Surface);
		theme.SetColor("DockTabGroup", "tabText", p.Text);

		// DockSplit
		theme.SetColor("DockSplit", "dividerColor", p.Border);
		theme.SetColor("DockSplit", "dividerHoverColor", p.Accent);

		// DockZone
		theme.SetColor("DockZone", "indicatorColor", Palette.WithAlpha(p.Accent, 80));
		theme.SetColor("DockZone", "hoverColor", Palette.WithAlpha(p.Accent, 160));

		// DockablePanel
		theme.SetColor("DockablePanel", "headerBackground", Palette.Darken(p.Surface, 0.2f));
		theme.SetColor("DockablePanel", "headerText", p.Text);
		theme.SetColor("DockablePanel", "contentBackground", p.Surface);

		// FloatingWindow
		theme.SetColor("FloatingWindow", "border", p.Border);

		// MenuBar
		theme.SetColor("MenuBar", "background", Palette.Darken(p.Surface, 0.05f));
		theme.SetColor("MenuBar", "itemHover", Palette.Lighten(p.Surface, 0.1f));
		theme.SetColor("MenuBar", "text", p.Text);
		theme.SetColor("MenuBar", "border", p.Border);
	}
}
