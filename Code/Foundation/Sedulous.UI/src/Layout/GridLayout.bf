namespace Sedulous.UI;

using System;
using System.Collections;

/// How a grid row or column is sized.
public enum GridSizeMode
{
	/// Size to fit content.
	Auto,
	/// Fixed pixel size.
	Fixed,
	/// Proportional share of remaining space after Auto and Fixed are resolved.
	Proportional
}

/// Specification for a single grid column or row.
public struct GridSpec
{
	public GridSizeMode Mode;
	/// Pixels for Fixed, weight for Proportional, ignored for Auto.
	public float Value;

	public this(GridSizeMode mode, float value = 0)
	{
		Mode = mode;
		Value = value;
	}

	public static GridSpec Auto => .(.Auto);
	public static GridSpec Pixels(float px) => .(.Fixed, px);
	public static GridSpec Star(float weight = 1) => .(.Proportional, weight);
}

/// A ViewGroup that arranges children in a grid with a fixed number of columns.
/// Row count is determined automatically. Supports row/column spans, per-cell gravity,
/// and column/row specs with Auto/Fixed/Proportional sizing.
public class GridLayout : ViewGroup
{
	/// LayoutParams for GridLayout children.
	public class LayoutParams : Sedulous.UI.LayoutParams
	{
		/// Row index (-1 = auto-assign).
		public int32 Row = -1;
		/// Column index (-1 = auto-assign).
		public int32 Column = -1;
		/// Number of rows this child spans.
		public int32 RowSpan = 1;
		/// Number of columns this child spans.
		public int32 ColumnSpan = 1;
		/// Gravity within the cell.
		public Gravity Gravity = .None;

		public this() : base() { }
		public this(float width, float height) : base(width, height) { }
	}

	/// Number of columns in the grid.
	public int32 ColumnCount = 1;
	/// Spacing between rows.
	public float RowSpacing = 0;
	/// Spacing between columns.
	public float ColumnSpacing = 0;

	// Optional sizing specs (null = default equal-size behavior)
	private List<GridSpec> mColumnSpecs ~ delete _;
	private List<GridSpec> mRowSpecs ~ delete _;

	// Internal state rebuilt each measure pass
	private List<float> mColumnWidths = new .() ~ delete _;
	private List<float> mRowHeights = new .() ~ delete _;
	private List<int32> mChildRows = new .() ~ delete _;
	private List<int32> mChildCols = new .() ~ delete _;

	/// Set column sizing specs. Count should match ColumnCount.
	public void SetColumnSpecs(params Span<GridSpec> specs)
	{
		if (mColumnSpecs == null)
			mColumnSpecs = new .();
		mColumnSpecs.Clear();
		for (let s in specs)
			mColumnSpecs.Add(s);
		InvalidateLayout();
	}

	/// Set row sizing specs.
	public void SetRowSpecs(params Span<GridSpec> specs)
	{
		if (mRowSpecs == null)
			mRowSpecs = new .();
		mRowSpecs.Clear();
		for (let s in specs)
			mRowSpecs.Add(s);
		InvalidateLayout();
	}

	protected override Sedulous.UI.LayoutParams CreateDefaultLayoutParams()
	{
		return new GridLayout.LayoutParams();
	}

	protected override bool CheckLayoutParams(Sedulous.UI.LayoutParams lp)
	{
		return lp != null;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		int32 colCount = Math.Max(1, ColumnCount);

		// Auto-assign row/column positions
		AutoAssignPositions(colCount);

		// Determine row count
		int32 rowCount = 0;
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			int32 row = mChildRows[i];
			int32 rowSpan = 1;
			if (let glp = child.LayoutParams as GridLayout.LayoutParams)
				rowSpan = Math.Max(1, glp.RowSpan);

			rowCount = Math.Max(rowCount, row + rowSpan);
		}

