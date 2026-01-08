using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Delegate for creating item containers.
delegate Widget ItemContainerGenerator();

/// Delegate for recycling item containers.
delegate void ItemContainerRecycler(Widget container);

/// Delegate for binding data to a container.
delegate void ItemDataBinder(Widget container, int32 index, Object data);

/// Simple container widget for virtualizing panels.
class VirtualizingContainer : StackPanel
{
}

/// A stack panel that virtualizes its children for efficient rendering of large lists.
/// Only creates UI elements for items that are visible in the viewport.
class VirtualizingStackPanel : Widget
{
	private Orientation mOrientation = .Vertical;
	private float mItemSize = 30; // Fixed item size for uniform virtualization
	private bool mIsUniformSize = true;

	// Data source
	private int32 mItemCount = 0;
	private Object mItemsSource ~ { }; // External reference, not owned

	// Virtualization state
	private int32 mFirstVisibleIndex = 0;
	private int32 mVisibleItemCount = 0;
	private float mScrollOffset = 0;

	// Container management
	private List<Widget> mRealizedContainers = new .() ~ delete _;
	private List<Widget> mRecycledContainers = new .() ~ DeleteContainerAndItems!(_);
	private ItemContainerGenerator mContainerGenerator ~ delete _;
	private ItemContainerRecycler mContainerRecycler ~ delete _;
	private ItemDataBinder mDataBinder ~ delete _;

	// Cached item sizes for non-uniform mode
	private float[] mItemSizes ~ delete _;
	private float[] mItemOffsets ~ delete _;

	/// Gets or sets the orientation.
	public Orientation Orientation
	{
		get => mOrientation;
		set
		{
			if (mOrientation != value)
			{
				mOrientation = value;
				InvalidateVirtualization();
			}
		}
	}

	/// Gets or sets the fixed item size (for uniform virtualization).
	public float ItemSize
	{
		get => mItemSize;
		set
		{
			if (mItemSize != value)
			{
				mItemSize = Math.Max(1, value);
				InvalidateVirtualization();
			}
		}
	}

	/// Gets or sets whether items have uniform size.
	public bool IsUniformSize
	{
		get => mIsUniformSize;
		set
		{
			if (mIsUniformSize != value)
			{
				mIsUniformSize = value;
				InvalidateVirtualization();
			}
		}
	}

	/// Gets or sets the total item count.
	public int32 ItemCount
	{
		get => mItemCount;
		set
		{
			if (mItemCount != value)
			{
				mItemCount = Math.Max(0, value);
				InvalidateVirtualization();
			}
		}
	}

	/// Gets or sets the items source (for data binding).
	public Object ItemsSource
	{
		get => mItemsSource;
		set
		{
			mItemsSource = value;
			InvalidateVirtualization();
		}
	}

	/// Gets or sets the scroll offset.
	public float ScrollOffset
	{
		get => mScrollOffset;
		set
		{
			let newOffset = Math.Max(0, value);
			if (mScrollOffset != newOffset)
			{
				mScrollOffset = newOffset;
				UpdateVirtualization();
			}
		}
	}

	/// Gets the first visible item index.
	public int32 FirstVisibleIndex => mFirstVisibleIndex;

	/// Gets the number of visible items.
	public int32 VisibleItemCount => mVisibleItemCount;

	/// Gets the total extent (scrollable height/width).
	public float TotalExtent => mIsUniformSize ? mItemCount * mItemSize : GetTotalExtentNonUniform();

	/// Sets the container generator delegate.
	public void SetContainerGenerator(ItemContainerGenerator generator)
	{
		delete mContainerGenerator;
		mContainerGenerator = generator;
	}

	/// Sets the container recycler delegate.
	public void SetContainerRecycler(ItemContainerRecycler recycler)
	{
		delete mContainerRecycler;
		mContainerRecycler = recycler;
	}

	/// Sets the data binder delegate.
	public void SetDataBinder(ItemDataBinder binder)
	{
		delete mDataBinder;
		mDataBinder = binder;
	}

