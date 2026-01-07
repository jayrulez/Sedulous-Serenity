using System;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// Horizontal alignment of a widget within its parent.
enum HorizontalAlignment
{
	/// Align to the left edge.
	Left,
	/// Center horizontally.
	Center,
	/// Align to the right edge.
	Right,
	/// Stretch to fill available width.
	Stretch
}

/// Vertical alignment of a widget within its parent.
enum VerticalAlignment
{
	/// Align to the top edge.
	Top,
	/// Center vertically.
	Center,
	/// Align to the bottom edge.
	Bottom,
	/// Stretch to fill available height.
	Stretch
}

/// Visibility state of a widget.
enum Visibility
{
	/// Widget is visible and participates in layout.
	Visible,
	/// Widget is invisible but still participates in layout.
	Hidden,
	/// Widget is invisible and does not participate in layout.
	Collapsed
}

/// Direction of layout for panels.
enum Orientation
{
	/// Layout children horizontally.
	Horizontal,
	/// Layout children vertically.
	Vertical
}

/// Focus navigation direction.
enum FocusDirection
{
	/// Move to next focusable widget.
	Next,
	/// Move to previous focusable widget.
	Previous,
	/// Move focus up.
	Up,
	/// Move focus down.
	Down,
	/// Move focus left.
	Left,
	/// Move focus right.
	Right
}

/// Docking position for dock panels.
enum Dock
{
	/// Dock to the left edge.
	Left,
	/// Dock to the top edge.
	Top,
	/// Dock to the right edge.
	Right,
	/// Dock to the bottom edge.
	Bottom
}

/// Text alignment within bounds.
enum TextAlignment
{
	/// Align text to the left/top.
	Start,
	/// Center text.
	Center,
	/// Align text to the right/bottom.
	End
}

/// Text wrapping behavior.
enum TextWrapping
{
	/// No wrapping, text may overflow.
	NoWrap,
	/// Wrap text at word boundaries.
	Wrap,
	/// Wrap text at character boundaries.
	WrapWithOverflow
}

/// Text trimming behavior when text overflows.
enum TextTrimming
{
	/// No trimming.
	None,
	/// Trim at character boundary with ellipsis.
	CharacterEllipsis,
	/// Trim at word boundary with ellipsis.
	WordEllipsis
}

/// Image stretch mode.
enum Stretch
{
	/// No stretching, image is displayed at original size.
	None,
	/// Scale uniformly to fill bounds, may crop.
	Fill,
	/// Scale uniformly to fit within bounds.
	Uniform,
	/// Scale uniformly to fill bounds completely.
	UniformToFill
}

/// Selection mode for list controls.
enum SelectionMode
{
	/// No selection allowed.
	None,
	/// Single item selection.
	Single,
	/// Multiple item selection.
	Multiple,
	/// Extended selection (with Shift/Ctrl modifiers).
	Extended
}

/// Scrollbar visibility mode.
enum ScrollBarVisibility
{
	/// Scrollbar is always hidden.
	Disabled,
	/// Scrollbar is shown automatically when needed.
	Auto,
	/// Scrollbar is always visible.
	Visible,
	/// Scrollbar is always hidden but scrolling is enabled.
	Hidden
}

/// Expander direction.
enum ExpandDirection
{
	/// Expand downward.
	Down,
	/// Expand upward.
	Up,
	/// Expand to the left.
	Left,
	/// Expand to the right.
	Right
}

/// Popup placement mode.
enum Placement
{
	/// Place relative to the target element.
	Relative,
	/// Place at absolute screen position.
	Absolute,
	/// Place at the mouse position.
	Mouse,
	/// Place at the bottom of the target.
	Bottom,
	/// Place at the top of the target.
	Top,
	/// Place at the left of the target.
	Left,
	/// Place at the right of the target.
	Right
}

/// Dialog result values.
enum DialogResult
{
	/// No result.
	None,
	/// OK button was pressed.
	OK,
	/// Cancel button was pressed.
	Cancel,
	/// Yes button was pressed.
	Yes,
	/// No button was pressed.
	No
}

/// Mouse button identifiers.
enum MouseButton
{
	/// Left mouse button.
	Left,
	/// Right mouse button.
	Right,
	/// Middle mouse button.
	Middle,
	/// Extra button 1.
	XButton1,
	/// Extra button 2.
	XButton2
}

/// Key modifier flags.
[Flags]
enum KeyModifiers
{
	/// No modifiers.
	None = 0,
	/// Shift key is pressed.
	Shift = 1,
	/// Control key is pressed.
	Control = 2,
	/// Alt key is pressed.
	Alt = 4,
	/// Super/Windows key is pressed.
	Super = 8
}

/// Cursor types.
enum CursorType
{
	/// Default arrow cursor.
	Arrow,
	/// Text input cursor (I-beam).
	IBeam,
	/// Wait/busy cursor.
	Wait,
	/// Crosshair cursor.
	Crosshair,
	/// Hand/pointer cursor.
	Hand,
	/// Horizontal resize cursor.
	SizeWE,
	/// Vertical resize cursor.
	SizeNS,
	/// Diagonal resize cursor (NW-SE).
	SizeNWSE,
	/// Diagonal resize cursor (NE-SW).
	SizeNESW,
	/// Move cursor.
	SizeAll,
	/// Not allowed cursor.
	NotAllowed
}
