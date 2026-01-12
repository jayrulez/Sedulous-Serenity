using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// Base class for all UI elements.
/// Provides core functionality for layout, rendering, and input handling.
public abstract class UIElement
{
	// Identity
	private UIElementId mId;

	// Tree structure
	internal UIContext mContext;
	private UIElement mParent;
	private List<UIElement> mChildren = new .() ~ DeleteContainerAndItems!(_);

	// Layout properties
	private SizeDimension mWidth = .Auto;
	private SizeDimension mHeight = .Auto;
	private Thickness mMargin;
	private Thickness mPadding;
	private HorizontalAlignment mHorizontalAlignment = .Stretch;
	private VerticalAlignment mVerticalAlignment = .Stretch;
	private float mMinWidth;
	private float mMinHeight;
	private float mMaxWidth = SizeConstraints.Infinity;
	private float mMaxHeight = SizeConstraints.Infinity;

	// Visual properties
	private Visibility mVisibility = .Visible;
	private float mOpacity = 1.0f;
	private Matrix mRenderTransform = Matrix.Identity;
	private Vector2 mRenderTransformOrigin = .(0.5f, 0.5f); // Center by default
	private bool mHasRenderTransform = false;
	private bool mClipToBounds = false;
	private CursorType? mCursor = null; // null = inherit from parent

	// State
	private bool mIsEnabled = true;
	private bool mIsFocused;
	private bool mIsMouseOver;
	private bool mFocusable;

	// Layout state
	private DesiredSize mDesiredSize;
	private RectangleF mBounds;
	private bool mMeasureDirty = true;
	private bool mArrangeDirty = true;

