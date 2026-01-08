using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Defines a row in a Grid.
class RowDefinition
{
	/// Height of the row.
	public GridLength Height = .Star;
	/// Minimum height.
	public float MinHeight = 0;
	/// Maximum height.
	public float MaxHeight = float.MaxValue;

	/// Actual computed height after layout.
	public float ActualHeight { get; private set; }

	/// Sets the actual height (called during layout).
	internal void SetActualHeight(float height)
	{
		ActualHeight = height;
	}

	/// Creates a row with default star sizing.
	public this() { }

	/// Creates a row with specified height.
	public this(GridLength height)
	{
		Height = height;
	}
}

/// Defines a column in a Grid.
class ColumnDefinition
{
	/// Width of the column.
	public GridLength Width = .Star;
	/// Minimum width.
	public float MinWidth = 0;
	/// Maximum width.
	public float MaxWidth = float.MaxValue;

	/// Actual computed width after layout.
	public float ActualWidth { get; private set; }

	/// Sets the actual width (called during layout).
	internal void SetActualWidth(float width)
	{
		ActualWidth = width;
	}

	/// Creates a column with default star sizing.
	public this() { }

	/// Creates a column with specified width.
	public this(GridLength width)
	{
		Width = width;
	}
}

/// Grid layout panel with rows and columns.
class Grid : Widget
{
	private List<RowDefinition> mRowDefinitions = new .() ~ DeleteContainerAndItems!(_);
	private List<ColumnDefinition> mColumnDefinitions = new .() ~ DeleteContainerAndItems!(_);

	// Attached property storage
	private static Dictionary<Widget, GridCellInfo> sAttachedProps = new .() ~ delete _;

	// Computed sizes during layout
	private float[] mRowSizes ~ delete _;
	private float[] mColumnSizes ~ delete _;

	/// Attached properties for grid children.
	private struct GridCellInfo
	{
		public int32 Row;
		public int32 Column;
		public int32 RowSpan;
		public int32 ColumnSpan;
	}

	/// Gets the row definitions.
	public List<RowDefinition> RowDefinitions => mRowDefinitions;

	/// Gets the column definitions.
	public List<ColumnDefinition> ColumnDefinitions => mColumnDefinitions;

	// ============ Attached Properties ============

