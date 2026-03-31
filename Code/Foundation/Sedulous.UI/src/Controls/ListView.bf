namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// A view that displays a scrollable list of items provided by an IListAdapter.
/// Only creates views for the visible range, recycling off-screen views.
public class ListView : ViewGroup, IAdapterObserver
{
	//==========================================================================
	// Adapter & Recycling
	//==========================================================================

	private IListAdapter mAdapter;
	private ViewRecycler mRecycler = new .() ~ delete _;

	/// Maps adapter position → active (visible) view.
	private Dictionary<int, View> mActiveViews = new .() ~ delete _;

	//==========================================================================
	// Selection
	//==========================================================================

	private SelectionModel mSelectionModel ~ delete _;

	//==========================================================================
	// Scroll State
	//==========================================================================

	private float mScrollY;
	private float mTotalContentHeight;
	private float mViewportWidth;
	private float mViewportHeight;

	//==========================================================================
	// Scrollbar (internal, not in mChildren)
	//==========================================================================

	private ScrollBar mVScrollBar ~ delete _;
	private bool mVScrollVisible;
	private ScrollBarPolicy mVScrollPolicy = .Auto;
	private float mScrollBarThickness = 12;

	//==========================================================================
	// Momentum
	//==========================================================================

	private MomentumHelper mMomentum = .();

	//==========================================================================
	// Item Height
	//==========================================================================

	private float mFixedItemHeight = 0;
	private List<float> mItemHeights ~ delete _;
	private List<float> mItemOffsets ~ delete _;

	//==========================================================================
	// Visible Range
	//==========================================================================

	private int mFirstVisiblePosition = -1;
	private int mLastVisiblePosition = -1;

	//==========================================================================
	// Events
	//==========================================================================

	private EventAccessor<delegate void(ListView, int)> mOnItemClick = new .() ~ delete _;
	private EventAccessor<delegate void(ListView, int)> mOnItemLongPress = new .() ~ delete _;

	//==========================================================================
	// Properties
	//==========================================================================

	public IListAdapter Adapter => mAdapter;

	public SelectionModel SelectionModel
	{
		get => mSelectionModel;
		set
		{
			if (mSelectionModel != value)
			{
				delete mSelectionModel;
				mSelectionModel = value;
				Invalidate();
			}
		}
	}

	/// Set > 0 for fixed item height (faster). Set 0 for variable height.
	public float FixedItemHeight
	{
		get => mFixedItemHeight;
		set
		{
			mFixedItemHeight = Math.Max(0, value);
			InvalidateLayout();
		}
	}

	public float ScrollY
	{
		get => mScrollY;
		set => SetScroll(value);
	}

	public float MaxScrollY => Math.Max(0, mTotalContentHeight - mViewportHeight);
	public float ViewportHeight => mViewportHeight;
	public float TotalContentHeight => mTotalContentHeight;

	public ScrollBarPolicy VerticalScrollBarPolicy
	{
		get => mVScrollPolicy;
		set { mVScrollPolicy = value; InvalidateLayout(); }
	}

	public float MomentumFriction
	{
		get => mMomentum.Friction;
		set { mMomentum.Friction = value; }
	}

	/// Subscribe to item click events (position).
	public EventAccessor<delegate void(ListView, int)> OnItemClick => mOnItemClick;

	/// Subscribe to item long-press events (position).
	public EventAccessor<delegate void(ListView, int)> OnItemLongPress => mOnItemLongPress;

	/// Access the view recycler (for diagnostics/testing).
	public ViewRecycler Recycler => mRecycler;

	//==========================================================================
	// Constructor
	//==========================================================================

	public this()
	{
		ClipToBounds = true;
		Focusable = true;

		mSelectionModel = new SelectionModel();

		mVScrollBar = new ScrollBar(.Vertical);
		mVScrollBar.[Friend]mParent = this;
		mVScrollBar.OnValueChanged.Subscribe(new => OnVScrollChanged);
	}

	//==========================================================================
	// Adapter Management
	//==========================================================================

	public void SetAdapter(IListAdapter adapter)
	{
		if (mAdapter != null)
		{
			mAdapter.UnregisterObserver(this);
			mAdapter = null;
		}

		RecycleAllViews();
		mRecycler.Clear();

		mAdapter = adapter;

		if (mAdapter != null)
			mAdapter.RegisterObserver(this);

		OnDataChanged();
	}

