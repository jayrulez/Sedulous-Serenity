using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Base class for layout containers that arrange multiple children.
public abstract class Panel : UIElement
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
		if (mBackground.HasValue)
		{
			drawContext.FillRect(Bounds, mBackground.Value);
		}
	}
}
