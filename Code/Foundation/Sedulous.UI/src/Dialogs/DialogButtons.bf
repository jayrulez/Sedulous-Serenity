namespace Sedulous.UI;

/// Flags indicating which buttons to show in a dialog.
//[Flags]
public enum DialogButtons
{
	/// No buttons.
	None = 0,
	/// Show OK button.
	OK = 1,
	/// Show Cancel button.
	Cancel = 2,
	/// Show Yes button.
	Yes = 4,
	/// Show No button.
	No = 8,

	/// OK and Cancel buttons.
	OKCancel = OK | Cancel,
	/// Yes and No buttons.
	YesNo = Yes | No,
	/// Yes, No, and Cancel buttons.
	YesNoCancel = Yes | No | Cancel
}
