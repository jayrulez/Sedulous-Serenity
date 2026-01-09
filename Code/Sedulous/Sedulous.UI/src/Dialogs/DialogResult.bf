namespace Sedulous.UI;

/// Result returned by a dialog when it closes.
public enum DialogResult
{
	/// Dialog was closed without a result.
	None,
	/// User clicked OK.
	OK,
	/// User clicked Cancel or closed the dialog.
	Cancel,
	/// User clicked Yes.
	Yes,
	/// User clicked No.
	No
}
