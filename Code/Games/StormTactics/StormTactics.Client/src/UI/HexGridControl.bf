namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;
using Sedulous.Core;

delegate void HexCellClickedDelegate(int32 col, int32 row);

/// Custom control that renders a flat-top hex grid and handles cell click interaction.
/// Uses the same offset coordinate system (even-r) as the battle hex grid.
class HexGridControl : Control
{
	private int32 mColumns;
	private int32 mRows;
	private float mHexSize; // Outer radius in pixels

	// Per-cell data
	private Color[,] mCellColors ~ delete _;
	private String[,] mCellLabels ~ { for (int r = 0; r < mRows; r++) for (int c = 0; c < mColumns; c++) delete _[r, c]; delete _; };

	// Precomputed hex centers (in local pixel space, after offset)
	private Vector2[,] mCenters ~ delete _;
	private float mTotalWidth;
	private float mTotalHeight;

	// Interaction
	private int32 mHoveredCol = -1;
	private int32 mHoveredRow = -1;

	// Colors
	private Color mEmptyFill = Color(30, 35, 50, 255);
	private Color mHoverFill = Color(50, 55, 75, 255);
	private Color mOutlineColor = Color(60, 70, 90, 255);
	private Color mLabelColor = Color(200, 200, 215);
	private Color mCoordColor = Color(60, 60, 75);

	// Events
	private EventAccessor<HexCellClickedDelegate> mOnCellClicked = new .() ~ delete _;
	public EventAccessor<HexCellClickedDelegate> OnCellClicked => mOnCellClicked;

	/// The control type name for theming.
	protected override StringView ControlTypeName => "HexGridControl";

	public int32 Columns => mColumns;
	public int32 Rows => mRows;

	public this(int32 columns, int32 rows, float hexSize = 34)
	{
		mColumns = columns;
		mRows = rows;
		mHexSize = hexSize;
		mCellColors = new .[rows, columns];
		mCellLabels = new .[rows, columns];
		mCenters = new .[rows, columns];

		IsFocusable = false;
		IsTabStop = false;

		ClearCells();
		ComputeCenters();
	}

	/// Set a cell's display color and label.
	public void SetCell(int32 col, int32 row, Color color, StringView label)
	{
		if (col < 0 || col >= mColumns || row < 0 || row >= mRows) return;
		mCellColors[row, col] = color;
		if (mCellLabels[row, col] != null)
			mCellLabels[row, col].Set(label);
		else
			mCellLabels[row, col] = new String(label);
	}

	/// Reset all cells to empty state.
	public void ClearCells()
	{
		for (int32 r = 0; r < mRows; r++)
		{
			for (int32 c = 0; c < mColumns; c++)
			{
				mCellColors[r, c] = mEmptyFill;
				delete mCellLabels[r, c];
				mCellLabels[r, c] = null;
			}
		}
	}

	// === Hex Math ===

	/// Compute hex center in pixel space from offset coordinates.
	/// Uses the same even-r flat-top formula as the battle grid.
	private Vector2 OffsetToPixel(int32 col, int32 row)
	{
		// Offset → Axial (even-r)
		int32 q = col - (row + (row & 1)) / 2;
		int32 r = row;

		// Axial → Pixel (flat-top)
		float px = mHexSize * 1.5f * (float)q;
		float py = mHexSize * Math.Sqrt(3.0f) * ((float)r + (float)q / 2.0f);
		return .(px, py);
	}

	/// Compute and cache all hex centers, shifted so minimum is at (hexSize, hexSize).
	private void ComputeCenters()
	{
		float minX = float.MaxValue, minY = float.MaxValue;
		float maxX = float.MinValue, maxY = float.MinValue;

		for (int32 r = 0; r < mRows; r++)
		{
			for (int32 c = 0; c < mColumns; c++)
			{
				let p = OffsetToPixel(c, r);
				mCenters[r, c] = p;
				if (p.X < minX) minX = p.X;
				if (p.Y < minY) minY = p.Y;
				if (p.X > maxX) maxX = p.X;
				if (p.Y > maxY) maxY = p.Y;
			}
		}

		// Offset so everything starts at (hexSize, hexSize) with padding
		float padX = mHexSize;
		float padY = mHexSize;
		float shiftX = -minX + padX;
		float shiftY = -minY + padY;

		for (int32 r = 0; r < mRows; r++)
			for (int32 c = 0; c < mColumns; c++)
				mCenters[r, c] = .(mCenters[r, c].X + shiftX, mCenters[r, c].Y + shiftY);

		mTotalWidth = (maxX - minX) + padX * 2 + mHexSize * 2;
		mTotalHeight = (maxY - minY) + padY * 2 + mHexSize * 2;
	}

