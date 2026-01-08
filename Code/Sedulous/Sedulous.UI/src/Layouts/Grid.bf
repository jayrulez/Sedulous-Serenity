using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Defines the sizing behavior for a grid row or column.
public enum GridUnitType
{
	/// Size is a fixed number of pixels.
	Pixel,
	/// Size is determined by content.
	Auto,
	/// Size is a weighted proportion of remaining space.
	Star
}

/// Specifies the height of a row or width of a column in a Grid.
public struct GridLength : IEquatable<GridLength>
{
	public GridUnitType UnitType;
	public float Value;

	public this(float value, GridUnitType unitType = .Pixel)
	{
		Value = value;
		UnitType = unitType;
	}

	/// Creates a pixel-based length.
	public static GridLength Pixel(float pixels) => .(pixels, .Pixel);

	/// Creates an auto-sized length.
	public static GridLength Auto => .(1, .Auto);

	/// Creates a star-sized length with weight 1.
	public static GridLength Star => .(1, .Star);

	/// Creates a star-sized length with specified weight.
	public static GridLength StarWeight(float weight) => .(weight, .Star);

	public bool IsPixel => UnitType == .Pixel;
	public bool IsAuto => UnitType == .Auto;
	public bool IsStar => UnitType == .Star;

	public bool Equals(GridLength other)
	{
		return UnitType == other.UnitType && Value == other.Value;
	}

	public static implicit operator GridLength(float pixels)
	{
		return Pixel(pixels);
	}
}

/// Defines a row in a Grid.
public class RowDefinition
{
	public GridLength Height = .Star;
	public float MinHeight = 0;
	public float MaxHeight = SizeConstraints.Infinity;

	/// The actual height after layout. Set by Grid during arrange.
	public float ActualHeight { get; private set; }

	public void SetActualHeight(float value) { ActualHeight = value; }
}

/// Defines a column in a Grid.
public class ColumnDefinition
{
	public GridLength Width = .Star;
	public float MinWidth = 0;
	public float MaxWidth = SizeConstraints.Infinity;

	/// The actual width after layout. Set by Grid during arrange.
	public float ActualWidth { get; private set; }

	public void SetActualWidth(float value) { ActualWidth = value; }
}

/// Grid attached properties for an element.
struct GridPosition
{
	public int Row;
	public int Column;
	public int RowSpan = 1;
	public int ColumnSpan = 1;
}

/// Arranges children in a grid of rows and columns.
public class Grid : Panel
{
	private List<RowDefinition> mRowDefinitions = new .() ~ DeleteContainerAndItems!(_);
	private List<ColumnDefinition> mColumnDefinitions = new .() ~ DeleteContainerAndItems!(_);
	private Dictionary<UIElement, GridPosition> mPositions = new .() ~ delete _;

	/// Row definitions for the grid.
	public List<RowDefinition> RowDefinitions => mRowDefinitions;

	/// Column definitions for the grid.
	public List<ColumnDefinition> ColumnDefinitions => mColumnDefinitions;

	/// Gets the row index for a child element.
	public int GetRow(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos.Row;
		return 0;
	}

	/// Sets the row index for a child element.
	public void SetRow(UIElement element, int row)
	{
		var pos = GetPosition(element);
		pos.Row = row;
		mPositions[element] = pos;
		InvalidateMeasure();
	}

	/// Gets the column index for a child element.
	public int GetColumn(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos.Column;
		return 0;
	}

	/// Sets the column index for a child element.
	public void SetColumn(UIElement element, int column)
	{
		var pos = GetPosition(element);
		pos.Column = column;
		mPositions[element] = pos;
		InvalidateMeasure();
	}

	/// Gets the row span for a child element.
	public int GetRowSpan(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos.RowSpan;
		return 1;
	}

	/// Sets the row span for a child element.
	public void SetRowSpan(UIElement element, int rowSpan)
	{
		var pos = GetPosition(element);
		pos.RowSpan = Math.Max(1, rowSpan);
		mPositions[element] = pos;
		InvalidateMeasure();
	}

	/// Gets the column span for a child element.
	public int GetColumnSpan(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos.ColumnSpan;
		return 1;
	}

	/// Sets the column span for a child element.
	public void SetColumnSpan(UIElement element, int columnSpan)
	{
		var pos = GetPosition(element);
		pos.ColumnSpan = Math.Max(1, columnSpan);
		mPositions[element] = pos;
		InvalidateMeasure();
	}

