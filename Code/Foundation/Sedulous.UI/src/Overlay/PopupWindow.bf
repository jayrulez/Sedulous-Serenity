namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// A generic popup container that wraps any view.
/// Used for dropdowns, autocomplete, and other anchored popups.
public class PopupWindow : FrameLayout
{
	/// The content view, or null.
	public View Content => (ChildCount > 0) ? GetChildAt(0) : null;

	public this()
	{
		CornerRadius = 4;
	}

	/// Corner radius for the popup background.
	public float CornerRadius = 4;

	/// Set the content view. PopupWindow takes ownership via AddView.
	public void SetContent(View content)
	{
		RemoveAllViews();
		if (content != null)
		{
			AddView(content, new LayoutParams(
				Sedulous.UI.LayoutParams.MatchParent,
				Sedulous.UI.LayoutParams.MatchParent
			));
		}
	}

	/// Close this popup via the UIContext.
	public void Dismiss()
	{
		let ctx = Context;
		let self = this;
		ctx?.MutationQueue.QueueAction(new () => {
			ctx.ClosePopup(self);
		});
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;

		// Draw background — try drawable first, then color fallback
		let bgDrawable = theme?.GetDrawable("PopupWindow", "background");
		if (bgDrawable != null)
		{
			bgDrawable.Draw(ctx, .(0, 0, Width, Height));
		}
		else
		{
			Color bgColor = theme?.GetColor("PopupWindow", "background") ?? Color(60, 60, 60, 240);
			Color borderColor = theme?.GetColor("PopupWindow", "border") ?? Color(100, 100, 100, 200);
			float cr = theme?.GetDimension("PopupWindow", "cornerRadius") ?? CornerRadius;

			if (cr > 0)
			{
				ctx.FillRoundedRect(.(0, 0, Width, Height), cr, bgColor);
				ctx.DrawBorderRoundedRect(.(0, 0, Width, Height), cr, borderColor, 1);
			}
			else
			{
				ctx.FillRect(.(0, 0, Width, Height), bgColor);
				ctx.DrawBorderRect(.(0, 0, Width, Height), borderColor, 1);
			}
		}

		// Draw children
		base.OnDraw(ctx);
	}

	/// Show this popup anchored below a view.
	public void ShowAsDropDown(View anchor)
	{
		if (anchor == null || anchor.Context == null) return;

		let ctx = anchor.Context;

		// Get anchor bounds in screen coordinates
		let screenPos = anchor.ToScreen(.Zero);
		let anchorBounds = RectangleF(screenPos.X, screenPos.Y, anchor.Width, anchor.Height);

		// Measure popup
		Measure(
			MeasureSpec.MakeAtMost(ctx.Width / ctx.DpiScale),
			MeasureSpec.MakeAtMost(ctx.Height / ctx.DpiScale)
		);

		let pos = PopupPositioner.PositionBestFit(
			MeasuredWidth, MeasuredHeight,
			anchorBounds,
			ctx.Width / ctx.DpiScale,
			ctx.Height / ctx.DpiScale
		);

		ctx.ShowPopup(this, null, pos.X, pos.Y);
	}
}
