namespace Sedulous.UI;

using System;
using internal Sedulous.UI;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// Root view for a window. Holds per-window state: size, DPI scale, PopupLayer, cursor.
/// Each OS window (or virtual window) gets one RootView added to the shared UIContext.
/// Content views are added as children; the PopupLayer is always the last child.
public class RootView : ViewGroup
{
	private float mWindowWidth;
	private float mWindowHeight;
	private float mDpiScale = 1.0f;
	private PopupLayer mPopupLayer; // Owned as child view — ViewGroup destructor handles deletion
	private CursorType mRequestedCursor = .Default;

	/// Physical window width in pixels.
	public float WindowWidth => mWindowWidth;

	/// Physical window height in pixels.
	public float WindowHeight => mWindowHeight;

	/// Logical width (physical / DPI scale).
	public float LogicalWidth => (mDpiScale > 0) ? mWindowWidth / mDpiScale : mWindowWidth;

	/// Logical height (physical / DPI scale).
	public float LogicalHeight => (mDpiScale > 0) ? mWindowHeight / mDpiScale : mWindowHeight;

	/// DPI scale factor for this window. Default 1.0.
	public float DpiScale
	{
		get => mDpiScale;
		set { mDpiScale = Math.Max(0.1f, value); }
	}

	/// The per-window popup/overlay layer.
	public PopupLayer PopupLayer => mPopupLayer;

	/// Cursor type requested by the hovered view in this window.
	public CursorType RequestedCursor
	{
		get => mRequestedCursor;
		set { mRequestedCursor = value; }
	}

	public this()
	{
		mPopupLayer = new PopupLayer();
		AddView(mPopupLayer);
	}

	/// Adds a child, keeping PopupLayer as the last child (topmost for drawing/hit-testing).
	public override void AddView(View child)
	{
		if (child == null || child.Parent != null)
			return;

		if (child == mPopupLayer || ChildCount == 0)
		{
			AddViewInternal(child);
		}
		else
		{
			// Insert before PopupLayer (last child)
			int insertIndex = ChildCount;
			if (GetChildAt(ChildCount - 1) == mPopupLayer)
				insertIndex = ChildCount - 1;
			InsertView(child, insertIndex);
		}
	}

	/// Set the physical window size in pixels.
	public void SetSize(float width, float height)
	{
		mWindowWidth = width;
		mWindowHeight = height;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(LogicalWidth, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(LogicalHeight, MinHeight, MaxHeight);

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;
			child.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(h));
		}

		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;
			child.Layout(0, 0, width, height);
		}
	}
}