	//==========================================================================
	// IAdapterObserver
	//==========================================================================

	public void OnDataChanged()
	{
		RecycleAllViews();
		ComputeTotalContentHeight();
		mScrollY = Math.Clamp(mScrollY, 0, MaxScrollY);
		InvalidateLayout();
	}

	//==========================================================================
	// Scroll
	//==========================================================================

	public void SetScroll(float y)
	{
		float newY = Math.Clamp(y, 0, MaxScrollY);
		if (newY != mScrollY)
		{
			mScrollY = newY;
			InvalidateLayout();
		}
	}

	public void ScrollBy(float dy) => SetScroll(mScrollY + dy);
	public void ScrollToTop() => SetScroll(0);
	public void ScrollToBottom() => SetScroll(MaxScrollY);

	/// Scroll so the item at the given position is visible.
	public void ScrollToPosition(int position)
	{
		if (mAdapter == null || position < 0 || position >= mAdapter.ItemCount)
			return;

		float itemTop = GetItemOffset(position);
		float itemH = GetItemHeight(position);

		if (itemTop < mScrollY)
			SetScroll(itemTop);
		else if (itemTop + itemH > mScrollY + mViewportHeight)
			SetScroll(itemTop + itemH - mViewportHeight);
	}

	public void StopMomentum()
	{
		mMomentum.Stop();
	}

	//==========================================================================
	// Per-Frame Update
	//==========================================================================

	public override void OnTick(float deltaTime)
	{
		if (mMomentum.IsActive)
		{
			let (_, dy) = mMomentum.Update(deltaTime);
			ScrollBy(dy);
		}
	}

