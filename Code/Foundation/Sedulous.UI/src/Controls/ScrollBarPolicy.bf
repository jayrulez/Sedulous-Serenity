namespace Sedulous.UI;

/// Controls when a scrollbar is displayed.
public enum ScrollBarPolicy
{
	/// Never show the scrollbar. Scroll via wheel/drag only.
	Never,
	/// Show the scrollbar only when content exceeds viewport.
	Auto,
	/// Always show the scrollbar, even when content fits.
	Always
}
