namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Overlay drawn during dock drag operations showing zone indicators (T/B/L/R/Center).
public class DockZoneIndicator : View
{
	private List<DockTarget> mTargets = new .() ~ delete _;
	private int mHoveredTarget = -1;

	public this()
	{
		IsHitTestVisible = false; // Transparent to hit-testing
	}

	/// Set the available dock targets.
	public void SetTargets(List<DockTarget> targets)
	{
		mTargets.Clear();
		for (let t in targets)
			mTargets.Add(t);
		Invalidate();
	}

	/// Clear all targets.
	public void ClearTargets()
	{
		mTargets.Clear();
		mHoveredTarget = -1;
		Invalidate();
	}

	/// Get the hovered dock target given screen coordinates.
	public DockTarget? GetHoveredTarget(float localX, float localY)
	{
		for (int i = 0; i < mTargets.Count; i++)
		{
			let t = mTargets[i];
			if (localX >= t.ZoneBounds.X && localX < t.ZoneBounds.X + t.ZoneBounds.Width &&
				localY >= t.ZoneBounds.Y && localY < t.ZoneBounds.Y + t.ZoneBounds.Height)
			{
				mHoveredTarget = i;
				return t;
			}
		}
		mHoveredTarget = -1;
		return null;
	}

	/// Update hover state from local coordinates.
	public void UpdateHover(float localX, float localY)
	{
		int prev = mHoveredTarget;
		GetHoveredTarget(localX, localY);
		if (prev != mHoveredTarget)
			Invalidate();
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		let indicatorColor = theme?.GetColor("DockZone", "indicatorColor") ?? Palette.WithAlpha(palette.Accent, 80);
		let hoverColor = theme?.GetColor("DockZone", "hoverColor") ?? Palette.WithAlpha(palette.Accent, 160);

		for (int i = 0; i < mTargets.Count; i++)
		{
			let t = mTargets[i];
			let color = (i == mHoveredTarget) ? hoverColor : indicatorColor;
			ctx.FillRoundedRect(t.ZoneBounds, 4, color);

			// Draw direction arrow
			DrawArrow(ctx, t.Position, t.ZoneBounds, Palette.WithAlpha(palette.Text, 200));
		}
	}

	private void DrawArrow(DrawContext ctx, DockPosition pos, RectangleF bounds, Color color)
	{
		float cx = bounds.X + bounds.Width * 0.5f;
		float cy = bounds.Y + bounds.Height * 0.5f;
		float s = Math.Min(bounds.Width, bounds.Height) * 0.25f;

		switch (pos)
		{
		case .Top:
			Vector2[3] tri = .(.(cx, cy - s), .(cx - s, cy + s * 0.5f), .(cx + s, cy + s * 0.5f));
			ctx.FillPolygon(tri, color);
		case .Bottom:
			Vector2[3] tri = .(.(cx, cy + s), .(cx - s, cy - s * 0.5f), .(cx + s, cy - s * 0.5f));
			ctx.FillPolygon(tri, color);
		case .Left:
			Vector2[3] tri = .(.(cx - s, cy), .(cx + s * 0.5f, cy - s), .(cx + s * 0.5f, cy + s));
			ctx.FillPolygon(tri, color);
		case .Right:
			Vector2[3] tri = .(.(cx + s, cy), .(cx - s * 0.5f, cy - s), .(cx - s * 0.5f, cy + s));
			ctx.FillPolygon(tri, color);
		case .Center:
			ctx.FillRect(.(cx - s * 0.5f, cy - s * 0.5f, s, s), color);
		case .Float:
			break;
		}
	}
}