	/// Get the 6 vertices of a flat-top hex at the given center.
	private void GetHexVertices(Vector2 center, Span<Vector2> verts)
	{
		for (int32 i = 0; i < 6; i++)
		{
			float angle = Math.PI_f / 3.0f * (float)i;
			verts[i] = .(
				center.X + mHexSize * Math.Cos(angle),
				center.Y + mHexSize * Math.Sin(angle)
			);
		}
	}

	/// Find which cell (col, row) a local point falls in. Returns false if none.
	private bool FindCellAtPoint(float localX, float localY, out int32 outCol, out int32 outRow)
	{
		outCol = -1;
		outRow = -1;
		float bestDist = float.MaxValue;

		for (int32 r = 0; r < mRows; r++)
		{
			for (int32 c = 0; c < mColumns; c++)
			{
				let center = mCenters[r, c];
				float dx = localX - center.X;
				float dy = localY - center.Y;
				float dist = dx * dx + dy * dy;
				if (dist < bestDist)
				{
					bestDist = dist;
					outCol = c;
					outRow = r;
				}
			}
		}

		// Check if within the hex (use inner radius as threshold)
		float innerRadius = mHexSize * Math.Sqrt(3.0f) / 2.0f;
		return bestDist <= innerRadius * innerRadius;
	}

	// === Layout ===

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		return .(mTotalWidth, mTotalHeight);
	}

	// === Rendering ===

	protected override void RenderOverride(DrawContext ctx)
	{
		let bounds = ArrangedBounds;
		Vector2[6] verts = default;

		for (int32 r = 0; r < mRows; r++)
		{
			for (int32 c = 0; c < mColumns; c++)
			{
				let center = Vector2(bounds.X + mCenters[r, c].X, bounds.Y + mCenters[r, c].Y);
				GetHexVertices(center, verts);

				// Fill
				Color fill = mCellColors[r, c];
				if (c == mHoveredCol && r == mHoveredRow)
					fill = mHoverFill;
				ctx.FillPolygon(verts, fill);

				// Outline
				ctx.DrawPolygon(verts, mOutlineColor, 1.5f);

				// Coordinate label (small, bottom)
				let coordStr = scope String();
				coordStr.AppendF("{},{}", c, r);
				ctx.DrawText(coordStr, 10, .(center.X - 10, center.Y + mHexSize * 0.35f), mCoordColor);

				// Unit name label (centered)
				let label = mCellLabels[r, c];
				if (label != null && label.Length > 0)
				{
					ctx.DrawText(label, 12, .(center.X - label.Length * 3, center.Y - 6), mLabelColor);
				}
			}
		}
	}

	// === Mouse Handling ===

	protected override void OnMouseMove(MouseEventArgs e)
	{
		base.OnMouseMove(e);
		let localX = e.ScreenX - ArrangedBounds.X;
		let localY = e.ScreenY - ArrangedBounds.Y;

		int32 col, row;
		if (FindCellAtPoint(localX, localY, out col, out row))
		{
			mHoveredCol = col;
			mHoveredRow = row;
		}
		else
		{
			mHoveredCol = -1;
			mHoveredRow = -1;
		}
	}

	protected override void OnMouseLeave(MouseEventArgs e)
	{
		base.OnMouseLeave(e);
		mHoveredCol = -1;
		mHoveredRow = -1;
	}

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		base.OnMouseDown(e);
		if (e.Button != .Left) return;

		let localX = e.ScreenX - ArrangedBounds.X;
		let localY = e.ScreenY - ArrangedBounds.Y;

		int32 col, row;
		if (FindCellAtPoint(localX, localY, out col, out row))
		{
			mOnCellClicked.[Friend]Invoke(col, row);
			e.Handled = true;
		}
	}
}