	//==========================================================================
	// Measurement
	//==========================================================================

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float selfWidth = widthSpec.Resolve(0, MinWidth, MaxWidth);
		float selfHeight = heightSpec.Resolve(0, MinHeight, MaxHeight);
		SetMeasuredDimension(selfWidth, selfHeight);
	}

	//==========================================================================
	// Layout
	//==========================================================================

	protected override void OnLayout(float width, float height)
	{
		if (mAdapter == null)
		{
			mViewportWidth = width - Padding.Horizontal;
			mViewportHeight = height - Padding.Vertical;
			return;
		}

		mScrollBarThickness = mVScrollBar.Thickness;
		float contentAreaW = width - Padding.Horizontal;
		float contentAreaH = height - Padding.Vertical;

		// Compute total content height
		ComputeTotalContentHeight();

		// Determine scrollbar visibility
		mVScrollVisible = NeedsScrollBar();

		mViewportWidth = contentAreaW - (mVScrollVisible ? mScrollBarThickness : 0);
		mViewportHeight = contentAreaH;

		// Clamp scroll
		mScrollY = Math.Clamp(mScrollY, 0, MaxScrollY);

		// Compute visible range
		int newFirst, newLast;
		ComputeVisibleRange(out newFirst, out newLast);

		// Recycle views outside visible range
		RecycleOutOfRange(newFirst, newLast);

		// Fill visible range with views
		FillVisibleRange(newFirst, newLast);

		mFirstVisiblePosition = newFirst;
		mLastVisiblePosition = newLast;

		// Layout scrollbar
		if (mVScrollVisible)
		{
			float sbH = contentAreaH;
			mVScrollBar.Measure(
				MeasureSpec.MakeExactly(mScrollBarThickness),
				MeasureSpec.MakeExactly(sbH)
			);
			mVScrollBar.Layout(
				width - Padding.Right - mScrollBarThickness,
				Padding.Top,
				mScrollBarThickness,
				sbH
			);
		}

		UpdateScrollBar();
	}

	//==========================================================================
	// Content Height Computation
	//==========================================================================

	private void ComputeTotalContentHeight()
	{
		if (mAdapter == null)
		{
			mTotalContentHeight = 0;
			return;
		}

		int count = mAdapter.ItemCount;

		if (mFixedItemHeight > 0)
		{
			mTotalContentHeight = count * mFixedItemHeight;
		}
		else
		{
			// Variable height: measure all items and cache
			if (mItemHeights == null)
			{
				mItemHeights = new List<float>();
				mItemOffsets = new List<float>();
			}

			// Only recompute if count changed
			if (mItemHeights.Count != count)
			{
				mItemHeights.Clear();
				mItemOffsets.Clear();

				float cumulative = 0;
				mItemOffsets.Add(0);

				float measureWidth = Math.Max(100, mViewportWidth);

				for (int i = 0; i < count; i++)
				{
					int32 viewType = mAdapter.GetItemViewType(i);
					View view = mRecycler.ObtainView(viewType);
					if (view == null)
					{
						view = mAdapter.CreateView(viewType);
						mRecycler.RecordCreation();
					}
					mAdapter.BindView(view, i);

					view.Measure(
						MeasureSpec.MakeExactly(measureWidth),
						MeasureSpec.MakeUnspecified()
					);

					float h = view.MeasuredHeight;
					mItemHeights.Add(h);
					cumulative += h;
					mItemOffsets.Add(cumulative);

					mRecycler.RecycleView(view, viewType);
				}

				mTotalContentHeight = cumulative;
			}
		}
	}

	//==========================================================================
	// Visible Range
	//==========================================================================

	private void ComputeVisibleRange(out int first, out int last)
	{
		if (mAdapter == null || mAdapter.ItemCount == 0 || mViewportHeight <= 0)
		{
			first = -1;
			last = -1;
			return;
		}

		int count = mAdapter.ItemCount;

		if (mFixedItemHeight > 0)
		{
			first = Math.Max(0, (int)(mScrollY / mFixedItemHeight));
			last = Math.Min(count - 1,
				(int)((mScrollY + mViewportHeight) / mFixedItemHeight));
		}
		else
		{
			// Binary search for first visible
			first = BinarySearchOffset(mScrollY);
			// Scan forward for last visible
			float endY = mScrollY + mViewportHeight;
			last = first;
			while (last < count - 1 && GetItemOffset(last + 1) < endY)
				last++;
		}
	}

	/// Binary search in mItemOffsets to find the item containing the given Y.
	private int BinarySearchOffset(float y)
	{
		if (mItemOffsets == null || mItemOffsets.Count <= 1)
			return 0;

		int lo = 0;
		int hi = mItemOffsets.Count - 2; // last valid item index
		while (lo < hi)
		{
			int mid = (lo + hi) / 2;
			if (mItemOffsets[mid + 1] <= y)
				lo = mid + 1;
			else
				hi = mid;
		}
		return lo;
	}

	//==========================================================================
	// Recycling
	//==========================================================================

	private void RecycleOutOfRange(int newFirst, int newLast)
	{
		let toRecycle = scope List<int>();

		for (let (pos, _) in mActiveViews)
		{
			if (newFirst < 0 || pos < newFirst || pos > newLast)
				toRecycle.Add(pos);
		}

		for (let pos in toRecycle)
		{
			let view = mActiveViews[pos];
			int32 viewType = mAdapter.GetItemViewType(pos);

			if (Context != null)
				Context.NotifyElementDeleted(view);

			view.[Friend]SetParent(null);
			if (Context != null)
				view.OnDetachedFromContext(Context);
			[Friend]mChildren.Remove(view);
			mRecycler.RecycleView(view, viewType);
			mActiveViews.Remove(pos);
		}
	}

	private void FillVisibleRange(int firstPos, int lastPos)
	{
		if (mAdapter == null || firstPos < 0)
			return;

		for (int pos = firstPos; pos <= lastPos; pos++)
		{
			if (mActiveViews.ContainsKey(pos))
			{
				// Already have a view, just relayout
				LayoutItem(mActiveViews[pos], pos);
				continue;
			}

			int32 viewType = mAdapter.GetItemViewType(pos);
			View view = mRecycler.ObtainView(viewType);

			if (view == null)
			{
				view = mAdapter.CreateView(viewType);
				mRecycler.RecordCreation();
			}

			mAdapter.BindView(view, pos);
			mActiveViews[pos] = view;

			// Add as child without triggering full layout cycle
			view.[Friend]SetParent(this);
			[Friend]EnsureLayoutParams(view);
			[Friend]mChildren.Add(view);
			if (Context != null)
				view.OnAttachedToContext(Context);

			// Measure
			let widthSpec = MeasureSpec.MakeExactly(mViewportWidth);
			let heightSpec = (mFixedItemHeight > 0)
				? MeasureSpec.MakeExactly(mFixedItemHeight)
				: MeasureSpec.MakeUnspecified();
			view.Measure(widthSpec, heightSpec);

			LayoutItem(view, pos);
		}
	}

	private void LayoutItem(View view, int pos)
	{
		float itemY = GetItemOffset(pos) - mScrollY + Padding.Top;
		float itemH = (mFixedItemHeight > 0) ? mFixedItemHeight : view.MeasuredHeight;
		view.Layout(Padding.Left, itemY, mViewportWidth, itemH);
	}

	private void RecycleAllViews()
	{
		for (let (pos, view) in mActiveViews)
		{
			// Clear input state before recycling — the InputManager may hold
			// a reference to this view as pressed/hovered, which would go stale.
			if (Context != null)
				Context.NotifyElementDeleted(view);

			view.[Friend]SetParent(null);
			if (Context != null)
				view.OnDetachedFromContext(Context);
			[Friend]mChildren.Remove(view);

			if (mAdapter != null)
			{
				int32 viewType = mAdapter.GetItemViewType(pos);
				mRecycler.RecycleView(view, viewType);
			}
			else
			{
				delete view;
			}
		}
		mActiveViews.Clear();

		mFirstVisiblePosition = -1;
		mLastVisiblePosition = -1;

		// Clear cached variable heights
		if (mItemHeights != null)
		{
			mItemHeights.Clear();
			mItemOffsets.Clear();
		}
	}

	//==========================================================================
	// Item Height Helpers
	//==========================================================================

	private float GetItemOffset(int position)
	{
		if (mFixedItemHeight > 0)
			return position * mFixedItemHeight;
		if (mItemOffsets != null && position < mItemOffsets.Count)
			return mItemOffsets[position];
		return 0;
	}

	private float GetItemHeight(int position)
	{
		if (mFixedItemHeight > 0)
			return mFixedItemHeight;
		if (mItemHeights != null && position < mItemHeights.Count)
			return mItemHeights[position];
		return 0;
	}

	//==========================================================================
	// Scrollbar
	//==========================================================================

	private bool NeedsScrollBar()
	{
		if (mVScrollPolicy == .Never) return false;
		if (mVScrollPolicy == .Always) return true;
		return mTotalContentHeight > mViewportHeight;
	}

	private void UpdateScrollBar()
	{
		mVScrollBar.Min = 0;
		mVScrollBar.Max = Math.Max(0, mTotalContentHeight);
		mVScrollBar.ViewportSize = mViewportHeight;
		mVScrollBar.Value = mScrollY;
	}

	private void OnVScrollChanged(ScrollBar sb, float value)
	{
		mScrollY = value;
		InvalidateLayout();
	}

	//==========================================================================
	// Drawing
	//==========================================================================

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		ctx.PushClipRect(.(Padding.Left, Padding.Top, mViewportWidth, mViewportHeight));

		// Draw selection highlights behind items
		if (mSelectionModel != null && mSelectionModel.Count > 0)
		{
			let selColor = theme?.GetColor("ListView", "selection")
				?? Color(palette.Accent.R, palette.Accent.G, palette.Accent.B, 60);

			for (let (pos, _) in mActiveViews)
			{
				if (mSelectionModel.IsSelected(pos))
				{
					float itemY = GetItemOffset(pos) - mScrollY + Padding.Top;
					float itemH = GetItemHeight(pos);
					ctx.FillRect(.(Padding.Left, itemY, mViewportWidth, itemH), selColor);
				}
			}
		}

		// Draw visible items
		for (let (_, view) in mActiveViews)
			view.Draw(ctx);

		ctx.PopClip();

		// Draw scrollbar outside clip
		if (mVScrollVisible)
			mVScrollBar.Draw(ctx);
	}

	//==========================================================================
	// Hit Testing
	//==========================================================================

	public override View HitTest(Vector2 point)
	{
		if (Visibility != .Visible || !IsHitTestVisible || IsPendingDeletion)
			return null;

		var localPoint = PointToLocal(point);

		if (localPoint.X < 0 || localPoint.Y < 0 || localPoint.X > Width || localPoint.Y > Height)
			return null;

		// Test scrollbar first
		if (mVScrollVisible)
		{
			let hit = mVScrollBar.HitTest(localPoint);
			if (hit != null) return hit;
		}

		// Test items within viewport
		if (localPoint.X >= Padding.Left && localPoint.X <= Padding.Left + mViewportWidth &&
			localPoint.Y >= Padding.Top && localPoint.Y <= Padding.Top + mViewportHeight)
		{
			for (int i = ChildCount - 1; i >= 0; i--)
			{
				let child = GetChildAt(i);
				let hit = child.HitTest(localPoint);
				if (hit != null) return hit;
			}
		}

		return this;
	}

	//==========================================================================
	// Input
	//==========================================================================

	/// Convert a local Y coordinate to an adapter position.
	public int PositionFromY(float localY)
	{
		float contentY = localY - Padding.Top + mScrollY;
		if (mAdapter == null || contentY < 0)
			return -1;

		int count = mAdapter.ItemCount;

		if (mFixedItemHeight > 0)
		{
			int pos = (int)(contentY / mFixedItemHeight);
			return (pos >= 0 && pos < count) ? pos : -1;
		}
		else
		{
			int pos = BinarySearchOffset(contentY);
			return (pos >= 0 && pos < count) ? pos : -1;
		}
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		int pos = PositionFromY(e.LocalY);
		if (pos >= 0 && pos < mAdapter.ItemCount)
		{
			if (mSelectionModel != null && mSelectionModel.Mode != .None)
			{
				if (e.HasModifier(.Ctrl) && mSelectionModel.Mode == .Multiple)
					mSelectionModel.Toggle(pos);
				else
					mSelectionModel.Select(pos);
				Invalidate();
			}

			mOnItemClick.[Friend]Invoke(this, pos);
			e.Handled = true;
		}
	}

	public override void OnMouseWheel(MouseWheelEventArgs e)
	{
		float amount = mVScrollBar.SmallChange * 3;
		float delta = -e.DeltaY * amount;
		if (delta != 0 && MaxScrollY > 0)
		{
			ScrollBy(delta);
			mMomentum.Stop();
			e.Handled = true;
		}
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (!Enabled || mAdapter == null) return;

		if (mSelectionModel != null && mSelectionModel.Mode != .None)
		{
			int current = mSelectionModel.SelectedPosition;
			int count = mAdapter.ItemCount;

			switch (e.Key)
			{
			case .Down:
				int next = Math.Min((current < 0 ? -1 : current) + 1, count - 1);
				if (next >= 0)
				{
					mSelectionModel.Select(next);
					ScrollToPosition(next);
					Invalidate();
				}
				e.Handled = true;
			case .Up:
				int prev = Math.Max((current < 0 ? count : current) - 1, 0);
				if (prev >= 0 && count > 0)
				{
					mSelectionModel.Select(prev);
					ScrollToPosition(prev);
					Invalidate();
				}
				e.Handled = true;
			case .PageDown:
				if (count > 0)
				{
					int pageItems = Math.Max(1, (int)(mViewportHeight / GetItemHeight(Math.Max(0, current))) - 1);
					int target = Math.Min((current < 0 ? 0 : current) + pageItems, count - 1);
					mSelectionModel.Select(target);
					ScrollToPosition(target);
					Invalidate();
				}
				e.Handled = true;
			case .PageUp:
				if (count > 0)
				{
					int pageItems = Math.Max(1, (int)(mViewportHeight / GetItemHeight(Math.Max(0, current))) - 1);
					int target = Math.Max((current < 0 ? 0 : current) - pageItems, 0);
					mSelectionModel.Select(target);
					ScrollToPosition(target);
					Invalidate();
				}
				e.Handled = true;
			case .Home:
				if (count > 0)
				{
					mSelectionModel.Select(0);
					ScrollToPosition(0);
					Invalidate();
				}
				e.Handled = true;
			case .End:
				if (count > 0)
				{
					mSelectionModel.Select(count - 1);
					ScrollToPosition(count - 1);
					Invalidate();
				}
				e.Handled = true;
			default:
			}
		}
	}

	//==========================================================================
	// Lifecycle
	//==========================================================================

	public override void OnAttachedToContext(UIContext context)
	{
		base.OnAttachedToContext(context);
		mVScrollBar.OnAttachedToContext(context);
	}

	public override void OnDetachedFromContext(UIContext context)
	{
		mVScrollBar.OnDetachedFromContext(context);
		base.OnDetachedFromContext(context);
	}
}