	/// Gets the Row attached property.
	public static int32 GetRow(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info))
			return info.Row;
		return 0;
	}

	/// Sets the Row attached property.
	public static void SetRow(Widget widget, int32 row)
	{
		var info = GetOrCreateInfo(widget);
		info.Row = Math.Max(0, row);
		sAttachedProps[widget] = info;
		widget.InvalidateArrange();
	}

	/// Gets the Column attached property.
	public static int32 GetColumn(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info))
			return info.Column;
		return 0;
	}

	/// Sets the Column attached property.
	public static void SetColumn(Widget widget, int32 column)
	{
		var info = GetOrCreateInfo(widget);
		info.Column = Math.Max(0, column);
		sAttachedProps[widget] = info;
		widget.InvalidateArrange();
	}

	/// Gets the RowSpan attached property.
	public static int32 GetRowSpan(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info))
			return info.RowSpan;
		return 1;
	}

	/// Sets the RowSpan attached property.
	public static void SetRowSpan(Widget widget, int32 rowSpan)
	{
		var info = GetOrCreateInfo(widget);
		info.RowSpan = Math.Max(1, rowSpan);
		sAttachedProps[widget] = info;
		widget.InvalidateArrange();
	}

	/// Gets the ColumnSpan attached property.
	public static int32 GetColumnSpan(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info))
			return info.ColumnSpan;
		return 1;
	}

	/// Sets the ColumnSpan attached property.
	public static void SetColumnSpan(Widget widget, int32 columnSpan)
	{
		var info = GetOrCreateInfo(widget);
		info.ColumnSpan = Math.Max(1, columnSpan);
		sAttachedProps[widget] = info;
		widget.InvalidateArrange();
	}

	/// Sets cell position for a widget.
	public static void SetCell(Widget widget, int32 row, int32 column)
	{
		var info = GetOrCreateInfo(widget);
		info.Row = Math.Max(0, row);
		info.Column = Math.Max(0, column);
		sAttachedProps[widget] = info;
		widget.InvalidateArrange();
	}

	/// Sets cell position and span for a widget.
	public static void SetCell(Widget widget, int32 row, int32 column, int32 rowSpan, int32 columnSpan)
	{
		var info = GridCellInfo();
		info.Row = Math.Max(0, row);
		info.Column = Math.Max(0, column);
		info.RowSpan = Math.Max(1, rowSpan);
		info.ColumnSpan = Math.Max(1, columnSpan);
		sAttachedProps[widget] = info;
		widget.InvalidateArrange();
	}

	private static GridCellInfo GetOrCreateInfo(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let info))
			return info;
		return GridCellInfo() { Row = 0, Column = 0, RowSpan = 1, ColumnSpan = 1 };
	}

	// ============ Helper Methods ============

	/// Gets effective row count (at least 1).
	private int32 EffectiveRowCount => Math.Max(1, (int32)mRowDefinitions.Count);

	/// Gets effective column count (at least 1).
	private int32 EffectiveColumnCount => Math.Max(1, (int32)mColumnDefinitions.Count);

	/// Gets row definition or default.
	private GridLength GetRowHeight(int32 row)
	{
		if (row >= 0 && row < mRowDefinitions.Count)
			return mRowDefinitions[row].Height;
		return .Star;
	}

	/// Gets column definition or default.
	private GridLength GetColumnWidth(int32 column)
	{
		if (column >= 0 && column < mColumnDefinitions.Count)
			return mColumnDefinitions[column].Width;
		return .Star;
	}

	/// Gets row min height.
	private float GetRowMinHeight(int32 row)
	{
		if (row >= 0 && row < mRowDefinitions.Count)
			return mRowDefinitions[row].MinHeight;
		return 0;
	}

	/// Gets row max height.
	private float GetRowMaxHeight(int32 row)
	{
		if (row >= 0 && row < mRowDefinitions.Count)
			return mRowDefinitions[row].MaxHeight;
		return float.MaxValue;
	}

	/// Gets column min width.
	private float GetColumnMinWidth(int32 column)
	{
		if (column >= 0 && column < mColumnDefinitions.Count)
			return mColumnDefinitions[column].MinWidth;
		return 0;
	}

	/// Gets column max width.
	private float GetColumnMaxWidth(int32 column)
	{
		if (column >= 0 && column < mColumnDefinitions.Count)
			return mColumnDefinitions[column].MaxWidth;
		return float.MaxValue;
	}

	// ============ Layout ============

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		let rowCount = EffectiveRowCount;
		let colCount = EffectiveColumnCount;

		// Allocate size arrays
		delete mRowSizes;
		delete mColumnSizes;
		mRowSizes = new float[rowCount];
		mColumnSizes = new float[colCount];

		// Available space after padding
		let contentWidth = Math.Max(0, availableSize.X - Padding.HorizontalThickness);
		let contentHeight = Math.Max(0, availableSize.Y - Padding.VerticalThickness);

		// First pass: measure auto-sized rows/columns
		MeasureAutoSizes(contentWidth, contentHeight, rowCount, colCount);

		// Second pass: distribute remaining space to star-sized rows/columns
		DistributeStarSizes(contentWidth, contentHeight, rowCount, colCount);

		// Calculate total size
		float totalWidth = 0;
		float totalHeight = 0;

		for (int32 i = 0; i < colCount; i++)
			totalWidth += mColumnSizes[i];

		for (int32 i = 0; i < rowCount; i++)
			totalHeight += mRowSizes[i];

		// Add padding
		return Vector2(
			totalWidth + Padding.HorizontalThickness,
			totalHeight + Padding.VerticalThickness
		);
	}

	private void MeasureAutoSizes(float availableWidth, float availableHeight, int32 rowCount, int32 colCount)
	{
		// Initialize with pixel sizes and minimums
		for (int32 c = 0; c < colCount; c++)
		{
			let length = GetColumnWidth(c);
			if (length.IsAbsolute)
				mColumnSizes[c] = Math.Clamp(length.Value, GetColumnMinWidth(c), GetColumnMaxWidth(c));
			else
				mColumnSizes[c] = GetColumnMinWidth(c);
		}

		for (int32 r = 0; r < rowCount; r++)
		{
			let length = GetRowHeight(r);
			if (length.IsAbsolute)
				mRowSizes[r] = Math.Clamp(length.Value, GetRowMinHeight(r), GetRowMaxHeight(r));
			else
				mRowSizes[r] = GetRowMinHeight(r);
		}

		// Measure children to determine auto sizes
		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			let info = GetOrCreateInfo(child);
			let row = Math.Min(info.Row, rowCount - 1);
			let col = Math.Min(info.Column, colCount - 1);
			let rowSpan = Math.Min(info.RowSpan, rowCount - row);
			let colSpan = Math.Min(info.ColumnSpan, colCount - col);

			// Check if this child affects auto columns
			bool hasAutoColumn = false;
			for (int32 c = col; c < col + colSpan && c < colCount; c++)
			{
				if (GetColumnWidth(c).IsAuto)
				{
					hasAutoColumn = true;
					break;
				}
			}

			// Check if this child affects auto rows
			bool hasAutoRow = false;
			for (int32 r = row; r < row + rowSpan && r < rowCount; r++)
			{
				if (GetRowHeight(r).IsAuto)
				{
					hasAutoRow = true;
					break;
				}
			}

			if (!hasAutoColumn && !hasAutoRow)
				continue;

			// Measure with infinite size for auto dimensions
			float measureWidth = hasAutoColumn ? float.MaxValue : GetSpanSize(mColumnSizes, col, colSpan);
			float measureHeight = hasAutoRow ? float.MaxValue : GetSpanSize(mRowSizes, row, rowSpan);

			child.Measure(Vector2(measureWidth, measureHeight));

			// Distribute desired size to auto columns (single-span only for simplicity)
			if (hasAutoColumn && colSpan == 1 && GetColumnWidth(col).IsAuto)
			{
				mColumnSizes[col] = Math.Max(mColumnSizes[col], child.DesiredSize.X);
				mColumnSizes[col] = Math.Clamp(mColumnSizes[col], GetColumnMinWidth(col), GetColumnMaxWidth(col));
			}

			// Distribute desired size to auto rows (single-span only for simplicity)
			if (hasAutoRow && rowSpan == 1 && GetRowHeight(row).IsAuto)
			{
				mRowSizes[row] = Math.Max(mRowSizes[row], child.DesiredSize.Y);
				mRowSizes[row] = Math.Clamp(mRowSizes[row], GetRowMinHeight(row), GetRowMaxHeight(row));
			}
		}
	}

	private void DistributeStarSizes(float availableWidth, float availableHeight, int32 rowCount, int32 colCount)
	{
		// Calculate remaining space for star columns
		float usedWidth = 0;
		float totalStarWidth = 0;
		for (int32 c = 0; c < colCount; c++)
		{
			let length = GetColumnWidth(c);
			if (length.IsStar)
				totalStarWidth += length.Value;
			else
				usedWidth += mColumnSizes[c];
		}

		float remainingWidth = Math.Max(0, availableWidth - usedWidth);
		if (totalStarWidth > 0)
		{
			let widthPerStar = remainingWidth / totalStarWidth;
			for (int32 c = 0; c < colCount; c++)
			{
				let length = GetColumnWidth(c);
				if (length.IsStar)
				{
					mColumnSizes[c] = Math.Clamp(length.Value * widthPerStar, GetColumnMinWidth(c), GetColumnMaxWidth(c));
				}
			}
		}

		// Calculate remaining space for star rows
		float usedHeight = 0;
		float totalStarHeight = 0;
		for (int32 r = 0; r < rowCount; r++)
		{
			let length = GetRowHeight(r);
			if (length.IsStar)
				totalStarHeight += length.Value;
			else
				usedHeight += mRowSizes[r];
		}

		float remainingHeight = Math.Max(0, availableHeight - usedHeight);
		if (totalStarHeight > 0)
		{
			let heightPerStar = remainingHeight / totalStarHeight;
			for (int32 r = 0; r < rowCount; r++)
			{
				let length = GetRowHeight(r);
				if (length.IsStar)
				{
					mRowSizes[r] = Math.Clamp(length.Value * heightPerStar, GetRowMinHeight(r), GetRowMaxHeight(r));
				}
			}
		}

		// Re-measure children with final sizes
		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			let info = GetOrCreateInfo(child);
			let row = Math.Min(info.Row, rowCount - 1);
			let col = Math.Min(info.Column, colCount - 1);
			let rowSpan = Math.Min(info.RowSpan, rowCount - row);
			let colSpan = Math.Min(info.ColumnSpan, colCount - col);

			let cellWidth = GetSpanSize(mColumnSizes, col, colSpan);
			let cellHeight = GetSpanSize(mRowSizes, row, rowSpan);

			child.Measure(Vector2(cellWidth, cellHeight));
		}
	}

	private float GetSpanSize(float[] sizes, int32 start, int32 span)
	{
		float total = 0;
		for (int32 i = start; i < start + span && i < sizes.Count; i++)
			total += sizes[i];
		return total;
	}

	private float GetSpanOffset(float[] sizes, int32 index)
	{
		float offset = 0;
		for (int32 i = 0; i < index && i < sizes.Count; i++)
			offset += sizes[i];
		return offset;
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		let contentBounds = ContentBounds;
		let rowCount = EffectiveRowCount;
		let colCount = EffectiveColumnCount;

		// Update actual sizes in definitions
		for (int32 r = 0; r < mRowDefinitions.Count && r < rowCount; r++)
			mRowDefinitions[r].[Friend]ActualHeight = mRowSizes[r];

		for (int32 c = 0; c < mColumnDefinitions.Count && c < colCount; c++)
			mColumnDefinitions[c].[Friend]ActualWidth = mColumnSizes[c];

		// Arrange children
		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			let info = GetOrCreateInfo(child);
			let row = Math.Min(info.Row, rowCount - 1);
			let col = Math.Min(info.Column, colCount - 1);
			let rowSpan = Math.Min(info.RowSpan, rowCount - row);
			let colSpan = Math.Min(info.ColumnSpan, colCount - col);

			let x = contentBounds.X + GetSpanOffset(mColumnSizes, col);
			let y = contentBounds.Y + GetSpanOffset(mRowSizes, row);
			let width = GetSpanSize(mColumnSizes, col, colSpan);
			let height = GetSpanSize(mRowSizes, row, rowSpan);

			child.Arrange(RectangleF(x, y, width, height));
		}
	}
}
