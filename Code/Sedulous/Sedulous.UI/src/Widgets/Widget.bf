using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Base class for all UI widgets.
abstract class Widget
{
	// Static ID counter for generating unique IDs
	private static uint64 sNextId = 1;

	// Identity
	private WidgetId mId;
	private String mName ~ delete _;

	// Hierarchy
	private Widget mParent;
	private WidgetCollection mChildren ~ delete _;
	private UIContext mContext;

	// Layout properties
	private float mWidth = float.NaN;
	private float mHeight = float.NaN;
	private float mMinWidth = 0;
	private float mMinHeight = 0;
	private float mMaxWidth = float.MaxValue;
	private float mMaxHeight = float.MaxValue;
	private Thickness mMargin = .Zero;
	private Thickness mPadding = .Zero;
	private HorizontalAlignment mHAlign = .Stretch;
	private VerticalAlignment mVAlign = .Stretch;

	// Visual state
	private Visibility mVisibility = .Visible;
	private float mOpacity = 1.0f;
	private bool mIsEnabled = true;
	private bool mClipToBounds = false;

	// Computed layout
	private RectangleF mBounds = .Empty;
	private Vector2 mDesiredSize = .Zero;

	// Layout flags
	private bool mIsMeasureValid = false;
	private bool mIsArrangeValid = false;

	// Focus
	private bool mIsFocusable = false;
	private int mTabIndex = 0;

	// Tooltip
	private String mTooltip ~ delete _;

	// Data context for binding
	private Object mDataContext;

	/// Initializes a new widget.
	public this()
	{
		mId = WidgetId(sNextId++);
		mChildren = new WidgetCollection(this);
	}

	// ============ Properties ============

	/// Gets the unique widget identifier.
	public WidgetId Id => mId;

	/// Gets or sets the widget name.
	public StringView Name
	{
		get => mName ?? "";
		set
		{
			delete mName;
			mName = value.IsEmpty ? null : new String(value);
		}
	}

	/// Gets the parent widget.
	public Widget Parent => mParent;

	/// Gets the children collection.
	public WidgetCollection Children => mChildren;

	/// Gets or sets the UI context.
	public UIContext Context
	{
		get => mContext ?? mParent?.Context;
		set => mContext = value;
	}