		// Initialize column widths and row heights
		mColumnWidths.Clear();
		mRowHeights.Clear();
		for (int32 c = 0; c < colCount; c++)
			mColumnWidths.Add(0);
		for (int32 r = 0; r < rowCount; r++)
			mRowHeights.Add(0);

		// Measure all children and track max sizes per column/row
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			MeasureChildWithMargins(child, widthSpec, 0, heightSpec, 0);

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;
			int32 col = mChildCols[i];
			int32 row = mChildRows[i];
			int32 colSpan = 1;
			int32 rowSpan = 1;
			if (let glp = lp as GridLayout.LayoutParams)
			{
				colSpan = Math.Max(1, glp.ColumnSpan);
				rowSpan = Math.Max(1, glp.RowSpan);
			}

			// For single-span cells, track the max directly.
			// For multi-span, distribute evenly (simplified).
			float childW = child.MeasuredWidth + margin.Horizontal;
			float childH = child.MeasuredHeight + margin.Vertical;

			if (colSpan == 1)
			{
				if (col < mColumnWidths.Count)
					mColumnWidths[col] = Math.Max(mColumnWidths[col], childW);
			}
			else
			{
				// Distribute width requirement across spanned columns
				float perCol = childW / colSpan;
				for (int32 c = col; c < col + colSpan && c < mColumnWidths.Count; c++)
					mColumnWidths[c] = Math.Max(mColumnWidths[c], perCol);
			}

