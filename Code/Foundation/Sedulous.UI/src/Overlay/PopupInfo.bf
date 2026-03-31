namespace Sedulous.UI;

/// Tracks metadata for an active popup in the PopupLayer.
struct PopupInfo
{
	/// The popup view (owned by PopupLayer).
	public View Popup;

	/// Optional owner, notified on close.
	public IPopupOwner Owner;

	/// Whether clicking outside this popup should close it.
	public bool CloseOnClickOutside;

	/// Whether this popup is modal (blocks input below).
	public bool IsModal;
}
