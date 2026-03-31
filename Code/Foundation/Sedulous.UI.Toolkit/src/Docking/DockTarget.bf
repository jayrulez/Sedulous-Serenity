namespace Sedulous.UI.Toolkit;

using Sedulous.UI;
using Sedulous.Core.Mathematics;

/// Describes a dock zone target: a position, the node to dock relative to, and the zone bounds.
public struct DockTarget
{
	public DockPosition Position;
	public View TargetNode;
	public RectangleF ZoneBounds;

	public this(DockPosition position, View targetNode, RectangleF bounds)
	{
		Position = position;
		TargetNode = targetNode;
		ZoneBounds = bounds;
	}
}
