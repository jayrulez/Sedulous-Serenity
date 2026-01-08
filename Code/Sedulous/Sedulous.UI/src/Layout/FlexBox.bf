using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// CSS-like flexbox layout panel.
class FlexBox : Widget
{
	private FlexDirection mDirection = .Row;
	private FlexWrap mWrap = .NoWrap;
	private JustifyContent mJustifyContent = .FlexStart;
	private AlignItems mAlignItems = .Stretch;
	private AlignContent mAlignContent = .Stretch;
	private float mGap = 0;
	private float mRowGap = 0;
	private float mColumnGap = 0;

	// Attached property storage
	private static Dictionary<Widget, FlexItemInfo> sAttachedProps = new .() ~ delete _;

	/// Attached properties for flex items.
	private struct FlexItemInfo
	{
		public float Grow;
		public float Shrink;
		public float Basis;
		public bool HasBasis;
		public AlignItems AlignSelf;
		public bool HasAlignSelf;
		public int32 Order;
	}

	// ============ Container Properties ============

	/// Gets or sets the flex direction.
	public FlexDirection Direction
	{
		get => mDirection;
		set { if (mDirection != value) { mDirection = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the wrap behavior.
	public FlexWrap Wrap
	{
		get => mWrap;
		set { if (mWrap != value) { mWrap = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the main axis alignment.
	public JustifyContent JustifyContent
	{
		get => mJustifyContent;
		set { if (mJustifyContent != value) { mJustifyContent = value; InvalidateArrange(); } }
	}

	/// Gets or sets the cross axis alignment.
	public AlignItems AlignItems
	{
		get => mAlignItems;
		set { if (mAlignItems != value) { mAlignItems = value; InvalidateArrange(); } }
	}

	/// Gets or sets the multi-line alignment.
	public AlignContent AlignContent
	{
		get => mAlignContent;
		set { if (mAlignContent != value) { mAlignContent = value; InvalidateArrange(); } }
	}

	/// Gets or sets the gap between items (both row and column).
	public float Gap
	{
		get => mGap;
		set { mGap = value; mRowGap = value; mColumnGap = value; InvalidateMeasure(); }
	}

	/// Gets or sets the gap between rows.
	public float RowGap
	{
		get => mRowGap;
		set { if (mRowGap != value) { mRowGap = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the gap between columns.
	public float ColumnGap
	{
		get => mColumnGap;
		set { if (mColumnGap != value) { mColumnGap = value; InvalidateMeasure(); } }
	}

	// ============ Attached Properties ============

	/// Gets the flex-grow value.
	public static float GetGrow(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info))
			return info.Grow;
		return 0;
	}

	/// Sets the flex-grow value.
	public static void SetGrow(Widget widget, float grow)
	{
		var info = GetOrCreateInfo(widget);
		info.Grow = Math.Max(0, grow);
		sAttachedProps[widget] = info;
		widget.InvalidateMeasure();
	}

	/// Gets the flex-shrink value.
	public static float GetShrink(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info))
			return info.Shrink;
		return 1;
	}

	/// Sets the flex-shrink value.
	public static void SetShrink(Widget widget, float shrink)
	{
		var info = GetOrCreateInfo(widget);
		info.Shrink = Math.Max(0, shrink);
		sAttachedProps[widget] = info;
		widget.InvalidateMeasure();
	}

	/// Gets the flex-basis value.
	public static float GetBasis(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info) && info.HasBasis)
			return info.Basis;
		return float.NaN;
	}

	/// Sets the flex-basis value.
	public static void SetBasis(Widget widget, float basis)
	{
		var info = GetOrCreateInfo(widget);
		info.Basis = basis;
		info.HasBasis = basis == basis; // NaN check
		sAttachedProps[widget] = info;
		widget.InvalidateMeasure();
	}

	/// Gets the align-self value.
	public static AlignItems GetAlignSelf(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info) && info.HasAlignSelf)
			return info.AlignSelf;
		return .Stretch;
	}

	/// Sets the align-self value.
	public static void SetAlignSelf(Widget widget, AlignItems align)
	{
		var info = GetOrCreateInfo(widget);
		info.AlignSelf = align;
		info.HasAlignSelf = true;
		sAttachedProps[widget] = info;
		widget.InvalidateArrange();
	}

	/// Gets the order value.
	public static int32 GetOrder(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info))
			return info.Order;
		return 0;
	}

	/// Sets the order value.
	public static void SetOrder(Widget widget, int32 order)
	{
		var info = GetOrCreateInfo(widget);
		info.Order = order;
		sAttachedProps[widget] = info;
		widget.InvalidateArrange();
	}

	private static FlexItemInfo GetOrCreateInfo(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info))
			return info;
		return FlexItemInfo() { Grow = 0, Shrink = 1, Basis = 0, HasBasis = false, AlignSelf = .Stretch, HasAlignSelf = false, Order = 0 };
	}

	// ============ Helper Methods ============

	/// Whether main axis is horizontal.
	private bool IsHorizontal => mDirection == .Row || mDirection == .RowReverse;

	/// Whether direction is reversed.
	private bool IsReversed => mDirection == .RowReverse || mDirection == .ColumnReverse;

	/// Gets the main axis gap.
	private float MainGap => IsHorizontal ? mColumnGap : mRowGap;

	/// Gets the cross axis gap.
	private float CrossGap => IsHorizontal ? mRowGap : mColumnGap;

	/// Gets main axis size from vector.
	private float GetMainSize(Vector2 size) => IsHorizontal ? size.X : size.Y;

	/// Gets cross axis size from vector.
	private float GetCrossSize(Vector2 size) => IsHorizontal ? size.Y : size.X;

	/// Creates a vector from main and cross sizes.
	private Vector2 MakeSize(float main, float cross)
	{
		return IsHorizontal ? Vector2(main, cross) : Vector2(cross, main);
	}

	// ============ Layout ============

	/// Flex line for layout calculations.
	private struct FlexLine
	{
		public int32 StartIndex;
		public int32 EndIndex;
		public float MainSize;
		public float CrossSize;
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		let contentWidth = Math.Max(0, availableSize.X - Padding.HorizontalThickness);
		let contentHeight = Math.Max(0, availableSize.Y - Padding.VerticalThickness);
		let mainAvailable = IsHorizontal ? contentWidth : contentHeight;
		let crossAvailable = IsHorizontal ? contentHeight : contentWidth;

		// Get visible children
		List<Widget> visibleChildren = scope .();
		for (let child in Children)
		{
			if (child.Visibility != .Collapsed)
				visibleChildren.Add(child);
		}

		if (visibleChildren.Count == 0)
			return Vector2(Padding.HorizontalThickness, Padding.VerticalThickness);

		// Sort by order if needed
		// (simplified: not sorting for now)

		// Measure children with infinite main axis
		for (let child in visibleChildren)
		{
			let measureSize = MakeSize(float.MaxValue, crossAvailable);
			child.Measure(measureSize);
		}

		// Calculate lines
		List<FlexLine> lines = scope .();
		BuildLines(visibleChildren, mainAvailable, lines);

		// Calculate total size
		float totalMainSize = 0;
		float totalCrossSize = 0;

		for (let line in lines)
		{
			totalMainSize = Math.Max(totalMainSize, line.MainSize);
			totalCrossSize += line.CrossSize;
		}

		// Add gaps between lines
		if (lines.Count > 1)
			totalCrossSize += CrossGap * (lines.Count - 1);

		let resultSize = MakeSize(totalMainSize, totalCrossSize);
		return Vector2(
			resultSize.X + Padding.HorizontalThickness,
			resultSize.Y + Padding.VerticalThickness
		);
	}

	private void BuildLines(List<Widget> children, float mainAvailable, List<FlexLine> lines)
	{
		if (children.Count == 0)
			return;

		var currentLine = FlexLine() { StartIndex = 0 };
		float currentMain = 0;
		float currentCross = 0;

		for (int32 i = 0; i < children.Count; i++)
		{
			let child = children[i];
			let itemMain = GetMainSize(child.DesiredSize);
			let itemCross = GetCrossSize(child.DesiredSize);

			// Check if item fits on current line
			float testMain = currentMain + itemMain;
			if (currentLine.StartIndex < i)
				testMain += MainGap;

			bool shouldWrap = mWrap != .NoWrap && testMain > mainAvailable && currentLine.StartIndex < i;

			if (shouldWrap)
			{
				// Finish current line
				currentLine.EndIndex = i;
				currentLine.MainSize = currentMain;
				currentLine.CrossSize = currentCross;
				lines.Add(currentLine);

				// Start new line
				currentLine = FlexLine() { StartIndex = i };
				currentMain = itemMain;
				currentCross = itemCross;
			}
			else
			{
				if (currentLine.StartIndex < i)
					currentMain += MainGap;
				currentMain += itemMain;
				currentCross = Math.Max(currentCross, itemCross);
			}
		}

		// Add last line
		currentLine.EndIndex = (int32)children.Count;
		currentLine.MainSize = currentMain;
		currentLine.CrossSize = currentCross;
		lines.Add(currentLine);
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		let contentBounds = ContentBounds;
		let mainAvailable = IsHorizontal ? contentBounds.Width : contentBounds.Height;
		let crossAvailable = IsHorizontal ? contentBounds.Height : contentBounds.Width;

		// Get visible children
		List<Widget> visibleChildren = scope .();
		for (let child in Children)
		{
			if (child.Visibility != .Collapsed)
				visibleChildren.Add(child);
		}

		if (visibleChildren.Count == 0)
			return;

		// Build lines
		List<FlexLine> lines = scope .();
		BuildLines(visibleChildren, mainAvailable, lines);

		// Calculate cross sizes for lines
		float totalCrossSize = 0;
		for (let line in lines)
			totalCrossSize += line.CrossSize;
		if (lines.Count > 1)
			totalCrossSize += CrossGap * (lines.Count - 1);

		float extraCross = crossAvailable - totalCrossSize;

		// Calculate line positions based on align-content
		float crossOffset = 0;
		float crossSpacing = 0;

		switch (mAlignContent)
		{
		case .FlexStart:
			crossOffset = 0;
		case .FlexEnd:
			crossOffset = extraCross;
		case .Center:
			crossOffset = extraCross / 2;
		case .SpaceBetween:
			if (lines.Count > 1)
				crossSpacing = extraCross / (lines.Count - 1);
		case .SpaceAround:
			if (lines.Count > 0)
			{
				let space = extraCross / lines.Count;
				crossOffset = space / 2;
				crossSpacing = space;
			}
		case .Stretch:
			if (lines.Count > 0)
			{
				let extra = extraCross / lines.Count;
				for (var line in ref lines)
					line.CrossSize += extra;
			}
		}

		// Handle wrap-reverse
		if (mWrap == .WrapReverse)
		{
			crossOffset = crossAvailable - crossOffset;
		}

		// Arrange each line
		for (let line in lines)
		{
			ArrangeLine(visibleChildren, line, contentBounds, ref crossOffset, crossSpacing);
		}
	}

	private void ArrangeLine(List<Widget> children, FlexLine line, RectangleF bounds, ref float crossOffset, float crossSpacing)
	{
		let mainAvailable = IsHorizontal ? bounds.Width : bounds.Height;
		let lineItemCount = line.EndIndex - line.StartIndex;
		if (lineItemCount == 0)
			return;

		// Calculate flex grow/shrink
		float totalGrow = 0;
		float totalShrink = 0;
		float totalBasis = 0;

		for (int32 i = line.StartIndex; i < line.EndIndex; i++)
		{
			let child = children[i];
			let info = GetOrCreateInfo(child);
			let basis = info.HasBasis ? info.Basis : GetMainSize(child.DesiredSize);

			totalGrow += info.Grow;
			totalShrink += info.Shrink * basis;
			totalBasis += basis;
		}

		// Add gaps to basis
		if (lineItemCount > 1)
			totalBasis += MainGap * (lineItemCount - 1);

		float freeSpace = mainAvailable - totalBasis;
		float growFactor = (freeSpace > 0 && totalGrow > 0) ? freeSpace / totalGrow : 0;
		float shrinkFactor = (freeSpace < 0 && totalShrink > 0) ? Math.Abs(freeSpace) / totalShrink : 0;

		// Calculate main offset based on justify-content
		float mainOffset = 0;
		float mainSpacing = 0;

		if (freeSpace > 0 && totalGrow == 0)
		{
			switch (mJustifyContent)
			{
			case .FlexStart:
				mainOffset = 0;
			case .FlexEnd:
				mainOffset = freeSpace;
			case .Center:
				mainOffset = freeSpace / 2;
			case .SpaceBetween:
				if (lineItemCount > 1)
					mainSpacing = freeSpace / (lineItemCount - 1);
			case .SpaceAround:
				if (lineItemCount > 0)
				{
					let space = freeSpace / lineItemCount;
					mainOffset = space / 2;
					mainSpacing = space;
				}
			case .SpaceEvenly:
				if (lineItemCount > 0)
				{
					let space = freeSpace / (lineItemCount + 1);
					mainOffset = space;
					mainSpacing = space;
				}
			}
		}

		// Handle direction reversal
		if (IsReversed)
			mainOffset = mainAvailable - mainOffset;

		// Arrange items
		float currentMain = mainOffset;
		float lineCrossOffset = crossOffset;

		if (mWrap == .WrapReverse)
			lineCrossOffset -= line.CrossSize;

		for (int32 i = line.StartIndex; i < line.EndIndex; i++)
		{
			let child = children[i];
			let info = GetOrCreateInfo(child);
			let basis = info.HasBasis ? info.Basis : GetMainSize(child.DesiredSize);

			// Calculate item main size
			float itemMain = basis;
			if (freeSpace > 0 && info.Grow > 0)
				itemMain += info.Grow * growFactor;
			else if (freeSpace < 0 && info.Shrink > 0)
				itemMain -= info.Shrink * basis * shrinkFactor;
			itemMain = Math.Max(0, itemMain);

			// Calculate item cross size and position
			let align = info.HasAlignSelf ? info.AlignSelf : mAlignItems;
			let childCross = GetCrossSize(child.DesiredSize);
			float itemCross = line.CrossSize;
			float itemCrossOffset = 0;

			switch (align)
			{
			case .Stretch:
				itemCross = line.CrossSize;
			case .FlexStart:
				itemCross = childCross;
			case .FlexEnd:
				itemCross = childCross;
				itemCrossOffset = line.CrossSize - childCross;
			case .Center:
				itemCross = childCross;
				itemCrossOffset = (line.CrossSize - childCross) / 2;
			case .Baseline:
				itemCross = childCross;
				// Baseline alignment would need font metrics - simplified to flex-start
			}

			// Position calculation
			float x, y, w, h;
			if (IsHorizontal)
			{
				if (IsReversed)
				{
					x = bounds.X + currentMain - itemMain;
					currentMain -= itemMain + MainGap + mainSpacing;
				}
				else
				{
					x = bounds.X + currentMain;
					currentMain += itemMain + MainGap + mainSpacing;
				}
				y = bounds.Y + lineCrossOffset + itemCrossOffset;
				w = itemMain;
				h = itemCross;
			}
			else
			{
				x = bounds.X + lineCrossOffset + itemCrossOffset;
				if (IsReversed)
				{
					y = bounds.Y + currentMain - itemMain;
					currentMain -= itemMain + MainGap + mainSpacing;
				}
				else
				{
					y = bounds.Y + currentMain;
					currentMain += itemMain + MainGap + mainSpacing;
				}
				w = itemCross;
				h = itemMain;
			}

			child.Arrange(RectangleF(x, y, Math.Max(0, w), Math.Max(0, h)));
		}

		// Update cross offset for next line
		if (mWrap == .WrapReverse)
			crossOffset -= line.CrossSize + CrossGap + crossSpacing;
		else
			crossOffset += line.CrossSize + CrossGap + crossSpacing;
	}
}