	private GridPosition GetPosition(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos;
		return .();
	}

	private int EffectiveRowCount => Math.Max(1, mRowDefinitions.Count);
	private int EffectiveColumnCount => Math.Max(1, mColumnDefinitions.Count);

	private RowDefinition GetRowDef(int index)
	{
		if (index < mRowDefinitions.Count)
			return mRowDefinitions[index];
		return null;
	}

	private ColumnDefinition GetColumnDef(int index)
	{
		if (index < mColumnDefinitions.Count)
			return mColumnDefinitions[index];
		return null;
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		let rowCount = EffectiveRowCount;
		let colCount = EffectiveColumnCount;

		// Initialize row/column sizes
		float[] rowHeights = scope float[rowCount];
		float[] colWidths = scope float[colCount];
		float[] rowStarWeights = scope float[rowCount];
		float[] colStarWeights = scope float[colCount];

		// First pass: calculate fixed and auto sizes
		for (int r = 0; r < rowCount; r++)
		{
			let def = GetRowDef(r);
			if (def != null)
			{
				if (def.Height.IsPixel)
					rowHeights[r] = Math.Clamp(def.Height.Value, def.MinHeight, def.MaxHeight);
				else if (def.Height.IsStar)
					rowStarWeights[r] = def.Height.Value;
			}
			else
			{
				rowStarWeights[r] = 1; // Default star
			}
		}

		for (int c = 0; c < colCount; c++)
		{
			let def = GetColumnDef(c);
			if (def != null)
			{
				if (def.Width.IsPixel)
					colWidths[c] = Math.Clamp(def.Width.Value, def.MinWidth, def.MaxWidth);
				else if (def.Width.IsStar)
					colStarWeights[c] = def.Width.Value;
			}
			else
			{
				colStarWeights[c] = 1; // Default star
			}
		}

		// Measure children and determine auto sizes
		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			let pos = GetPosition(child);
			let row = Math.Min(pos.Row, rowCount - 1);
			let col = Math.Min(pos.Column, colCount - 1);

			// Measure with infinity for auto/star cells
			child.Measure(.Unconstrained);

			// Update auto row heights (only for non-spanning cells for simplicity)
			if (pos.RowSpan == 1)
			{
				let def = GetRowDef(row);
				if (def == null || def.Height.IsAuto)
				{
					rowHeights[row] = Math.Max(rowHeights[row], child.DesiredSize.Height);
				}
			}

			// Update auto column widths
			if (pos.ColumnSpan == 1)
			{
				let def = GetColumnDef(col);
				if (def == null || def.Width.IsAuto)
				{
					colWidths[col] = Math.Max(colWidths[col], child.DesiredSize.Width);
				}
			}
		}

		// Calculate total fixed/auto size and star weights
		var fixedHeight = 0.0f;
		var totalRowStars = 0.0f;
		for (int r = 0; r < rowCount; r++)
		{
			let def = GetRowDef(r);
			if (def == null || def.Height.IsStar)
				totalRowStars += rowStarWeights[r];
			else
				fixedHeight += rowHeights[r];
		}

		var fixedWidth = 0.0f;
		var totalColStars = 0.0f;
		for (int c = 0; c < colCount; c++)
		{
			let def = GetColumnDef(c);
			if (def == null || def.Width.IsStar)
				totalColStars += colStarWeights[c];
			else
				fixedWidth += colWidths[c];
		}

		// For measurement, just return the fixed/auto size
		// Star sizes will be distributed during arrange
		return .(fixedWidth, fixedHeight);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		let rowCount = EffectiveRowCount;
		let colCount = EffectiveColumnCount;

		float[] rowHeights = scope float[rowCount];
		float[] colWidths = scope float[colCount];
		float[] rowStarWeights = scope float[rowCount];
		float[] colStarWeights = scope float[colCount];

