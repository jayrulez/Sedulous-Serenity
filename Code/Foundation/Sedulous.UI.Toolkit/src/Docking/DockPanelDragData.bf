namespace Sedulous.UI.Toolkit;

using Sedulous.UI;

/// Drag data carrying a reference to a DockablePanel being dragged.
public class DockPanelDragData : DragData
{
	public DockablePanel Panel;

	public this(DockablePanel panel) : base("dock/panel")
	{
		Panel = panel;
	}
}
