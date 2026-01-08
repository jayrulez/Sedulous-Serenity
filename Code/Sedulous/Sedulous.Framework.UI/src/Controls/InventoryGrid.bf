using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.UI;

namespace Sedulous.Framework.UI;

/// Represents a single slot in the inventory grid.
class InventorySlot
{
	private int32 mIndex;
	private TextureHandle mIcon;
	private int32 mStackCount = 0;
	private Object mItemData;
	private Color mBackgroundColor = Color(60, 60, 60, 255);
	private Color mHighlightColor = Color(100, 149, 237, 255);
	private bool mIsHighlighted = false;
	private bool mIsLocked = false;

	/// Gets the slot index.
	public int32 Index => mIndex;

	/// Gets or sets the icon texture.
	public TextureHandle Icon
	{
		get => mIcon;
		set => mIcon = value;
	}

	/// Gets or sets the stack count.
	public int32 StackCount
	{
		get => mStackCount;
		set => mStackCount = value;
	}

	/// Gets whether the slot is empty.
	public bool IsEmpty => !mIcon.IsValid && mItemData == null;

	/// Gets or sets the item data.
	public Object ItemData
	{
		get => mItemData;
		set => mItemData = value;
	}

	/// Gets or sets the background color.
	public Color BackgroundColor
	{
		get => mBackgroundColor;
		set => mBackgroundColor = value;
	}

	/// Gets or sets the highlight color.
	public Color HighlightColor
	{
		get => mHighlightColor;
		set => mHighlightColor = value;
	}

	/// Gets or sets whether the slot is highlighted.
	public bool IsHighlighted
	{
		get => mIsHighlighted;
		set => mIsHighlighted = value;
	}

	/// Gets or sets whether the slot is locked.
	public bool IsLocked
	{
		get => mIsLocked;
		set => mIsLocked = value;
	}

	public this(int32 index)
	{
		mIndex = index;
	}

	/// Clears the slot.
	public void Clear()
	{
		mIcon = default;
		mStackCount = 0;
		mItemData = null;
		mIsHighlighted = false;
	}
}

/// Inventory grid control for displaying items.
class InventoryGrid : Widget
{
	private int32 mColumns = 8;
	private int32 mRows = 4;
	private float mSlotSize = 48;
	private float mSlotSpacing = 4;
	private List<InventorySlot> mSlots = new .() ~ DeleteContainerAndItems!(_);
	private InventorySlot mHoveredSlot;
	private InventorySlot mDraggedSlot;
	private Vector2 mDragOffset;
	private bool mAllowDragDrop = true;
	private Color mEmptySlotColor = Color(40, 40, 40, 255);
	private Color mSlotBorderColor = Color(80, 80, 80, 255);

	/// Event raised when a slot is clicked.
	public Event<delegate void(InventorySlot)> OnSlotClicked ~ _.Dispose();

	/// Event raised when a slot is right-clicked.
	public Event<delegate void(InventorySlot)> OnSlotRightClicked ~ _.Dispose();

	/// Event raised when an item is moved.
	public Event<delegate void(InventorySlot, InventorySlot)> OnItemMoved ~ _.Dispose();

	/// Gets or sets the number of columns.
	public int32 Columns
	{
		get => mColumns;
		set
		{
			if (mColumns != value)
			{
				mColumns = Math.Max(1, value);
				RebuildSlots();
			}
		}
	}

	/// Gets or sets the number of rows.
	public int32 Rows
	{
		get => mRows;
		set
		{
			if (mRows != value)
			{
				mRows = Math.Max(1, value);
				RebuildSlots();
			}
		}
	}

	/// Gets or sets the slot size.
	public float SlotSize
	{
		get => mSlotSize;
		set
		{
			mSlotSize = Math.Max(16, value);
			InvalidateMeasure();
		}
	}

	/// Gets or sets the spacing between slots.
	public float SlotSpacing
	{
		get => mSlotSpacing;
		set
		{
			mSlotSpacing = Math.Max(0, value);
			InvalidateMeasure();
		}
	}

	/// Gets the inventory slots.
	public List<InventorySlot> Slots => mSlots;

	/// Gets the currently dragged slot.
	public InventorySlot DraggedSlot => mDraggedSlot;

	/// Gets or sets whether drag and drop is allowed.
	public bool AllowDragDrop
	{
		get => mAllowDragDrop;
		set => mAllowDragDrop = value;
	}

	/// Gets or sets the empty slot color.
	public Color EmptySlotColor
	{
		get => mEmptySlotColor;
		set => mEmptySlotColor = value;
	}

	public this()
	{
		RebuildSlots();
	}

	private void RebuildSlots()
	{
		// Preserve existing slot data where possible
		let totalSlots = mColumns * mRows;
		while (mSlots.Count < totalSlots)
		{
			mSlots.Add(new InventorySlot((int32)mSlots.Count));
		}
		while (mSlots.Count > totalSlots)
		{
			delete mSlots.PopBack();
		}
		InvalidateMeasure();
		InvalidateVisual();
	}

	/// Gets a slot by index.
	public InventorySlot GetSlot(int32 index)
	{
		if (index >= 0 && index < mSlots.Count)
			return mSlots[index];
		return null;
	}

	/// Gets a slot at grid position.
	public InventorySlot GetSlotAt(int32 column, int32 row)
	{
		if (column < 0 || column >= mColumns || row < 0 || row >= mRows)
			return null;
		return GetSlot(row * mColumns + column);
	}

