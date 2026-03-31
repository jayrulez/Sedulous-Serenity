namespace Sedulous.UI;

/// Visual state of a control, used for theming and state-based styling.
/// Priority order: Disabled > Pressed > Focused > Hover > Normal.
public enum ControlState
{
	Normal,
	Hover,
	Pressed,
	Disabled,
	Focused
}
