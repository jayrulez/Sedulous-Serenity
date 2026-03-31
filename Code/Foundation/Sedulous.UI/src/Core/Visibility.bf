namespace Sedulous.UI;

/// Controls whether a View is visible and participates in layout.
public enum Visibility
{
	/// View is visible and takes up space in layout.
	Visible,
	/// View is invisible but still takes up space in layout.
	Invisible,
	/// View is invisible and takes up no space in layout.
	Gone
}