	/// Gets the slot at a screen position.
	public InventorySlot GetSlotAtPosition(Vector2 localPos)
	{
		let bounds = ContentBounds;
		let relX = localPos.X - bounds.X;
		let relY = localPos.Y - bounds.Y;

		let cellSize = mSlotSize + mSlotSpacing;
		let col = (int32)(relX / cellSize);
		let row = (int32)(relY / cellSize);

		// Check if within slot bounds (not in spacing)
		let slotX = col * cellSize;
		let slotY = row * cellSize;
		if (relX >= slotX && relX < slotX + mSlotSize &&
			relY >= slotY && relY < slotY + mSlotSize)
		{
			return GetSlotAt(col, row);
		}
		return null;
	}

	/// Clears all slots.
	public void ClearAll()
	{
		for (let slot in mSlots)
		{
			slot.Clear();
		}
		InvalidateVisual();
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let slot = GetSlotAtPosition(e.Position);
		if (slot != mHoveredSlot)
		{
			if (mHoveredSlot != null)
				mHoveredSlot.IsHighlighted = false;
			mHoveredSlot = slot;
			if (mHoveredSlot != null)
				mHoveredSlot.IsHighlighted = true;
			InvalidateVisual();
		}

		// Update drag position
		if (mDraggedSlot != null)
		{
			InvalidateVisual();
		}

		return base.OnMouseMove(e);
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		let slot = GetSlotAtPosition(e.Position);
		if (slot == null)
			return base.OnMouseDown(e);

		if (e.Button == .Left)
		{
			OnSlotClicked(slot);

			// Start drag if allowed and slot has item
			if (mAllowDragDrop && !slot.IsEmpty && !slot.IsLocked)
			{
				mDraggedSlot = slot;
				let bounds = GetSlotBounds(slot.Index);
				mDragOffset = Vector2(e.Position.X - bounds.X, e.Position.Y - bounds.Y);
				Context?.Input.CaptureMouse(this);
			}
		}
		else if (e.Button == .Right)
		{
			OnSlotRightClicked(slot);
		}

		return true;
	}

	protected override bool OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && mDraggedSlot != null)
		{
			let dropSlot = GetSlotAtPosition(e.Position);
			if (dropSlot != null && dropSlot != mDraggedSlot && !dropSlot.IsLocked)
			{
				OnItemMoved(mDraggedSlot, dropSlot);
			}
			mDraggedSlot = null;
			Context?.Input.ReleaseMouse();
			InvalidateVisual();
		}

		return base.OnMouseUp(e);
	}

	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		if (mHoveredSlot != null)
		{
			mHoveredSlot.IsHighlighted = false;
			mHoveredSlot = null;
			InvalidateVisual();
		}
		return base.OnMouseLeave(e);
	}

	private RectangleF GetSlotBounds(int32 index)
	{
		let col = index % mColumns;
		let row = index / mColumns;
		let cellSize = mSlotSize + mSlotSpacing;
		let bounds = ContentBounds;

		return RectangleF(
			bounds.X + col * cellSize,
			bounds.Y + row * cellSize,
			mSlotSize,
			mSlotSize
		);
	}

	protected override void OnRender(DrawContext dc)
	{
		for (let slot in mSlots)
		{
			// Skip dragged slot in its original position
			if (slot == mDraggedSlot)
				continue;

			let bounds = GetSlotBounds(slot.Index);
			RenderSlot(dc, slot, bounds);
		}

		// Draw dragged slot at cursor position
		if (mDraggedSlot != null && Context != null)
		{
			let mousePos = Context.Input.MousePosition;
			let dragBounds = RectangleF(
				mousePos.X - mDragOffset.X,
				mousePos.Y - mDragOffset.Y,
				mSlotSize,
				mSlotSize
			);
			RenderSlot(dc, mDraggedSlot, dragBounds, true);
		}
	}

	private void RenderSlot(DrawContext dc, InventorySlot slot, RectangleF bounds, bool isDragging = false)
	{
		// Background
		Color bgColor = slot.IsEmpty ? mEmptySlotColor : slot.BackgroundColor;
		if (slot.IsHighlighted && !isDragging)
			bgColor = slot.HighlightColor;
		if (slot.IsLocked)
			bgColor = Color(30, 30, 30, 255);

		dc.FillRect(bounds, bgColor);

		// Icon
		if (slot.Icon.IsValid)
		{
			let iconTint = slot.IsLocked ? Color(128, 128, 128, 255) : Color.White;
			dc.DrawImage(slot.Icon, bounds, iconTint);
		}

		// Border
		dc.DrawRect(bounds, mSlotBorderColor, 1);

		// Lock indicator
		if (slot.IsLocked)
		{
			// Draw a simple X
			dc.DrawLine(
				Vector2(bounds.X + 4, bounds.Y + 4),
				Vector2(bounds.X + bounds.Width - 4, bounds.Y + bounds.Height - 4),
				Color(200, 0, 0, 200), 2);
			dc.DrawLine(
				Vector2(bounds.X + bounds.Width - 4, bounds.Y + 4),
				Vector2(bounds.X + 4, bounds.Y + bounds.Height - 4),
				Color(200, 0, 0, 200), 2);
		}
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		let cellSize = mSlotSize + mSlotSpacing;
		return Vector2(
			mColumns * cellSize - mSlotSpacing,
			mRows * cellSize - mSlotSpacing
		);
	}
}