	// Events using EventAccessor from Sedulous.Foundation
	private EventAccessor<delegate void(UIElement)> mOnGotFocusEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement)> mOnLostFocusEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement)> mOnMouseEnterEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement)> mOnMouseLeaveEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement, float, float)> mOnMouseMoveEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement, int, float, float)> mOnMouseDownEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement, int, float, float)> mOnMouseUpEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement, float, float)> mOnMouseWheelEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement, KeyCode, KeyModifiers)> mOnKeyDownEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement, KeyCode, KeyModifiers)> mOnKeyUpEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement, char32)> mOnTextInputEvent = new .() ~ delete _;
	private EventAccessor<delegate void(UIElement)> mOnClickEvent = new .() ~ delete _;

	/// Unique identifier for this element.
	public UIElementId Id
	{
		get => mId;
		set => mId = value;
	}

	/// The UI context this element belongs to.
	public UIContext Context => mContext ?? mParent?.Context;

	/// Parent element in the UI tree.
	public UIElement Parent => mParent;

	/// Children of this element.
	public List<UIElement> Children => mChildren;

	// === Layout Properties ===

	/// Requested width (Fixed, Auto, Fill, or Proportional).
	public SizeDimension Width
	{
		get => mWidth;
		set { mWidth = value; InvalidateMeasure(); }
	}

	/// Requested height (Fixed, Auto, Fill, or Proportional).
	public SizeDimension Height
	{
		get => mHeight;
		set { mHeight = value; InvalidateMeasure(); }
	}

	/// Margin around the element (outside the border).
	public Thickness Margin
	{
		get => mMargin;
		set { mMargin = value; InvalidateMeasure(); }
	}

	/// Padding inside the element (between border and content).
	public Thickness Padding
	{
		get => mPadding;
		set { mPadding = value; InvalidateMeasure(); }
	}

	/// Horizontal alignment within the parent.
	public HorizontalAlignment HorizontalAlignment
	{
		get => mHorizontalAlignment;
		set { mHorizontalAlignment = value; InvalidateArrange(); }
	}

	/// Vertical alignment within the parent.
	public VerticalAlignment VerticalAlignment
	{
		get => mVerticalAlignment;
		set { mVerticalAlignment = value; InvalidateArrange(); }
	}

	/// Minimum width constraint.
	public float MinWidth
	{
		get => mMinWidth;
		set { mMinWidth = value; InvalidateMeasure(); }
	}

	/// Minimum height constraint.
	public float MinHeight
	{
		get => mMinHeight;
		set { mMinHeight = value; InvalidateMeasure(); }
	}

	/// Maximum width constraint.
	public float MaxWidth
	{
		get => mMaxWidth;
		set { mMaxWidth = value; InvalidateMeasure(); }
	}

	/// Maximum height constraint.
	public float MaxHeight
	{
		get => mMaxHeight;
		set { mMaxHeight = value; InvalidateMeasure(); }
	}

	// === Visual Properties ===

	/// Visibility state of the element.
	public Visibility Visibility
	{
		get => mVisibility;
		set
		{
			if (mVisibility != value)
			{
				mVisibility = value;
				InvalidateMeasure();
				InvalidateVisual();

				// Parent also needs to remeasure when child visibility changes
				// (especially Collapsed <-> Visible transitions)
				mParent?.InvalidateMeasure();
			}
		}
	}

	/// Opacity (0.0 = transparent, 1.0 = opaque).
	public float Opacity
	{
		get => mOpacity;
		set { mOpacity = Math.Clamp(value, 0.0f, 1.0f); InvalidateVisual(); }
	}

	/// Transform matrix applied during rendering (does not affect layout).
	public Matrix RenderTransform
	{
		get => mRenderTransform;
		set
		{
			mRenderTransform = value;
			mHasRenderTransform = (value != Matrix.Identity);
			InvalidateVisual();
		}
	}

	/// Origin point for render transform as relative coordinates (0-1).
	/// Default is (0.5, 0.5) for center of element.
	public Vector2 RenderTransformOrigin
	{
		get => mRenderTransformOrigin;
		set { mRenderTransformOrigin = value; InvalidateVisual(); }
	}

	/// Whether to clip child content to this element's bounds.
	public bool ClipToBounds
	{
		get => mClipToBounds;
		set { mClipToBounds = value; InvalidateVisual(); }
	}

	/// Cursor to display when mouse is over this element.
	/// null means inherit from parent (default).
	public CursorType? Cursor
	{
		get => mCursor;
		set => mCursor = value;
	}

	/// Gets the effective cursor for this element (resolves inheritance).
	public CursorType EffectiveCursor
	{
		get
		{
			if (mCursor.HasValue)
				return mCursor.Value;
			if (mParent != null)
				return mParent.EffectiveCursor;
			return .Default;
		}
	}

	// === State Properties ===

	/// Whether the element is enabled for interaction.
	public bool IsEnabled
	{
		get => mIsEnabled && (mParent?.IsEnabled ?? true);
		set { mIsEnabled = value; InvalidateVisual(); }
	}

	/// Whether the element currently has focus.
	public bool IsFocused => mIsFocused;

	/// Whether the mouse is currently over the element.
	public bool IsMouseOver => mIsMouseOver;

	/// Whether the element can receive focus.
	public bool Focusable
	{
		get => mFocusable;
		set => mFocusable = value;
	}

	// === Layout Results ===

	/// The desired size calculated during the measure pass.
	public DesiredSize DesiredSize => mDesiredSize;

	/// The final bounds assigned during the arrange pass.
	public RectangleF Bounds => mBounds;

	/// The content area (bounds minus padding).
	public RectangleF ContentBounds
	{
		get
		{
			return .(
				mBounds.X + mPadding.Left,
				mBounds.Y + mPadding.Top,
				mBounds.Width - mPadding.TotalHorizontal,
				mBounds.Height - mPadding.TotalVertical
			);
		}
	}

	// === Events ===

	/// Fired when the element gains focus.
	public EventAccessor<delegate void(UIElement)> OnGotFocusEvent => mOnGotFocusEvent;

	/// Fired when the element loses focus.
	public EventAccessor<delegate void(UIElement)> OnLostFocusEvent => mOnLostFocusEvent;

	/// Fired when the mouse enters the element.
	public EventAccessor<delegate void(UIElement)> OnMouseEnterEvent => mOnMouseEnterEvent;

	/// Fired when the mouse leaves the element.
	public EventAccessor<delegate void(UIElement)> OnMouseLeaveEvent => mOnMouseLeaveEvent;

	/// Fired when the mouse moves over the element.
	public EventAccessor<delegate void(UIElement, float, float)> OnMouseMoveEvent => mOnMouseMoveEvent;

	/// Fired when a mouse button is pressed.
	public EventAccessor<delegate void(UIElement, int, float, float)> OnMouseDownEvent => mOnMouseDownEvent;

	/// Fired when a mouse button is released.
	public EventAccessor<delegate void(UIElement, int, float, float)> OnMouseUpEvent => mOnMouseUpEvent;

	/// Fired when the mouse wheel is scrolled.
	public EventAccessor<delegate void(UIElement, float, float)> OnMouseWheelEvent => mOnMouseWheelEvent;

	/// Fired when a key is pressed.
	public EventAccessor<delegate void(UIElement, KeyCode, KeyModifiers)> OnKeyDownEvent => mOnKeyDownEvent;

	/// Fired when a key is released.
	public EventAccessor<delegate void(UIElement, KeyCode, KeyModifiers)> OnKeyUpEvent => mOnKeyUpEvent;

	/// Fired when text is input.
	public EventAccessor<delegate void(UIElement, char32)> OnTextInputEvent => mOnTextInputEvent;

	/// Fired when the element is clicked.
	public EventAccessor<delegate void(UIElement)> OnClickEvent => mOnClickEvent;

	// === Tree Manipulation ===

	/// Adds a child element.
	public void AddChild(UIElement child)
	{
		if (child.mParent != null)
			child.mParent.RemoveChild(child);

		child.mParent = this;
		mChildren.Add(child);
		InvalidateMeasure();
	}

	/// Inserts a child at the specified index.
	public void InsertChild(int index, UIElement child)
	{
		if (child.mParent != null)
			child.mParent.RemoveChild(child);

		child.mParent = this;
		mChildren.Insert(index, child);
		InvalidateMeasure();
	}

	/// Removes a child element.
	public bool RemoveChild(UIElement child)
	{
		if (mChildren.Remove(child))
		{
			child.mParent = null;
			InvalidateMeasure();
			return true;
		}
		return false;
	}

	/// Removes all children.
	public void ClearChildren()
	{
		for (let child in mChildren)
		{
			child.mParent = null;
			delete child;
		}
		mChildren.Clear();
		InvalidateMeasure();
	}

	// === Layout ===

	/// Marks the element as needing re-measurement.
	public void InvalidateMeasure()
	{
		if (!mMeasureDirty)
		{
			mMeasureDirty = true;
			mArrangeDirty = true;
			Context?.InvalidateLayout();
		}
	}

	/// Marks the element as needing re-arrangement.
	public void InvalidateArrange()
	{
		if (!mArrangeDirty)
		{
			mArrangeDirty = true;
			Context?.InvalidateLayout();
		}
	}

	/// Marks the element as needing visual update.
	public void InvalidateVisual()
	{
		Context?.InvalidateVisual();
	}

	/// Measures the element to determine its desired size.
	public void Measure(SizeConstraints constraints)
	{
		if (mVisibility == .Collapsed)
		{
			mDesiredSize = .Zero;
			mMeasureDirty = false;
			return;
		}

		// Apply local constraints
		var localConstraints = constraints;
		localConstraints.MinWidth = Math.Max(localConstraints.MinWidth, mMinWidth);
		localConstraints.MinHeight = Math.Max(localConstraints.MinHeight, mMinHeight);
		localConstraints.MaxWidth = Math.Min(localConstraints.MaxWidth, mMaxWidth);
		localConstraints.MaxHeight = Math.Min(localConstraints.MaxHeight, mMaxHeight);

		// Handle fixed sizes
		if (mWidth.IsFixed)
		{
			localConstraints.MinWidth = mWidth.Value;
			localConstraints.MaxWidth = mWidth.Value;
		}
		if (mHeight.IsFixed)
		{
			localConstraints.MinHeight = mHeight.Value;
			localConstraints.MaxHeight = mHeight.Value;
		}

		// Deflate by margin for child measurement
		let innerConstraints = localConstraints.Deflate(mMargin);

		// Measure content (override in subclasses)
		var contentSize = MeasureOverride(innerConstraints);

		// Add padding to content size
		contentSize.Width += mPadding.TotalHorizontal;
		contentSize.Height += mPadding.TotalVertical;

		// Add margin to get desired size
		mDesiredSize = .(
			contentSize.Width + mMargin.TotalHorizontal,
			contentSize.Height + mMargin.TotalVertical
		);

		// Constrain to limits
		mDesiredSize = localConstraints.Constrain(mDesiredSize);

		mMeasureDirty = false;
	}

	/// Override to measure content. Returns the desired content size.
	protected virtual DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Default: measure children and return size of largest
		var maxWidth = 0.0f;
		var maxHeight = 0.0f;

		for (let child in mChildren)
		{
			child.Measure(constraints);
			maxWidth = Math.Max(maxWidth, child.DesiredSize.Width);
			maxHeight = Math.Max(maxHeight, child.DesiredSize.Height);
		}

		return .(maxWidth, maxHeight);
	}

	/// Arranges the element and its children within the final bounds.
	public void Arrange(RectangleF finalRect)
	{
		if (mVisibility == .Collapsed)
		{
			mBounds = .Empty;
			mArrangeDirty = false;
			return;
		}

		// Apply margin
		let availableRect = RectangleF(
			finalRect.X + mMargin.Left,
			finalRect.Y + mMargin.Top,
			Math.Max(0, finalRect.Width - mMargin.TotalHorizontal),
			Math.Max(0, finalRect.Height - mMargin.TotalVertical)
		);

		// Calculate actual size based on alignment
		// Fixed sizes are not stretched, only Auto/Fill sizes respect Stretch alignment
		var actualWidth = mDesiredSize.Width - mMargin.TotalHorizontal;
		var actualHeight = mDesiredSize.Height - mMargin.TotalVertical;

		if (mHorizontalAlignment == .Stretch && !mWidth.IsFixed)
			actualWidth = availableRect.Width;
		if (mVerticalAlignment == .Stretch && !mHeight.IsFixed)
			actualHeight = availableRect.Height;

		// Calculate position based on alignment
		var x = availableRect.X;
		var y = availableRect.Y;

		switch (mHorizontalAlignment)
		{
		case .Left:
			x = availableRect.X;
		case .Center:
			x = availableRect.X + (availableRect.Width - actualWidth) * 0.5f;
		case .Right:
			x = availableRect.X + availableRect.Width - actualWidth;
		case .Stretch:
			x = availableRect.X;
		}

		switch (mVerticalAlignment)
		{
		case .Top:
			y = availableRect.Y;
		case .Center:
			y = availableRect.Y + (availableRect.Height - actualHeight) * 0.5f;
		case .Bottom:
			y = availableRect.Y + availableRect.Height - actualHeight;
		case .Stretch:
			y = availableRect.Y;
		}

		mBounds = .(x, y, actualWidth, actualHeight);

		// Arrange content (override in subclasses)
		ArrangeOverride(ContentBounds);

		mArrangeDirty = false;
	}

	/// Override to arrange children within the content bounds.
	protected virtual void ArrangeOverride(RectangleF contentBounds)
	{
		// Default: arrange all children to fill content bounds
		for (let child in mChildren)
		{
			child.Arrange(contentBounds);
		}
	}

	// === Rendering ===

	/// Renders the element and its children.
	public virtual void Render(DrawContext drawContext)
	{
		if (mVisibility != .Visible || mOpacity <= 0)
			return;

		// Apply opacity to this element and all children
		let needsOpacity = mOpacity < 1.0f;
		if (needsOpacity)
			drawContext.PushOpacity(mOpacity);

		// Apply render transform if set
		Matrix savedTransform = .Identity;
		if (mHasRenderTransform)
		{
			savedTransform = drawContext.GetTransform();

			// Calculate origin in absolute coordinates
			let originX = mBounds.X + mBounds.Width * mRenderTransformOrigin.X;
			let originY = mBounds.Y + mBounds.Height * mRenderTransformOrigin.Y;

			// Apply transform around the origin:
			// 1. Translate to origin
			// 2. Apply the render transform
			// 3. Translate back
			let toOrigin = Matrix.CreateTranslation(-originX, -originY, 0);
			let fromOrigin = Matrix.CreateTranslation(originX, originY, 0);
			let combinedTransform = toOrigin * mRenderTransform * fromOrigin * savedTransform;
			drawContext.SetTransform(combinedTransform);
		}

		// Apply clipping if enabled
		if (mClipToBounds)
			drawContext.PushClipRect(mBounds);

		// Render this element's content
		OnRender(drawContext);

		// Render children
		for (let child in mChildren)
		{
			child.Render(drawContext);
		}

		// Pop clipping
		if (mClipToBounds)
			drawContext.PopClip();

		// Restore transform
		if (mHasRenderTransform)
			drawContext.SetTransform(savedTransform);

		if (needsOpacity)
			drawContext.PopOpacity();
	}

	/// Override to render element content.
	protected virtual void OnRender(DrawContext drawContext)
	{
		// Base class does nothing - subclasses override to draw
	}

	// === Hit Testing ===

	/// Tests if the specified point hits this element or any child.
	/// Returns the deepest element hit, or null if no hit.
	public UIElement HitTest(float x, float y)
	{
		if (mVisibility != .Visible)
			return null;

		// Transform hit point if this element has a render transform
		var hitX = x;
		var hitY = y;

		if (mHasRenderTransform)
		{
			// Calculate the inverse transform to map screen point to local space
			let originX = mBounds.X + mBounds.Width * mRenderTransformOrigin.X;
			let originY = mBounds.Y + mBounds.Height * mRenderTransformOrigin.Y;

			let toOrigin = Matrix.CreateTranslation(-originX, -originY, 0);
			let fromOrigin = Matrix.CreateTranslation(originX, originY, 0);
			let fullTransform = toOrigin * mRenderTransform * fromOrigin;

			// Try to invert the transform
			Matrix inverseTransform;
			if (Matrix.TryInvert(fullTransform, out inverseTransform))
			{
				let transformed = Vector2.Transform(.(x, y), inverseTransform);
				hitX = transformed.X;
				hitY = transformed.Y;
			}
		}

		// Check if point is within bounds
		if (!mBounds.Contains(hitX, hitY))
			return null;

		// Check children in reverse order (front to back)
		// Children use the transformed coordinates relative to this element
		for (int i = mChildren.Count - 1; i >= 0; i--)
		{
			let result = mChildren[i].HitTest(hitX, hitY);
			if (result != null)
				return result;
		}

		// No child hit, return this element
		return this;
	}

	/// Tests if the specified point is within this element's bounds.
	public bool ContainsPoint(float x, float y)
	{
		return mBounds.Contains(x, y);
	}

	// === Tree Searching ===

	/// Finds an element by ID in this element and its descendants.
	public UIElement FindElementById(UIElementId id)
	{
		if (mId == id)
			return this;

		for (let child in mChildren)
		{
			let result = child.FindElementById(id);
			if (result != null)
				return result;
		}

		return null;
	}

	// === Input Handlers (called by UIContext) ===

	protected virtual void OnGotFocus()
	{
		mIsFocused = true;
		mOnGotFocusEvent.[Friend]Invoke(this);
	}

	protected virtual void OnLostFocus()
	{
		mIsFocused = false;
		mOnLostFocusEvent.[Friend]Invoke(this);
	}

	protected virtual void OnMouseEnter()
	{
		mIsMouseOver = true;
		mOnMouseEnterEvent.[Friend]Invoke(this);
	}

	protected virtual void OnMouseLeave()
	{
		mIsMouseOver = false;
		mOnMouseLeaveEvent.[Friend]Invoke(this);
	}

	protected virtual void OnMouseMove(float localX, float localY)
	{
		mOnMouseMoveEvent.[Friend]Invoke(this, localX, localY);
	}

	protected virtual void OnMouseDown(int button, float localX, float localY)
	{
		mOnMouseDownEvent.[Friend]Invoke(this, button, localX, localY);
	}

	protected virtual void OnMouseUp(int button, float localX, float localY)
	{
		mOnMouseUpEvent.[Friend]Invoke(this, button, localX, localY);
	}

	protected virtual void OnMouseWheel(float deltaX, float deltaY)
	{
		mOnMouseWheelEvent.[Friend]Invoke(this, deltaX, deltaY);
	}

	protected virtual void OnKeyDown(KeyCode key, KeyModifiers modifiers)
	{
		mOnKeyDownEvent.[Friend]Invoke(this, key, modifiers);
	}

	protected virtual void OnKeyUp(KeyCode key, KeyModifiers modifiers)
	{
		mOnKeyUpEvent.[Friend]Invoke(this, key, modifiers);
	}

	protected virtual void OnTextInput(char32 character)
	{
		mOnTextInputEvent.[Friend]Invoke(this, character);
	}

	/// Called when the element is clicked (mouse down + up within bounds).
	protected virtual void OnClick()
	{
		mOnClickEvent.[Friend]Invoke(this);
	}

	// === Routed Input Handlers (called by InputManager with event args) ===

	/// Called when the mouse moves over this element (routed event).
	protected virtual void OnMouseMoveRouted(MouseEventArgs args)
	{
		// Default implementation invokes the event
		mOnMouseMoveEvent.[Friend]Invoke(this, args.LocalX, args.LocalY);
	}

	/// Called when a mouse button is pressed (routed event).
	protected virtual void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		mOnMouseDownEvent.[Friend]Invoke(this, (int)args.Button, args.LocalX, args.LocalY);
	}

	/// Called when a mouse button is released (routed event).
	protected virtual void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		mOnMouseUpEvent.[Friend]Invoke(this, (int)args.Button, args.LocalX, args.LocalY);
	}

	/// Called when the mouse wheel is scrolled (routed event).
	protected virtual void OnMouseWheelRouted(MouseWheelEventArgs args)
	{
		mOnMouseWheelEvent.[Friend]Invoke(this, args.DeltaX, args.DeltaY);
	}

	/// Called when a key is pressed (routed event).
	protected virtual void OnKeyDownRouted(KeyEventArgs args)
	{
		mOnKeyDownEvent.[Friend]Invoke(this, args.Key, args.Modifiers);
	}

	/// Called when a key is released (routed event).
	protected virtual void OnKeyUpRouted(KeyEventArgs args)
	{
		mOnKeyUpEvent.[Friend]Invoke(this, args.Key, args.Modifiers);
	}

	/// Called when text is input (routed event).
	protected virtual void OnTextInputRouted(TextInputEventArgs args)
	{
		mOnTextInputEvent.[Friend]Invoke(this, args.Character);
	}
}
