namespace Sedulous.UI;

/// Interface for views that own a popup. Notified when the popup is closed.
public interface IPopupOwner
{
	/// Called when a popup owned by this object is closed.
	void OnPopupClosed(View popup);
}