			if (rowSpan == 1)
			{
				if (row < mRowHeights.Count)
					mRowHeights[row] = Math.Max(mRowHeights[row], childH);
			}
			else
			{
				float perRow = childH / rowSpan;
				for (int32 r = row; r < row + rowSpan && r < mRowHeights.Count; r++)
					mRowHeights[r] = Math.Max(mRowHeights[r], perRow);
			}
		}

		// Apply column specs if set
		if (mColumnSpecs != null && mColumnSpecs.Count > 0)
		{
			float availW = (widthSpec.SpecMode != .Unspecified)
				? widthSpec.Size - Padding.Horizontal - Math.Max(0, mColumnWidths.Count - 1) * ColumnSpacing
				: 0;
			ApplySpecs(mColumnSpecs, mColumnWidths, availW);
		}

		// Apply row specs if set
		if (mRowSpecs != null && mRowSpecs.Count > 0)
		{
			float availH = (heightSpec.SpecMode != .Unspecified)
				? heightSpec.Size - Padding.Vertical - Math.Max(0, mRowHeights.Count - 1) * RowSpacing
				: 0;
			ApplySpecs(mRowSpecs, mRowHeights, availH);
		}

		// Re-measure children in proportional columns/rows so they fill their cells
		ReMeasureProportionalChildren();

		// Sum up total size
		float totalWidth = Padding.Horizontal;
		for (int c = 0; c < mColumnWidths.Count; c++)
			totalWidth += mColumnWidths[c];
		if (mColumnWidths.Count > 1)
			totalWidth += (mColumnWidths.Count - 1) * ColumnSpacing;

		float totalHeight = Padding.Vertical;
		for (int r = 0; r < mRowHeights.Count; r++)
			totalHeight += mRowHeights[r];
		if (mRowHeights.Count > 1)
			totalHeight += (mRowHeights.Count - 1) * RowSpacing;

		SetMeasuredDimension(
			widthSpec.Resolve(totalWidth, MinWidth, MaxWidth),
			heightSpec.Resolve(totalHeight, MinHeight, MaxHeight)
		);
	}

	protected override void OnLayout(float width, float height)
	{
		if (mColumnWidths.Count == 0 && mRowHeights.Count == 0)
			return;

		// Build cumulative offsets
		List<float> colOffsets = scope .();
		float cx = 0;
		for (int c = 0; c < mColumnWidths.Count; c++)
		{
			colOffsets.Add(cx);
			cx += mColumnWidths[c] + ColumnSpacing;
		}

		List<float> rowOffsets = scope .();
		float ry = 0;
		for (int r = 0; r < mRowHeights.Count; r++)
		{
			rowOffsets.Add(ry);
			ry += mRowHeights[r] + RowSpacing;
		}

		// Position each child
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;
			int32 col = mChildCols[i];
			int32 row = mChildRows[i];
			int32 colSpan = 1;
			int32 rowSpan = 1;
			Gravity gravity = .None;

			if (let glp = lp as GridLayout.LayoutParams)
			{
				colSpan = Math.Max(1, glp.ColumnSpan);
				rowSpan = Math.Max(1, glp.RowSpan);
				gravity = glp.Gravity;
			}

			// Calculate cell rectangle
			float cellX = (col < colOffsets.Count) ? colOffsets[col] : 0;
			float cellW = 0;
			for (int32 c = col; c < col + colSpan && c < mColumnWidths.Count; c++)
			{
				cellW += mColumnWidths[c];
				if (c > col) cellW += ColumnSpacing;
			}

			float cellY = (row < rowOffsets.Count) ? rowOffsets[row] : 0;
			float cellH = 0;
			for (int32 r = row; r < row + rowSpan && r < mRowHeights.Count; r++)
			{
				cellH += mRowHeights[r];
				if (r > row) cellH += RowSpacing;
			}

			// Apply gravity within cell
			float outX, outY, outW, outH;
			GravityHelper.Apply(gravity, cellW, cellH,
				child.MeasuredWidth, child.MeasuredHeight, margin,
				out outX, out outY, out outW, out outH);

			child.Layout(Padding.Left + cellX + outX, Padding.Top + cellY + outY, outW, outH);
		}
	}

	/// After proportional column/row sizes are resolved, re-measure children
	/// that live in proportional columns/rows with Exactly specs so they fill
	/// their cells instead of staying at content size.
	private void ReMeasureProportionalChildren()
	{
		bool hasAnyCols = mColumnSpecs != null && mColumnSpecs.Count > 0;
		bool hasAnyRows = mRowSpecs != null && mRowSpecs.Count > 0;
		if (!hasAnyCols && !hasAnyRows) return;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;

			int32 col = mChildCols[i];
			int32 row = mChildRows[i];
			int32 colSpan = 1;
			int32 rowSpan = 1;
			if (let glp = child.LayoutParams as GridLayout.LayoutParams)
			{
				colSpan = Math.Max(1, glp.ColumnSpan);
				rowSpan = Math.Max(1, glp.RowSpan);
			}

			// Check if any spanned column is proportional
			bool inPropCol = false;
			if (hasAnyCols)
				for (int32 c = col; c < col + colSpan && c < mColumnSpecs.Count; c++)
					if (mColumnSpecs[c].Mode == .Proportional) { inPropCol = true; break; }

			// Check if any spanned row is proportional
			bool inPropRow = false;
			if (hasAnyRows)
				for (int32 r = row; r < row + rowSpan && r < mRowSpecs.Count; r++)
					if (mRowSpecs[r].Mode == .Proportional) { inPropRow = true; break; }

			if (!inPropCol && !inPropRow) continue;

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;

			// Compute cell width
			float cellW = 0;
			for (int32 c = col; c < col + colSpan && c < mColumnWidths.Count; c++)
			{
				cellW += mColumnWidths[c];
				if (c > col) cellW += ColumnSpacing;
			}

			// Compute cell height
			float cellH = 0;
			for (int32 r = row; r < row + rowSpan && r < mRowHeights.Count; r++)
			{
				cellH += mRowHeights[r];
				if (r > row) cellH += RowSpacing;
			}

			MeasureSpec cw = inPropCol
				? MeasureSpec.MakeExactly(Math.Max(0, cellW - margin.Horizontal))
				: MeasureSpec.MakeAtMost(Math.Max(0, cellW - margin.Horizontal));
			MeasureSpec ch = inPropRow
				? MeasureSpec.MakeExactly(Math.Max(0, cellH - margin.Vertical))
				: MeasureSpec.MakeAtMost(Math.Max(0, cellH - margin.Vertical));

			child.Measure(cw, ch);
		}
	}

	/// Apply sizing specs to computed sizes.
	/// For Auto: keep content-measured size. For Fixed: use spec value.
	/// For Proportional: distribute remaining space by weight.
	private void ApplySpecs(List<GridSpec> specs, List<float> sizes, float availableSpace)
	{
		float fixedTotal = 0;
		float totalWeight = 0;

		// Pass 1: set Fixed sizes, keep Auto sizes, accumulate Proportional weights
		for (int i = 0; i < sizes.Count; i++)
		{
			if (i < specs.Count)
			{
				let spec = specs[i];
				switch (spec.Mode)
				{
				case .Fixed:
					sizes[i] = spec.Value;
					fixedTotal += spec.Value;
				case .Auto:
					fixedTotal += sizes[i]; // Keep content-measured size
				case .Proportional:
					totalWeight += spec.Value;
				}
			}
			else
			{
				// No spec for this index — treat as Auto
				fixedTotal += sizes[i];
			}
		}

		// Pass 2: distribute remaining space to Proportional
		if (totalWeight > 0 && availableSpace > 0)
		{
			float remaining = Math.Max(0, availableSpace - fixedTotal);
			for (int i = 0; i < sizes.Count && i < specs.Count; i++)
			{
				if (specs[i].Mode == .Proportional)
					sizes[i] = remaining * (specs[i].Value / totalWeight);
			}
		}
	}

	private void AutoAssignPositions(int32 colCount)
	{
		mChildRows.Clear();
		mChildCols.Clear();

		// Ensure lists are sized for all children
		for (int i = 0; i < ChildCount; i++)
		{
			mChildRows.Add(0);
			mChildCols.Add(0);
		}

		// Track occupied cells
		HashSet<int64> occupied = scope .();

		int32 autoRow = 0;
		int32 autoCol = 0;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
			{
				mChildRows[i] = 0;
				mChildCols[i] = 0;
				continue;
			}

			let lp = child.LayoutParams;
			int32 row = -1, col = -1;
			int32 rowSpan = 1, colSpan = 1;

			if (let glp = lp as GridLayout.LayoutParams)
			{
				row = glp.Row;
				col = glp.Column;
				rowSpan = Math.Max(1, glp.RowSpan);
				colSpan = Math.Max(1, glp.ColumnSpan);
			}

			if (row >= 0 && col >= 0)
			{
				// Explicit position
				mChildRows[i] = row;
				mChildCols[i] = col;
			}
			else
			{
				// Auto-assign: find next unoccupied cell that fits the span
				while (true)
				{
					if (autoCol + colSpan > colCount)
					{
						autoCol = 0;
						autoRow++;
					}

					// Check if all cells in the span are free
					bool fits = true;
					for (int32 dr = 0; dr < rowSpan && fits; dr++)
						for (int32 dc = 0; dc < colSpan && fits; dc++)
							if (occupied.Contains(CellKey(autoRow + dr, autoCol + dc)))
								fits = false;

					if (fits)
						break;

					autoCol++;
				}

				row = autoRow;
				col = autoCol;
				mChildRows[i] = row;
				mChildCols[i] = col;

				// Advance auto cursor past this child
				autoCol += colSpan;
				if (autoCol >= colCount)
				{
					autoCol = 0;
					autoRow++;
				}
			}

			// Mark cells as occupied
			for (int32 dr = 0; dr < rowSpan; dr++)
				for (int32 dc = 0; dc < colSpan; dc++)
					occupied.Add(CellKey(row + dr, col + dc));
		}
	}

	private static int64 CellKey(int32 row, int32 col)
	{
		return ((int64)row << 32) | (int64)(uint32)col;
	}
}