	/// Gets or sets the desired width (NaN = auto).
	public float Width
	{
		get => mWidth;
		set { if (mWidth != value) { mWidth = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the desired height (NaN = auto).
	public float Height
	{
		get => mHeight;
		set { if (mHeight != value) { mHeight = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the minimum width.
	public float MinWidth
	{
		get => mMinWidth;
		set { if (mMinWidth != value) { mMinWidth = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the minimum height.
	public float MinHeight
	{
		get => mMinHeight;
		set { if (mMinHeight != value) { mMinHeight = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the maximum width.
	public float MaxWidth
	{
		get => mMaxWidth;
		set { if (mMaxWidth != value) { mMaxWidth = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the maximum height.
	public float MaxHeight
	{
		get => mMaxHeight;
		set { if (mMaxHeight != value) { mMaxHeight = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the margin.
	public Thickness Margin
	{
		get => mMargin;
		set { if (mMargin != value) { mMargin = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the padding.
	public Thickness Padding
	{
		get => mPadding;
		set { if (mPadding != value) { mPadding = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the horizontal alignment.
	public HorizontalAlignment HAlign
	{
		get => mHAlign;
		set { if (mHAlign != value) { mHAlign = value; InvalidateArrange(); } }
	}

	/// Gets or sets the vertical alignment.
	public VerticalAlignment VAlign
	{
		get => mVAlign;
		set { if (mVAlign != value) { mVAlign = value; InvalidateArrange(); } }
	}

	/// Gets or sets the visibility.
	public Visibility Visibility
	{
		get => mVisibility;
		set { if (mVisibility != value) { mVisibility = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the opacity (0-1).
	public float Opacity
	{
		get => mOpacity;
		set => mOpacity = Math.Clamp(value, 0.0f, 1.0f);
	}

	/// Gets or sets whether the widget is enabled.
	public bool IsEnabled
	{
		get => mIsEnabled && (mParent?.IsEnabled ?? true);
		set => mIsEnabled = value;
	}

	/// Gets or sets whether to clip children to bounds.
	public bool ClipToBounds
	{
		get => mClipToBounds;
		set => mClipToBounds = value;
	}

	/// Gets the computed bounds after arrange.
	public RectangleF Bounds => mBounds;

	/// Gets the content bounds (bounds minus padding).
	public RectangleF ContentBounds
	{
		get
		{
			return RectangleF(
				mBounds.X + mPadding.Left,
				mBounds.Y + mPadding.Top,
				Math.Max(0, mBounds.Width - mPadding.HorizontalThickness),
				Math.Max(0, mBounds.Height - mPadding.VerticalThickness)
			);
		}
	}

	/// Gets the desired size after measure.
	public Vector2 DesiredSize => mDesiredSize;

	/// Gets or sets whether the widget is focusable.
	public bool IsFocusable
	{
		get => mIsFocusable;
		set => mIsFocusable = value;
	}

	/// Gets whether the widget is currently focused.
	public bool IsFocused => Context?.Input.FocusedWidget == this;

	/// Gets or sets the tab index for focus navigation.
	public int TabIndex
	{
		get => mTabIndex;
		set => mTabIndex = value;
	}

	/// Gets or sets the tooltip text.
	public StringView Tooltip
	{
		get => mTooltip ?? "";
		set
		{
			delete mTooltip;
			mTooltip = value.IsEmpty ? null : new String(value);
		}
	}

	/// Gets or sets the data context for binding.
	public Object DataContext
	{
		get => mDataContext ?? mParent?.DataContext;
		set => mDataContext = value;
	}

	/// Gets whether this widget is visible (considering all visibility states).
	public bool IsVisible => mVisibility == .Visible && mOpacity > 0 && (mParent?.IsVisible ?? true);

	// ============ Layout Methods ============

	/// Measures the widget and computes desired size.
	public void Measure(Vector2 availableSize)
	{
		if (mVisibility == .Collapsed)
		{
			mDesiredSize = .Zero;
			mIsMeasureValid = true;
			return;
		}

		// Account for margin
		var constrainedSize = Vector2(
			Math.Max(0, availableSize.X - mMargin.HorizontalThickness),
			Math.Max(0, availableSize.Y - mMargin.VerticalThickness)
		);

		// Apply min/max constraints
		constrainedSize.X = ApplyWidthConstraints(constrainedSize.X);
		constrainedSize.Y = ApplyHeightConstraints(constrainedSize.Y);

		// Call override to measure content
		var contentSize = MeasureOverride(constrainedSize);

		// Apply explicit size if set (NaN check: value != value is true for NaN)
		if (mWidth == mWidth)
			contentSize.X = mWidth;
		if (mHeight == mHeight)
			contentSize.Y = mHeight;

		// Apply min/max constraints to result
		contentSize.X = ApplyWidthConstraints(contentSize.X);
		contentSize.Y = ApplyHeightConstraints(contentSize.Y);

		// Add margin to desired size
		mDesiredSize = Vector2(
			contentSize.X + mMargin.HorizontalThickness,
			contentSize.Y + mMargin.VerticalThickness
		);

		mIsMeasureValid = true;
	}

	/// Arranges the widget within the given bounds.
	public void Arrange(RectangleF finalRect)
	{
		if (mVisibility == .Collapsed)
		{
			mBounds = .Empty;
			mIsArrangeValid = true;
			return;
		}

		// Account for margin
		var arrangeRect = RectangleF(
			finalRect.X + mMargin.Left,
			finalRect.Y + mMargin.Top,
			Math.Max(0, finalRect.Width - mMargin.HorizontalThickness),
			Math.Max(0, finalRect.Height - mMargin.VerticalThickness)
		);

		// Compute actual size based on alignment
		var actualWidth = mDesiredSize.X - mMargin.HorizontalThickness;
		var actualHeight = mDesiredSize.Y - mMargin.VerticalThickness;

		// Apply explicit size if set (NaN check: value != value is true for NaN)
		if (mWidth == mWidth)
			actualWidth = mWidth;
		if (mHeight == mHeight)
			actualHeight = mHeight;

		// Apply alignment
		if (mHAlign == .Stretch)
			actualWidth = arrangeRect.Width;
		if (mVAlign == .Stretch)
			actualHeight = arrangeRect.Height;

		// Apply min/max constraints
		actualWidth = ApplyWidthConstraints(actualWidth);
		actualHeight = ApplyHeightConstraints(actualHeight);

		// Compute position based on alignment
		var x = arrangeRect.X;
		var y = arrangeRect.Y;

		switch (mHAlign)
		{
		case .Center:
			x += (arrangeRect.Width - actualWidth) / 2;
		case .Right:
			x += arrangeRect.Width - actualWidth;
		default:
		}

		switch (mVAlign)
		{
		case .Center:
			y += (arrangeRect.Height - actualHeight) / 2;
		case .Bottom:
			y += arrangeRect.Height - actualHeight;
		default:
		}

		mBounds = RectangleF(x, y, actualWidth, actualHeight);

		// Call override to arrange children
		ArrangeOverride(mBounds);

		mIsArrangeValid = true;
	}

	/// Override to measure content. Returns desired size without margin.
	protected virtual Vector2 MeasureOverride(Vector2 availableSize)
	{
		// Default: measure children and return largest
		var maxSize = Vector2.Zero;

		for (let child in mChildren)
		{
			child.Measure(availableSize);
			maxSize.X = Math.Max(maxSize.X, child.DesiredSize.X);
			maxSize.Y = Math.Max(maxSize.Y, child.DesiredSize.Y);
		}

		// Add padding
		maxSize.X += mPadding.HorizontalThickness;
		maxSize.Y += mPadding.VerticalThickness;

		return maxSize;
	}

	/// Override to arrange children.
	protected virtual void ArrangeOverride(RectangleF finalRect)
	{
		// Default: arrange all children to fill content bounds
		let contentBounds = ContentBounds;
		for (let child in mChildren)
		{
			child.Arrange(contentBounds);
		}
	}

	/// Invalidates the measure pass.
	public void InvalidateMeasure()
	{
		mIsMeasureValid = false;
		mIsArrangeValid = false;
		mParent?.InvalidateMeasure();
	}

	/// Invalidates the arrange pass.
	public void InvalidateArrange()
	{
		mIsArrangeValid = false;
		mParent?.InvalidateArrange();
	}

	/// Invalidates the visual (request repaint).
	public void InvalidateVisual()
	{
		// TODO: Notify context of dirty region
	}

	// ============ Rendering ============

	/// Renders the widget.
	public void Render(DrawContext dc)
	{
		if (!IsVisible)
			return;

		// Push clip if needed
		if (mClipToBounds)
			dc.PushClip(mBounds);

		// Render this widget
		OnRender(dc);

		// Render children
		for (let child in mChildren)
		{
			child.Render(dc);
		}

		// Pop clip if needed
		if (mClipToBounds)
			dc.PopClip();
	}

	/// Override to render widget content.
	protected virtual void OnRender(DrawContext dc)
	{
		// Default: no rendering
	}

	// ============ Input Events ============

	/// Called when mouse enters the widget.
	protected virtual bool OnMouseEnter(MouseEventArgs e) => false;

	/// Called when mouse leaves the widget.
	protected virtual bool OnMouseLeave(MouseEventArgs e) => false;

	/// Called when mouse moves over the widget.
	protected virtual bool OnMouseMove(MouseMoveEventArgs e) => false;

	/// Called when a mouse button is pressed.
	protected virtual bool OnMouseDown(MouseButtonEventArgs e) => false;

	/// Called when a mouse button is released.
	protected virtual bool OnMouseUp(MouseButtonEventArgs e) => false;

	/// Called when mouse wheel is scrolled.
	protected virtual bool OnMouseWheel(MouseWheelEventArgs e) => false;

	/// Called when a key is pressed.
	protected virtual bool OnKeyDown(KeyEventArgs e) => false;

	/// Called when a key is released.
	protected virtual bool OnKeyUp(KeyEventArgs e) => false;

	/// Called when text is input.
	protected virtual bool OnTextInput(TextInputEventArgs e) => false;

	/// Called when the widget gains focus.
	protected virtual void OnGotFocus() { }

	/// Called when the widget loses focus.
	protected virtual void OnLostFocus() { }

	// ============ Lifecycle ============

	/// Called when the widget is added to the visual tree.
	protected virtual void OnAttached() { }

	/// Called when the widget is removed from the visual tree.
	protected virtual void OnDetached() { }

	/// Called each frame to update the widget.
	protected virtual void OnUpdate(float deltaTime) { }

	/// Updates the widget and children.
	public void Update(float deltaTime)
	{
		OnUpdate(deltaTime);
		for (let child in mChildren)
		{
			child.Update(deltaTime);
		}
	}

	// ============ Hit Testing ============

	/// Tests if a point is within this widget's bounds.
	public virtual bool HitTest(Vector2 point)
	{
		return mBounds.Contains(point);
	}

	/// Recursively hit tests to find the deepest widget at the point.
	public Widget HitTestRecursive(Vector2 point)
	{
		if (!IsVisible || !HitTest(point))
			return null;

		// Test children in reverse order (top-most first)
		for (int i = mChildren.Count - 1; i >= 0; i--)
		{
			let result = mChildren[i].HitTestRecursive(point);
			if (result != null)
				return result;
		}

		return this;
	}

	// ============ Focus Management ============

	/// Attempts to focus this widget.
	public bool Focus()
	{
		if (!mIsFocusable || !IsEnabled)
			return false;

		Context?.Input.SetFocus(this);
		return true;
	}

	/// Removes focus from this widget.
	public void Unfocus()
	{
		if (IsFocused)
			Context?.Input.ClearFocus();
	}

	// ============ Coordinate Transforms ============

	/// Converts a local point to screen coordinates.
	public Vector2 LocalToScreen(Vector2 localPoint)
	{
		return Vector2(mBounds.X + localPoint.X, mBounds.Y + localPoint.Y);
	}

	/// Converts a screen point to local coordinates.
	public Vector2 ScreenToLocal(Vector2 screenPoint)
	{
		return Vector2(screenPoint.X - mBounds.X, screenPoint.Y - mBounds.Y);
	}

	// ============ Helpers ============

	/// Applies width constraints (min/max).
	private float ApplyWidthConstraints(float width)
	{
		return Math.Clamp(width, mMinWidth, mMaxWidth);
	}

	/// Applies height constraints (min/max).
	private float ApplyHeightConstraints(float height)
	{
		return Math.Clamp(height, mMinHeight, mMaxHeight);
	}
}
