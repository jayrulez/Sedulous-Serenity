namespace Sedulous.UI;

/// Defines how a popup is positioned relative to its anchor.
public enum PopupPlacement
{
	/// Position below the anchor, aligned to left edge.
	Bottom,
	/// Position below the anchor, centered.
	BottomCenter,
	/// Position above the anchor, aligned to left edge.
	Top,
	/// Position above the anchor, centered.
	TopCenter,
	/// Position to the right of the anchor.
	Right,
	/// Position to the left of the anchor.
	Left,
	/// Position at the mouse cursor location.
	Mouse,
	/// Position at absolute coordinates (use HorizontalOffset/VerticalOffset).
	Absolute,
	/// Position centered in the viewport (for dialogs).
	Center
}

/// Options for popup behavior.
public enum PopupBehavior
{
	/// Close when clicking outside the popup.
	CloseOnClickOutside = 1,
	/// Close when pressing Escape.
	CloseOnEscape = 2,
	/// Close when the anchor loses focus.
	CloseOnAnchorLostFocus = 4,
	/// Block input to elements below (modal).
	Modal = 8,
	/// Show a dimmed overlay behind the popup (requires Modal).
	DimBackground = 16,

	/// Default behavior for popups (close on click outside and escape).
	Default = CloseOnClickOutside | CloseOnEscape,
	/// Default behavior for modal dialogs.
	ModalDialog = Modal | DimBackground | CloseOnEscape
}
