namespace Sedulous.UI;

/// Cursor types that UI elements can request.
public enum CursorType
{
	/// Default arrow cursor.
	Default,
	/// Text selection cursor (I-beam).
	Text,
	/// Wait/busy cursor.
	Wait,
	/// Crosshair cursor.
	Crosshair,
	/// Progress cursor (busy but interactive).
	Progress,
	/// Move cursor (four arrows).
	Move,
	/// Not allowed cursor.
	NotAllowed,
	/// Pointer/hand cursor (for clickable elements).
	Pointer,
	/// Horizontal resize cursor.
	ResizeEW,
	/// Vertical resize cursor.
	ResizeNS,
	/// Diagonal resize cursor (NW-SE).
	ResizeNWSE,
	/// Diagonal resize cursor (NE-SW).
	ResizeNESW
}
