using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Specifies the position of a child element within a DockPanel.
public enum Dock
{
	/// Dock to the left edge.
	Left,
	/// Dock to the top edge.
	Top,
	/// Dock to the right edge.
	Right,
	/// Dock to the bottom edge.
	Bottom
}

/// Arranges children by docking them to the edges of the panel.
/// The last child fills the remaining space by default.
public class DockPanel : Panel
{
	private bool mLastChildFill = true;

	// Attached property storage - maps element to dock position
	private Dictionary<UIElement, Dock> mDockValues = new .() ~ delete _;

	/// Whether the last child fills the remaining space.
	public bool LastChildFill
	{
		get => mLastChildFill;
		set { mLastChildFill = value; InvalidateMeasure(); }
	}

	/// Gets the dock position for a child element.
	public Dock GetDock(UIElement element)
	{
		if (mDockValues.TryGetValue(element, let dock))
			return dock;
		return .Left; // Default
	}

	/// Sets the dock position for a child element.
	public void SetDock(UIElement element, Dock dock)
	{
		mDockValues[element] = dock;
		InvalidateMeasure();
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		var usedWidth = 0.0f;
		var usedHeight = 0.0f;
		var maxWidth = 0.0f;
		var maxHeight = 0.0f;

		let childCount = Children.Count;
		for (int i = 0; i < childCount; i++)
		{
			let child = Children[i];
			if (child.Visibility == .Collapsed)
				continue;

			let dock = GetDock(child);
			let isLast = (i == childCount - 1) && mLastChildFill;

			// Calculate remaining space
			let remainingWidth = Math.Max(0, constraints.MaxWidth - usedWidth);
			let remainingHeight = Math.Max(0, constraints.MaxHeight - usedHeight);

			SizeConstraints childConstraints;
			if (isLast)
			{
				// Last child fills remaining space
				childConstraints = SizeConstraints.FromMaximum(remainingWidth, remainingHeight);
			}
			else
			{
				switch (dock)
				{
				case .Left, .Right:
					childConstraints = SizeConstraints.FromMaximum(remainingWidth, remainingHeight);
				case .Top, .Bottom:
					childConstraints = SizeConstraints.FromMaximum(remainingWidth, remainingHeight);
				}
			}

			child.Measure(childConstraints);

			switch (dock)
			{
			case .Left, .Right:
				usedWidth += child.DesiredSize.Width;
				maxHeight = Math.Max(maxHeight, usedHeight + child.DesiredSize.Height);
			case .Top, .Bottom:
				usedHeight += child.DesiredSize.Height;
				maxWidth = Math.Max(maxWidth, usedWidth + child.DesiredSize.Width);
			}
		}

		return .(Math.Max(maxWidth, usedWidth), Math.Max(maxHeight, usedHeight));
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		var left = contentBounds.X;
		var top = contentBounds.Y;
		var right = contentBounds.X + contentBounds.Width;
		var bottom = contentBounds.Y + contentBounds.Height;

		let childCount = Children.Count;
		for (int i = 0; i < childCount; i++)
		{
			let child = Children[i];
			if (child.Visibility == .Collapsed)
				continue;

			let dock = GetDock(child);
			let isLast = (i == childCount - 1) && mLastChildFill;

			RectangleF childRect;
			if (isLast)
			{
				// Fill remaining space
				childRect = .(left, top, right - left, bottom - top);
			}
			else
			{
				switch (dock)
				{
				case .Left:
					childRect = .(left, top, child.DesiredSize.Width, bottom - top);
					left += child.DesiredSize.Width;
				case .Top:
					childRect = .(left, top, right - left, child.DesiredSize.Height);
					top += child.DesiredSize.Height;
				case .Right:
					childRect = .(right - child.DesiredSize.Width, top, child.DesiredSize.Width, bottom - top);
					right -= child.DesiredSize.Width;
				case .Bottom:
					childRect = .(left, bottom - child.DesiredSize.Height, right - left, child.DesiredSize.Height);
					bottom -= child.DesiredSize.Height;
				}
			}

			child.Arrange(childRect);
		}
	}
}
