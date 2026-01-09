namespace Sedulous.UI;

/// Specifies where a panel can be docked.
public enum DockZone
{
	/// Not docked.
	None,
	/// Docked to the left edge.
	Left,
	/// Docked to the right edge.
	Right,
	/// Docked to the top edge.
	Top,
	/// Docked to the bottom edge.
	Bottom,
	/// Docked in the center (main content area).
	Center,
	/// Floating as a separate window.
	Float
}