	/// Scrolls to make the specified index visible.
	public void ScrollIntoView(int32 index)
	{
		if (index < 0 || index >= mItemCount)
			return;

		let itemOffset = GetItemOffset(index);
		let itemSize = GetItemSize(index);
		let viewportSize = mOrientation == .Vertical ? Bounds.Height : Bounds.Width;

		if (itemOffset < mScrollOffset)
		{
			// Item is above/before viewport
			ScrollOffset = itemOffset;
		}
		else if (itemOffset + itemSize > mScrollOffset + viewportSize)
		{
			// Item is below/after viewport
			ScrollOffset = itemOffset + itemSize - viewportSize;
		}
	}

	/// Invalidates virtualization and forces recalculation.
	public void InvalidateVirtualization()
	{
		RecycleAllContainers();

		if (!mIsUniformSize && mItemCount > 0)
		{
			delete mItemSizes;
			delete mItemOffsets;
			mItemSizes = new float[mItemCount];
			mItemOffsets = new float[mItemCount];

			// Initialize with default size
			for (int32 i = 0; i < mItemCount; i++)
				mItemSizes[i] = mItemSize;

			RecalculateOffsets();
		}

		InvalidateMeasure();
	}

	private void RecalculateOffsets()
	{
		if (mItemOffsets == null || mItemSizes == null)
			return;

		float offset = 0;
		for (int32 i = 0; i < mItemCount; i++)
		{
			mItemOffsets[i] = offset;
			offset += mItemSizes[i];
		}
	}

	private float GetItemOffset(int32 index)
	{
		if (index < 0 || index >= mItemCount)
			return 0;

		if (mIsUniformSize)
			return index * mItemSize;

		if (mItemOffsets != null && index < mItemOffsets.Count)
			return mItemOffsets[index];

		return index * mItemSize;
	}

	private float GetItemSize(int32 index)
	{
		if (mIsUniformSize)
			return mItemSize;

		if (mItemSizes != null && index < mItemSizes.Count)
			return mItemSizes[index];

		return mItemSize;
	}

	private float GetTotalExtentNonUniform()
	{
		if (mItemOffsets == null || mItemSizes == null || mItemCount == 0)
			return 0;

		return mItemOffsets[mItemCount - 1] + mItemSizes[mItemCount - 1];
	}

	private void RecycleAllContainers()
	{
		for (let container in mRealizedContainers)
		{
			Children.Remove(container);
			if (mContainerRecycler != null)
				mContainerRecycler(container);
			mRecycledContainers.Add(container);
		}
		mRealizedContainers.Clear();
	}

	private Widget GetOrCreateContainer()
	{
		if (mRecycledContainers.Count > 0)
		{
			let container = mRecycledContainers.PopBack();
			return container;
		}

		if (mContainerGenerator != null)
			return mContainerGenerator();

		// Default: create a simple container
		return new VirtualizingContainer();
	}

