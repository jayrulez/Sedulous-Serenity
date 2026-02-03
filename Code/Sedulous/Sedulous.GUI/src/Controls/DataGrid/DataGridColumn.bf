using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.GUI;

/// Sort direction for column sorting.
public enum SortDirection
{
	Ascending,
	Descending
}

/// Base class for DataGrid columns.
/// Defines column properties and how to render/extract cell values.
public abstract class DataGridColumn
{
	private String mHeader ~ delete _;
	private float mWidth = 100;
	private float mMinWidth = 50;
	private float mMaxWidth = float.MaxValue;
	private bool mCanResize = true;
	private bool mCanSort = true;
	private SortDirection? mSortDirection = null;

	/// The column header text.
	public StringView Header
	{
		get => mHeader ?? "";
		set
		{
			if (mHeader == null)
				mHeader = new String();
			mHeader.Set(value);
		}
	}

	/// The column width in pixels.
	public float Width
	{
		get => mWidth;
		set => mWidth = Math.Max(mMinWidth, Math.Min(mMaxWidth, value));
	}

	/// Minimum column width.
	public float MinWidth
	{
		get => mMinWidth;
		set
		{
			mMinWidth = Math.Max(20, value);
			if (mWidth < mMinWidth)
				mWidth = mMinWidth;
		}
	}

	/// Maximum column width.
	public float MaxWidth
	{
		get => mMaxWidth;
		set
		{
			mMaxWidth = value;
			if (mWidth > mMaxWidth)
				mWidth = mMaxWidth;
		}
	}

	/// Whether the column can be resized by dragging.
	public bool CanResize
	{
		get => mCanResize;
		set => mCanResize = value;
	}

	/// Whether the column can be sorted by clicking the header.
	public bool CanSort
	{
		get => mCanSort;
		set => mCanSort = value;
	}

	/// Current sort direction, or null if not sorted.
	public SortDirection? SortDirection
	{
		get => mSortDirection;
		set => mSortDirection = value;
	}

	/// Creates a new column with the given header.
	public this(StringView header)
	{
		Header = header;
	}

	/// Gets the cell value from a row data object.
	/// Override to extract the appropriate field from your data type.
	public abstract Object GetCellValue(Object rowData);

	/// Renders the cell content.
	/// Override for custom cell rendering.
	public virtual void RenderCell(DrawContext ctx, RectangleF bounds, Object cellValue, bool isSelected, bool isHovered)
	{
		// Default: render as text
		let text = cellValue?.ToString(.. scope String()) ?? "";
		let fontSize = 12.0f;
		let textColor = isSelected ? Color(255, 255, 255, 255) : Color(220, 220, 220, 255);
		let textX = bounds.X + 4;
		let textY = bounds.Y + (bounds.Height - fontSize) / 2;
		ctx.DrawText(text, fontSize, .(textX, textY), textColor);
	}

	/// Renders the column header.
	public virtual void RenderHeader(DrawContext ctx, RectangleF bounds, bool isHovered)
	{
		// Header background
		let bgColor = isHovered ? Color(55, 55, 55, 255) : Color(45, 45, 45, 255);
		ctx.FillRect(bounds, bgColor);

		// Header text
		let fontSize = 12.0f;
		let textColor = Color(220, 220, 220, 255);
		let textX = bounds.X + 4;
		let textY = bounds.Y + (bounds.Height - fontSize) / 2;
		ctx.DrawText(mHeader ?? "", fontSize, .(textX, textY), textColor);

		// Sort indicator
		if (mSortDirection != null)
		{
			let indicatorX = bounds.Right - 16;
			let indicatorY = bounds.Y + bounds.Height / 2;
			let indicator = mSortDirection == .Ascending ? "▲" : "▼";
			ctx.DrawText(indicator, 10, .(indicatorX, indicatorY - 5), Color(150, 180, 220, 255));
		}

		// Right border
		ctx.DrawLine(.(bounds.Right - 1, bounds.Y), .(bounds.Right - 1, bounds.Bottom), Color(60, 60, 60, 255), 1);
	}

	/// Compares two cell values for sorting.
	/// Returns negative if a < b, positive if a > b, zero if equal.
	public virtual int CompareCellValues(Object a, Object b)
	{
		if (a == null && b == null) return 0;
		if (a == null) return -1;
		if (b == null) return 1;

		// Try numeric comparison first
		if (let aInt = a as int?)
		{
			if (let bInt = b as int?)
				return aInt <=> bInt;
		}

		if (let aFloat = a as float?)
		{
			if (let bFloat = b as float?)
				return aFloat <=> bFloat;
		}

		// Fall back to string comparison
		let aStr = a.ToString(.. scope String());
		let bStr = b.ToString(.. scope String());
		return aStr.CompareTo(bStr, true);
	}
}
