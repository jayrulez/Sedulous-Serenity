namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;

/// Manages tooltip display with hover delay.
/// Ticked by UIContext each frame. InputManager notifies on hover changes.
public class TooltipManager
{
	private UIContext mContext;
	private TooltipView mTooltipView;
	private View mCurrentTarget;
	private float mHoverTime;
	private bool mIsShowing;
	private float mLastMouseX;
	private float mLastMouseY;
	private PopupLayer mTooltipPopupLayer; // Tracks which PopupLayer the tooltip was shown on

	/// Delay in seconds before showing a tooltip. Default 0.5s.
	public float ShowDelay = 0.5f;

	/// Vertical offset below the cursor for tooltip placement.
	public float CursorOffsetY = 16;

	public this(UIContext context)
	{
		mContext = context;
		mTooltipView = new TooltipView();
	}

	public ~this()
	{
		// Detach tooltip from popup layer before deleting
		if (mIsShowing && mTooltipView.Parent != null && mTooltipPopupLayer != null)
		{
			mTooltipPopupLayer.ClosePopup(mTooltipView);
		}
		delete mTooltipView;
	}

	/// Whether a tooltip is currently visible.
	public bool IsShowing => mIsShowing;

	/// The current tooltip target view, or null.
	public View CurrentTarget => mCurrentTarget;

	/// Called each frame by UIContext.Update.
	public void Update(float deltaTime)
	{
		if (mCurrentTarget == null || mIsShowing)
			return;

		mHoverTime += deltaTime;
		if (mHoverTime >= ShowDelay)
		{
			Show();
		}
	}

	/// Called by InputManager when the hovered view changes.
	public void OnHoverChanged(View newHover)
	{
		if (newHover == mCurrentTarget)
			return;

		// Hide existing tooltip
		if (mIsShowing)
			Hide();

		mCurrentTarget = null;
		mHoverTime = 0;

		// Check if new view has tooltip text
		if (newHover != null && newHover.TooltipText != null && newHover.TooltipText.Length > 0)
		{
			mCurrentTarget = newHover;
		}
	}

	/// Called by InputManager on mouse down — hide tooltip immediately.
	public void OnMouseDown()
	{
		if (mIsShowing)
			Hide();
		mCurrentTarget = null;
		mHoverTime = 0;
	}

	/// Called by InputManager on mouse move — update position.
	public void OnMouseMoved(float screenX, float screenY)
	{
		mLastMouseX = screenX;
		mLastMouseY = screenY;
	}

	/// Force hide the tooltip.
	public void Hide()
	{
		if (!mIsShowing) return;

		mTooltipPopupLayer?.ClosePopup(mTooltipView);
		mIsShowing = false;
		mTooltipPopupLayer = null;
	}

	private void Show()
	{
		if (mCurrentTarget == null) return;

		let targetRoot = mCurrentTarget.RootView;
		if (targetRoot == null) return;

		let layer = targetRoot.PopupLayer;
		float dpiScale = targetRoot.DpiScale;
		float viewportW = targetRoot.LogicalWidth;
		float viewportH = targetRoot.LogicalHeight;

		mTooltipView.SetText(mCurrentTarget.TooltipText);

		// Measure tooltip to know its size
		mTooltipView.Measure(
			MeasureSpec.MakeAtMost(viewportW),
			MeasureSpec.MakeAtMost(viewportH)
		);

		// Position below cursor
		float logicalX = mLastMouseX / dpiScale;
		float logicalY = mLastMouseY / dpiScale + CursorOffsetY;

		let pos = PopupPositioner.PositionBestFit(
			mTooltipView.MeasuredWidth,
			mTooltipView.MeasuredHeight,
			.(logicalX, logicalY, 0, 0),
			viewportW,
			viewportH
		);

		layer.ShowPopup(mTooltipView, null, pos.X, pos.Y, false, false);
		mTooltipPopupLayer = layer;
		mIsShowing = true;
	}
}
