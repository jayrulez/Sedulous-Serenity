using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// A draggable divider that can be used to resize adjacent panels.
public class Splitter : Control
{
	private bool mIsDragging;
	private float mLastMousePos; // Last mouse position during drag
	private float mSplitterThickness = 6;
	private Orientation mOrientation = .Horizontal;

	// Events
	private EventAccessor<delegate void(Splitter, float)> mSplitterMovedEvent = new .() ~ delete _;

	/// The orientation of the splitter.
	/// Horizontal means the splitter bar is vertical and resizes left/right.
	/// Vertical means the splitter bar is horizontal and resizes top/bottom.
	public Orientation Orientation
	{
		get => mOrientation;
		set
		{
			if (mOrientation != value)
			{
				mOrientation = value;
				UpdateCursor();
				InvalidateMeasure();
			}
		}
	}

	/// The thickness of the splitter bar in pixels.
	public float SplitterThickness
	{
		get => mSplitterThickness;
		set
		{
			if (mSplitterThickness != value)
			{
				mSplitterThickness = Math.Max(2, value);
				InvalidateMeasure();
			}
		}
	}

	/// Whether the splitter is currently being dragged.
	public bool IsDragging => mIsDragging;

	/// Fired when the splitter is moved. The delta is the amount moved in pixels.
	public EventAccessor<delegate void(Splitter, float)> SplitterMoved => mSplitterMovedEvent;

	public this()
	{
		Focusable = false;
		UpdateCursor();
	}

	private void UpdateCursor()
	{
		Cursor = Orientation == .Horizontal ? .ResizeEW : .ResizeNS;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (Orientation == .Horizontal)
		{
			// Vertical bar - fixed width, stretch height
			return .(mSplitterThickness, constraints.MaxHeight != SizeConstraints.Infinity ? constraints.MaxHeight : 100);
		}
		else
		{
			// Horizontal bar - stretch width, fixed height
			return .(constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : 100, mSplitterThickness);
		}
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Get colors based on state
		Color bgColor;
		if (mIsDragging)
			bgColor = theme?.GetColor("SplitterDragging") ?? theme?.GetColor("Primary") ?? Color(0, 120, 215);
		else if (IsMouseOver)
			bgColor = theme?.GetColor("SplitterHover") ?? Color(150, 150, 150);
		else
			bgColor = theme?.GetColor("SplitterBackground") ?? Color(180, 180, 180);

		drawContext.FillRect(bounds, bgColor);

		// Draw grip lines in center
		let gripColor = Color(bgColor.R > 128 ? (uint8)(bgColor.R - 40) : (uint8)(bgColor.R + 40),
							  bgColor.G > 128 ? (uint8)(bgColor.G - 40) : (uint8)(bgColor.G + 40),
							  bgColor.B > 128 ? (uint8)(bgColor.B - 40) : (uint8)(bgColor.B + 40));

		if (Orientation == .Horizontal)
		{
			// Vertical grip lines
			let centerX = bounds.X + bounds.Width / 2;
			let gripHeight = Math.Min(bounds.Height * 0.3f, 30);
			let startY = bounds.Y + (bounds.Height - gripHeight) / 2;

			for (int i = 0; i < 3; i++)
			{
				let y = startY + i * (gripHeight / 2);
				drawContext.FillRect(.(centerX - 1, y, 2, 2), gripColor);
			}
		}
		else
		{
			// Horizontal grip lines
			let centerY = bounds.Y + bounds.Height / 2;
			let gripWidth = Math.Min(bounds.Width * 0.3f, 30);
			let startX = bounds.X + (bounds.Width - gripWidth) / 2;

			for (int i = 0; i < 3; i++)
			{
				let x = startX + i * (gripWidth / 2);
				drawContext.FillRect(.(x, centerY - 1, 2, 2), gripColor);
			}
		}
	}

	protected override void OnMouseEnter()
	{
		base.OnMouseEnter();
		InvalidateVisual();
	}

	protected override void OnMouseLeave()
	{
		base.OnMouseLeave();
		InvalidateVisual();
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		base.OnMouseDownRouted(args);

		if (args.Button == .Left && IsEnabled)
		{
			mIsDragging = true;
			// Store the starting mouse position
			mLastMousePos = mOrientation == .Horizontal ? args.ScreenX : args.ScreenY;
			Context?.CaptureMouse(this);
			InvalidateVisual();
			args.Handled = true;
		}
	}

	protected override void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		base.OnMouseUpRouted(args);

		if (args.Button == .Left && mIsDragging)
		{
			mIsDragging = false;
			Context?.ReleaseMouseCapture();
			InvalidateVisual();
			args.Handled = true;
		}
	}

	protected override void OnMouseMoveRouted(MouseEventArgs args)
	{
		base.OnMouseMoveRouted(args);

		if (mIsDragging)
		{
			// Calculate delta from mouse movement
			let mousePos = mOrientation == .Horizontal ? args.ScreenX : args.ScreenY;
			let delta = mousePos - mLastMousePos;

			if (Math.Abs(delta) > 0.5f)
			{
				mSplitterMovedEvent.[Friend]Invoke(this, delta);
				// Update last position to current mouse position
				// This ensures smooth tracking even when movement is constrained
				mLastMousePos = mousePos;
			}

			args.Handled = true;
		}
	}
}
