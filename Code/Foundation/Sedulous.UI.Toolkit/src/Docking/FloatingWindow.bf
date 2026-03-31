namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// A floating window that wraps a DockablePanel and can be dragged to re-dock.
/// Supports two modes:
/// - OS window mode (mIsOSWindow=true): hosted in a real OS window via IFloatingWindowHost
/// - Virtual mode (mIsOSWindow=false): shown via PopupLayer as a draggable overlay
public class FloatingWindow : ViewGroup, IDockableWindow
{
	private DockablePanel mPanel;
	private float mTitleBarHeight = 24;
	private bool mIsOSWindow;

	private EventAccessor<delegate void(FloatingWindow)> mOnDockRequested = new .() ~ delete _;
	private EventAccessor<delegate void(FloatingWindow)> mOnCloseRequested = new .() ~ delete _;

	/// Fired when the user double-clicks the title bar to re-dock.
	public EventAccessor<delegate void(FloatingWindow)> OnDockRequested => mOnDockRequested;

	/// Fired when the user clicks the close button or the OS window is closed.
	public EventAccessor<delegate void(FloatingWindow)> OnCloseRequested => mOnCloseRequested;

	/// The panel contained in this floating window.
	public DockablePanel Panel => mPanel;

	/// Whether this floating window is hosted in a real OS window.
	public bool IsOSWindow => mIsOSWindow;

	public this(DockablePanel panel)
	{
		mPanel = panel;
		if (panel != null)
			AddView(panel);

		MinWidth = 120;
		MinHeight = 80;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(250, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(200, MinHeight, MaxHeight);

		if (mPanel != null)
		{
			if (mIsOSWindow)
			{
				// OS window: panel fills the entire window (OS chrome provides title bar)
				mPanel.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(h));
			}
			else
			{
				// Virtual: panel fills everything (title bar is part of the panel's own header)
				mPanel.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(h));
			}
		}

		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		if (mPanel != null)
			mPanel.Layout(0, 0, width, height);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		if (!mIsOSWindow)
		{
			// Virtual mode: draw border
			let borderColor = theme?.GetColor("FloatingWindow", "border") ?? palette.Border;
			ctx.FillRoundedRect(.(0, 0, Width, Height), 4, palette.Surface);
			ctx.DrawBorderRect(.(0, 0, Width, Height), borderColor, 2);
		}

		// Draw content
		if (mPanel != null)
			mPanel.Draw(ctx);
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left) return;

		// Title bar area: double-click to re-dock
		if (e.LocalY < mTitleBarHeight)
		{
			if (e.ClickCount >= 2)
			{
				mOnDockRequested.[Friend]Invoke(this);
				e.Handled = true;
				return;
			}
		}
	}

	/// Detach and return the panel. Caller takes ownership.
	public DockablePanel DetachPanel()
	{
		let panel = mPanel;
		if (panel != null)
		{
			DetachView(panel);
			mPanel = null;
		}
		return panel;
	}
}
