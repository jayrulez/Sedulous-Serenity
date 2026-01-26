using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Base class for layout containers that arrange multiple children.
/// Panels extend CompositeControl which provides children management.
public abstract class Panel : CompositeControl
{
	private Color? mBackground;

	/// Background color for the panel. Null means transparent.
	public Color? Background
	{
		get => mBackground;
		set { mBackground = value; InvalidateVisual(); }
	}

	protected override void OnRender(DrawContext drawContext)
	{
		// Draw background first
		if (mBackground.HasValue)
		{
			drawContext.FillRect(Bounds, mBackground.Value);
		}

		// Let CompositeControl render children
		base.OnRender(drawContext);
	}
}
