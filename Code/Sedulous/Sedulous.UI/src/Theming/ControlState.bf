using System;

namespace Sedulous.UI;

/// Flags representing the visual state of a control.
public enum ControlState
{
	/// Normal state with no special conditions.
	Normal = 0,
	/// Control is disabled and cannot be interacted with.
	Disabled = 1,
	/// Control has keyboard focus.
	Focused = 2,
	/// Mouse is over the control.
	Hovered = 4,
	/// Control is being pressed (mouse down).
	Pressed = 8,
	/// Control is selected (for selectable items).
	Selected = 16,
	/// Control is checked (for toggle controls).
	Checked = 32
}
