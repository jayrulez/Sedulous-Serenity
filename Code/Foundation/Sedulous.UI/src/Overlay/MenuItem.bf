namespace Sedulous.UI;

using System;

/// Data model for a context menu item.
struct MenuItem : IDisposable
{
	/// Display text for the item.
	public String Label;

	/// Action fired when the item is clicked. Owned by ContextMenu.
	public delegate void() Action;

	/// Whether the item is enabled.
	public bool Enabled;

	/// Whether this entry is a separator line.
	public bool IsSeparator;

	/// Optional nested submenu. Owned by MenuItem.
	public ContextMenu Submenu;

	public void Dispose() mut
	{
		delete Label;
		delete Action;
		delete Submenu;
	}
}
