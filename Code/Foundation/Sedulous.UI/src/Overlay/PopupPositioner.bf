namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;

/// Static helper for viewport-aware popup positioning.
public static class PopupPositioner
{
	/// Position a popup below an anchor rect. If it clips the bottom, flip above.
	/// Clamps horizontally to viewport edges. Returns the computed (x, y) position.
	public static Vector2 PositionBestFit(float popupW, float popupH, RectangleF anchorBounds, float viewportW, float viewportH)
	{
		float x = anchorBounds.X;
		float y = anchorBounds.Y + anchorBounds.Height;

		// If it clips the bottom, flip above
		if (y + popupH > viewportH)
		{
			float aboveY = anchorBounds.Y - popupH;
			if (aboveY >= 0)
				y = aboveY;
			// else: keep below (less bad than going off top)
		}

		// Clamp horizontally
		if (x + popupW > viewportW)
			x = viewportW - popupW;
		if (x < 0)
			x = 0;

		// Clamp vertically
		if (y + popupH > viewportH)
			y = viewportH - popupH;
		if (y < 0)
			y = 0;

		return .(x, y);
	}

	/// Position a popup directly below an anchor rect, left-aligned.
	public static Vector2 PositionBelow(float popupW, float popupH, RectangleF anchorBounds, float viewportW, float viewportH)
	{
		float x = anchorBounds.X;
		float y = anchorBounds.Y + anchorBounds.Height;

		// Clamp to viewport
		if (x + popupW > viewportW)
			x = viewportW - popupW;
		if (x < 0)
			x = 0;
		if (y + popupH > viewportH)
			y = viewportH - popupH;
		if (y < 0)
			y = 0;

		return .(x, y);
	}

	/// Position a submenu to the right of a parent menu item. Flips left if it clips.
	public static Vector2 PositionSubmenu(float popupW, float popupH, RectangleF parentItemBounds, float viewportW, float viewportH)
	{
		float x = parentItemBounds.X + parentItemBounds.Width;
		float y = parentItemBounds.Y;

		// If clips right edge, flip to left of parent
		if (x + popupW > viewportW)
		{
			float leftX = parentItemBounds.X - popupW;
			if (leftX >= 0)
				x = leftX;
			// else: keep right (less bad than going off left)
		}

		// Clamp vertically
		if (y + popupH > viewportH)
			y = viewportH - popupH;
		if (y < 0)
			y = 0;

		return .(x, y);
	}

	/// Position a popup above an anchor rect, left-aligned.
	public static Vector2 PositionAbove(float popupW, float popupH, RectangleF anchorBounds, float viewportW, float viewportH)
	{
		float x = anchorBounds.X;
		float y = anchorBounds.Y - popupH;

		// Clamp to viewport
		if (x + popupW > viewportW)
			x = viewportW - popupW;
		if (x < 0)
			x = 0;
		if (y < 0)
			y = 0;
		if (y + popupH > viewportH)
			y = viewportH - popupH;

		return .(x, y);
	}
}