		// Calculate fixed, auto, and star sizes
		var fixedHeight = 0.0f;
		var totalRowStars = 0.0f;
		for (int r = 0; r < rowCount; r++)
		{
			let def = GetRowDef(r);
			if (def != null && def.Height.IsPixel)
			{
				rowHeights[r] = Math.Clamp(def.Height.Value, def.MinHeight, def.MaxHeight);
				fixedHeight += rowHeights[r];
			}
			else if (def != null && def.Height.IsAuto)
			{
				// Re-measure for auto
				for (let child in Children)
				{
					if (child.Visibility == .Collapsed)
						continue;
					let pos = GetPosition(child);
					if (pos.Row == r && pos.RowSpan == 1)
						rowHeights[r] = Math.Max(rowHeights[r], child.DesiredSize.Height);
				}
				if (def != null)
					rowHeights[r] = Math.Clamp(rowHeights[r], def.MinHeight, def.MaxHeight);
				fixedHeight += rowHeights[r];
			}
			else
			{
				rowStarWeights[r] = def?.Height.Value ?? 1;
				totalRowStars += rowStarWeights[r];
			}
		}

		var fixedWidth = 0.0f;
		var totalColStars = 0.0f;
		for (int c = 0; c < colCount; c++)
		{
			let def = GetColumnDef(c);
			if (def != null && def.Width.IsPixel)
			{
				colWidths[c] = Math.Clamp(def.Width.Value, def.MinWidth, def.MaxWidth);
				fixedWidth += colWidths[c];
			}
			else if (def != null && def.Width.IsAuto)
			{
				for (let child in Children)
				{
					if (child.Visibility == .Collapsed)
						continue;
					let pos = GetPosition(child);
					if (pos.Column == c && pos.ColumnSpan == 1)
						colWidths[c] = Math.Max(colWidths[c], child.DesiredSize.Width);
				}
				if (def != null)
					colWidths[c] = Math.Clamp(colWidths[c], def.MinWidth, def.MaxWidth);
				fixedWidth += colWidths[c];
			}
			else
			{
				colStarWeights[c] = def?.Width.Value ?? 1;
				totalColStars += colStarWeights[c];
			}
		}

		// Distribute remaining space to star rows/columns
		let remainingHeight = Math.Max(0, contentBounds.Height - fixedHeight);
		let remainingWidth = Math.Max(0, contentBounds.Width - fixedWidth);

		if (totalRowStars > 0)
		{
			let starUnit = remainingHeight / totalRowStars;
			for (int r = 0; r < rowCount; r++)
			{
				if (rowStarWeights[r] > 0)
				{
					let def = GetRowDef(r);
					rowHeights[r] = starUnit * rowStarWeights[r];
					if (def != null)
						rowHeights[r] = Math.Clamp(rowHeights[r], def.MinHeight, def.MaxHeight);
				}
			}
		}

		if (totalColStars > 0)
		{
			let starUnit = remainingWidth / totalColStars;
			for (int c = 0; c < colCount; c++)
			{
				if (colStarWeights[c] > 0)
				{
					let def = GetColumnDef(c);
					colWidths[c] = starUnit * colStarWeights[c];
					if (def != null)
						colWidths[c] = Math.Clamp(colWidths[c], def.MinWidth, def.MaxWidth);
				}
			}
		}

		// Calculate row/column positions
		float[] rowTops = scope float[rowCount + 1];
		float[] colLefts = scope float[colCount + 1];
		rowTops[0] = contentBounds.Y;
		colLefts[0] = contentBounds.X;
		for (int r = 0; r < rowCount; r++)
			rowTops[r + 1] = rowTops[r] + rowHeights[r];
		for (int c = 0; c < colCount; c++)
			colLefts[c + 1] = colLefts[c] + colWidths[c];

		// Store actual sizes
		for (int r = 0; r < mRowDefinitions.Count; r++)
			mRowDefinitions[r].SetActualHeight(rowHeights[r]);
		for (int c = 0; c < mColumnDefinitions.Count; c++)
			mColumnDefinitions[c].SetActualWidth(colWidths[c]);

		// Arrange children
		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			let pos = GetPosition(child);
			let row = Math.Min(pos.Row, rowCount - 1);
			let col = Math.Min(pos.Column, colCount - 1);
			let rowEnd = Math.Min(row + pos.RowSpan, rowCount);
			let colEnd = Math.Min(col + pos.ColumnSpan, colCount);

			let x = colLefts[col];
			let y = rowTops[row];
			let width = colLefts[colEnd] - x;
			let height = rowTops[rowEnd] - y;

			child.Arrange(.(x, y, width, height));
		}
	}
}