	private void UpdateVirtualization()
	{
		let viewportSize = mOrientation == .Vertical
			? Math.Max(0, Bounds.Height - Padding.VerticalThickness)
			: Math.Max(0, Bounds.Width - Padding.HorizontalThickness);

		if (viewportSize <= 0 || mItemCount == 0)
		{
			RecycleAllContainers();
			mFirstVisibleIndex = 0;
			mVisibleItemCount = 0;
			return;
		}

		// Calculate visible range
		int32 newFirstIndex;
		int32 newLastIndex;

		if (mIsUniformSize)
		{
			newFirstIndex = (int32)(mScrollOffset / mItemSize);
			newLastIndex = (int32)((mScrollOffset + viewportSize) / mItemSize);
		}
		else
		{
			newFirstIndex = FindIndexAtOffset(mScrollOffset);
			newLastIndex = FindIndexAtOffset(mScrollOffset + viewportSize);
		}

		// Add buffer for smooth scrolling
		newFirstIndex = Math.Max(0, newFirstIndex - 1);
		newLastIndex = Math.Min(mItemCount - 1, newLastIndex + 1);

		let newVisibleCount = newLastIndex - newFirstIndex + 1;

		// Check if range changed
		if (newFirstIndex == mFirstVisibleIndex && newVisibleCount == mVisibleItemCount)
		{
			// Just update positions
			UpdateContainerPositions();
			return;
		}

		// Recycle containers outside new range
		for (int32 i = (int32)mRealizedContainers.Count - 1; i >= 0; i--)
		{
			let containerIndex = mFirstVisibleIndex + i;
			if (containerIndex < newFirstIndex || containerIndex > newLastIndex)
			{
				let container = mRealizedContainers[i];
				Children.Remove(container);
				if (mContainerRecycler != null)
					mContainerRecycler(container);
				mRecycledContainers.Add(container);
				mRealizedContainers.RemoveAt(i);
			}
		}

		// Build new container list
		List<Widget> newContainers = scope .();
		for (int32 dataIndex = newFirstIndex; dataIndex <= newLastIndex; dataIndex++)
		{
			Widget container = null;

			// Check if we already have this container
			let oldRelativeIndex = dataIndex - mFirstVisibleIndex;
			if (oldRelativeIndex >= 0 && oldRelativeIndex < mRealizedContainers.Count)
			{
				container = mRealizedContainers[oldRelativeIndex];
			}

			if (container == null)
			{
				// Get or create new container
				container = GetOrCreateContainer();
				Children.Add(container);

				// Bind data
				if (mDataBinder != null)
					mDataBinder(container, dataIndex, mItemsSource);
			}

			newContainers.Add(container);
		}

		// Update state
		mRealizedContainers.Clear();
		for (let c in newContainers)
			mRealizedContainers.Add(c);

		mFirstVisibleIndex = newFirstIndex;
		mVisibleItemCount = newVisibleCount;

		// Update positions
		UpdateContainerPositions();
		InvalidateArrange();
	}

	private int32 FindIndexAtOffset(float offset)
	{
		if (mItemCount == 0)
			return 0;

		if (mIsUniformSize)
			return Math.Clamp((int32)(offset / mItemSize), 0, mItemCount - 1);

		// Binary search for non-uniform
		if (mItemOffsets == null)
			return 0;

		int32 low = 0;
		int32 high = mItemCount - 1;

		while (low < high)
		{
			let mid = (low + high + 1) / 2;
			if (mItemOffsets[mid] <= offset)
				low = mid;
			else
				high = mid - 1;
		}

		return low;
	}

	private void UpdateContainerPositions()
	{
		// Positions are set during ArrangeOverride
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		// Calculate content size
		let extent = TotalExtent;

		// Measure visible containers
		for (let container in mRealizedContainers)
		{
			if (mOrientation == .Vertical)
				container.Measure(Vector2(availableSize.X - Padding.HorizontalThickness, mItemSize));
			else
				container.Measure(Vector2(mItemSize, availableSize.Y - Padding.VerticalThickness));
		}

		if (mOrientation == .Vertical)
		{
			return Vector2(
				Padding.HorizontalThickness,
				extent + Padding.VerticalThickness
			);
		}
		else
		{
			return Vector2(
				extent + Padding.HorizontalThickness,
				Padding.VerticalThickness
			);
		}
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		UpdateVirtualization();

		let contentBounds = ContentBounds;

		for (int32 i = 0; i < mRealizedContainers.Count; i++)
		{
			let container = mRealizedContainers[i];
			let dataIndex = mFirstVisibleIndex + i;

			let itemOffset = GetItemOffset(dataIndex) - mScrollOffset;
			let itemSize = GetItemSize(dataIndex);

			RectangleF childRect;
			if (mOrientation == .Vertical)
			{
				childRect = RectangleF(
					contentBounds.X,
					contentBounds.Y + itemOffset,
					contentBounds.Width,
					itemSize
				);
			}
			else
			{
				childRect = RectangleF(
					contentBounds.X + itemOffset,
					contentBounds.Y,
					itemSize,
					contentBounds.Height
				);
			}

			container.Arrange(childRect);
		}
	}

	/// Updates the size of a specific item (for non-uniform mode).
	public void SetItemSize(int32 index, float size)
	{
		if (mIsUniformSize || mItemSizes == null)
			return;

		if (index >= 0 && index < mItemCount)
		{
			mItemSizes[index] = Math.Max(1, size);
			RecalculateOffsets();
			InvalidateArrange();
		}
	}
}
