namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Scrollable container that clips content to its viewport.
/// Accepts a single content child via SetContent().
/// Internally manages scrollbar views (not in mChildren).
public class ScrollView : ViewGroup
{
	//==========================================================================
	// Content
	//==========================================================================

	private View mContent;

	//==========================================================================
	// Scroll State
	//==========================================================================

	private float mScrollX;
	private float mScrollY;
	private float mExtentWidth;
	private float mExtentHeight;
	private float mViewportWidth;
	private float mViewportHeight;

	//==========================================================================
	// Scrollbar Management
	//==========================================================================

	private ScrollBar mHScrollBar ~ delete _;
	private ScrollBar mVScrollBar ~ delete _;
	private bool mHScrollVisible;
	private bool mVScrollVisible;
	private ScrollBarPolicy mHScrollPolicy = .Auto;
	private ScrollBarPolicy mVScrollPolicy = .Auto;
	private float mScrollBarThickness = 12;

	//==========================================================================
	// Momentum
	//==========================================================================

	private MomentumHelper mMomentum = .();

	//==========================================================================
	// Configuration
	//==========================================================================

	private float mWheelSpeed = 1.0f;
	private bool mAllowHorizontalScroll = false;
	private bool mAllowVerticalScroll = true;

	//==========================================================================
	// Properties
	//==========================================================================

	public float ScrollX
	{
		get => mScrollX;
		set => SetScroll(value, mScrollY);
	}

	public float ScrollY
	{
		get => mScrollY;
		set => SetScroll(mScrollX, value);
	}

	public float MaxScrollX => Math.Max(0, mExtentWidth - mViewportWidth);
	public float MaxScrollY => Math.Max(0, mExtentHeight - mViewportHeight);
	public float ExtentWidth => mExtentWidth;
	public float ExtentHeight => mExtentHeight;
	public float ViewportWidth => mViewportWidth;
	public float ViewportHeight => mViewportHeight;
	public View Content => mContent;

	public ScrollBarPolicy HorizontalScrollBarPolicy
	{
		get => mHScrollPolicy;
		set { mHScrollPolicy = value; InvalidateLayout(); }
	}

	public ScrollBarPolicy VerticalScrollBarPolicy
	{
		get => mVScrollPolicy;
		set { mVScrollPolicy = value; InvalidateLayout(); }
	}

	public bool AllowHorizontalScroll
	{
		get => mAllowHorizontalScroll;
		set { mAllowHorizontalScroll = value; InvalidateLayout(); }
	}

	public bool AllowVerticalScroll
	{
		get => mAllowVerticalScroll;
		set { mAllowVerticalScroll = value; InvalidateLayout(); }
	}

	public float WheelSpeed
	{
		get => mWheelSpeed;
		set { mWheelSpeed = Math.Max(0, value); }
	}

	public float ScrollBarThickness
	{
		get => mScrollBarThickness;
		set { mScrollBarThickness = Math.Max(4, value); InvalidateLayout(); }
	}

	public float MomentumFriction
	{
		get => mMomentum.Friction;
		set { mMomentum.Friction = value; }
	}

	//==========================================================================
	// Constructor
	//==========================================================================

	public this()
	{
		ClipToBounds = true;

		mVScrollBar = new ScrollBar(.Vertical);
		mHScrollBar = new ScrollBar(.Horizontal);

		// Set parent so ToLocal coordinate chain works for input dispatch
		mVScrollBar.[Friend]mParent = this;
		mHScrollBar.[Friend]mParent = this;

		mVScrollBar.OnValueChanged.Subscribe(new => OnVScrollChanged);
		mHScrollBar.OnValueChanged.Subscribe(new => OnHScrollChanged);
	}

	//==========================================================================
	// Content Management
	//==========================================================================

	/// Set the scrollable content. Replaces any previous content (which is deleted).
	public void SetContent(View content)
	{
		if (mContent == content)
			return;

		if (mContent != null)
		{
			mContent = null;
			RemoveViewAt(0);
		}

		mContent = content;

		if (content != null)
			base.AddView(content);
	}

	//==========================================================================
	// Scroll Methods
	//==========================================================================

	public void SetScroll(float x, float y)
	{
		float newX = Math.Clamp(x, 0, MaxScrollX);
		float newY = Math.Clamp(y, 0, MaxScrollY);

		if (newX != mScrollX || newY != mScrollY)
		{
			mScrollX = newX;
			mScrollY = newY;
			InvalidateLayout();
		}
	}

	public void ScrollBy(float dx, float dy)
	{
		SetScroll(mScrollX + dx, mScrollY + dy);
	}

	public void ScrollToTop()
	{
		SetScroll(mScrollX, 0);
	}

	public void ScrollToBottom()
	{
		SetScroll(mScrollX, MaxScrollY);
	}

	public void ScrollToLeft()
	{
		SetScroll(0, mScrollY);
	}

	public void ScrollToRight()
	{
		SetScroll(MaxScrollX, mScrollY);
	}

	public void StopMomentum()
	{
		mMomentum.Stop();
	}

	/// Scroll to make a child view visible within the viewport.
	public void ScrollToView(View child)
	{
		if (child == null || mContent == null)
			return;

		// Get the child's position in content coordinates
		let screenPos = child.ToScreen(.(0, 0));
		let contentLocal = mContent.ToLocal(screenPos);

		float targetX = mScrollX;
		float targetY = mScrollY;

		// Horizontal adjustment
		if (contentLocal.X < mScrollX)
			targetX = contentLocal.X;
		else if (contentLocal.X + child.Width > mScrollX + mViewportWidth)
			targetX = contentLocal.X + child.Width - mViewportWidth;

		// Vertical adjustment
		if (contentLocal.Y < mScrollY)
			targetY = contentLocal.Y;
		else if (contentLocal.Y + child.Height > mScrollY + mViewportHeight)
			targetY = contentLocal.Y + child.Height - mViewportHeight;

		SetScroll(targetX, targetY);
	}

	//==========================================================================
	// Per-Frame Update (momentum)
	//==========================================================================

	public override void OnTick(float deltaTime)
	{
		if (mMomentum.IsActive)
		{
			let (dx, dy) = mMomentum.Update(deltaTime);
			ScrollBy(dx, dy);
		}
	}

	//==========================================================================
	// Measurement
	//==========================================================================

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float selfWidth = widthSpec.Resolve(0, MinWidth, MaxWidth);
		float selfHeight = heightSpec.Resolve(0, MinHeight, MaxHeight);

		if (mContent != null)
		{
			// Measure content with Unspecified on scrolling axes
			let contentWidthSpec = mAllowHorizontalScroll
				? MeasureSpec.MakeUnspecified()
				: MeasureSpec.MakeAtMost(Math.Max(0, selfWidth - Padding.Horizontal));
			let contentHeightSpec = mAllowVerticalScroll
				? MeasureSpec.MakeUnspecified()
				: MeasureSpec.MakeAtMost(Math.Max(0, selfHeight - Padding.Vertical));

			mContent.Measure(contentWidthSpec, contentHeightSpec);
			mExtentWidth = mContent.MeasuredWidth;
			mExtentHeight = mContent.MeasuredHeight;
		}
		else
		{
			mExtentWidth = 0;
			mExtentHeight = 0;
		}

		SetMeasuredDimension(selfWidth, selfHeight);
	}

	//==========================================================================
	// Layout
	//==========================================================================

	protected override void OnLayout(float width, float height)
	{
		// Sync thickness from theme-aware scrollbar
		mScrollBarThickness = mVScrollBar.Thickness;

		float contentAreaW = width - Padding.Horizontal;
		float contentAreaH = height - Padding.Vertical;

		// Determine scrollbar visibility (with cascading)
		ComputeScrollBarVisibility(contentAreaW, contentAreaH);

		// Compute viewport
		mViewportWidth = contentAreaW - (mVScrollVisible ? mScrollBarThickness : 0);
		mViewportHeight = contentAreaH - (mHScrollVisible ? mScrollBarThickness : 0);

		// Clamp scroll offsets
		mScrollX = Math.Clamp(mScrollX, 0, MaxScrollX);
		mScrollY = Math.Clamp(mScrollY, 0, MaxScrollY);

		// Layout content at negative offset (the trick!)
		if (mContent != null)
		{
			float contentW = Math.Max(mViewportWidth, mExtentWidth);
			float contentH = Math.Max(mViewportHeight, mExtentHeight);
			mContent.Layout(
				Padding.Left - mScrollX,
				Padding.Top - mScrollY,
				contentW,
				contentH
			);
		}

		// Layout scrollbars (internal, not in mChildren)
		if (mVScrollVisible)
		{
			float sbH = contentAreaH - (mHScrollVisible ? mScrollBarThickness : 0);
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

		if (mHScrollVisible)
		{
			float sbW = contentAreaW - (mVScrollVisible ? mScrollBarThickness : 0);
			mHScrollBar.Measure(
				MeasureSpec.MakeExactly(sbW),
				MeasureSpec.MakeExactly(mScrollBarThickness)
			);
			mHScrollBar.Layout(
				Padding.Left,
				height - Padding.Bottom - mScrollBarThickness,
				sbW,
				mScrollBarThickness
			);
		}

		UpdateScrollBars();
	}

	private void ComputeScrollBarVisibility(float areaWidth, float areaHeight)
	{
		// First pass: assume no scrollbars
		mHScrollVisible = false;
		mVScrollVisible = false;

		bool needH = NeedsScrollBar(mExtentWidth, areaWidth, mHScrollPolicy, mAllowHorizontalScroll);
		bool needV = NeedsScrollBar(mExtentHeight, areaHeight, mVScrollPolicy, mAllowVerticalScroll);

		if (needV) mVScrollVisible = true;
		if (needH) mHScrollVisible = true;

		// Second pass: cascading — showing one may trigger the other
		if (mVScrollVisible && !mHScrollVisible)
		{
			float reducedWidth = areaWidth - mScrollBarThickness;
			if (NeedsScrollBar(mExtentWidth, reducedWidth, mHScrollPolicy, mAllowHorizontalScroll))
				mHScrollVisible = true;
		}
		else if (mHScrollVisible && !mVScrollVisible)
		{
			float reducedHeight = areaHeight - mScrollBarThickness;
			if (NeedsScrollBar(mExtentHeight, reducedHeight, mVScrollPolicy, mAllowVerticalScroll))
				mVScrollVisible = true;
		}
	}

	private static bool NeedsScrollBar(float extent, float viewport, ScrollBarPolicy policy, bool allowed)
	{
		if (!allowed || policy == .Never)
			return false;
		if (policy == .Always)
			return true;
		// Auto
		return extent > viewport;
	}

	private void UpdateScrollBars()
	{
		// Vertical scrollbar
		mVScrollBar.Min = 0;
		mVScrollBar.Max = Math.Max(0, mExtentHeight);
		mVScrollBar.ViewportSize = mViewportHeight;
		mVScrollBar.Value = mScrollY;

		// Horizontal scrollbar
		mHScrollBar.Min = 0;
		mHScrollBar.Max = Math.Max(0, mExtentWidth);
		mHScrollBar.ViewportSize = mViewportWidth;
		mHScrollBar.Value = mScrollX;
	}

	//==========================================================================
	// Drawing
	//==========================================================================

	protected override void OnDraw(DrawContext ctx)
	{
		// Draw content clipped to viewport
		if (mContent != null)
		{
			ctx.PushClipRect(.(Padding.Left, Padding.Top, mViewportWidth, mViewportHeight));
			mContent.Draw(ctx);
			ctx.PopClip();
		}

		// Draw scrollbars (within ScrollView bounds but outside viewport clip)
		if (mVScrollVisible)
			mVScrollBar.Draw(ctx);
		if (mHScrollVisible)
			mHScrollBar.Draw(ctx);

		// Corner fill when both scrollbars visible
		if (mHScrollVisible && mVScrollVisible)
		{
			let palette = Context?.Theme?.Palette ?? Palette.Dark;
			float cx = Width - Padding.Right - mScrollBarThickness;
			float cy = Height - Padding.Bottom - mScrollBarThickness;
			ctx.FillRect(.(cx, cy, mScrollBarThickness, mScrollBarThickness), palette.Surface);
		}
	}

	//==========================================================================
	// Hit Testing
	//==========================================================================

	public override View HitTest(Vector2 point)
	{
		if (Visibility != .Visible || !IsHitTestVisible || IsPendingDeletion)
			return null;

		var localPoint = PointToLocal(point);

		// Check bounds
		if (localPoint.X < 0 || localPoint.Y < 0 || localPoint.X > Width || localPoint.Y > Height)
			return null;

		// Test scrollbars first (they overlay content edges)
		if (mVScrollVisible)
		{
			let hit = mVScrollBar.HitTest(localPoint);
			if (hit != null)
				return hit;
		}
		if (mHScrollVisible)
		{
			let hit = mHScrollBar.HitTest(localPoint);
			if (hit != null)
				return hit;
		}

		// Test content (only within viewport bounds)
		if (mContent != null)
		{
			if (localPoint.X >= Padding.Left && localPoint.X <= Padding.Left + mViewportWidth &&
				localPoint.Y >= Padding.Top && localPoint.Y <= Padding.Top + mViewportHeight)
			{
				// Content is at (-ScrollX, -ScrollY). PointToLocal on content
				// subtracts those, effectively adding scroll offset.
				let hit = mContent.HitTest(localPoint);
				if (hit != null)
					return hit;
			}
		}

		return this;
	}

	//==========================================================================
	// Input Handling
	//==========================================================================

	public override void OnMouseWheel(MouseWheelEventArgs e)
	{
		float amount = mVScrollBar.SmallChange * 3 * mWheelSpeed;

		bool horizontal = e.HasModifier(.Shift) || (!mAllowVerticalScroll && mAllowHorizontalScroll);

		if (horizontal && mAllowHorizontalScroll)
		{
			float delta = -e.DeltaY * amount;
			if (delta != 0 && MaxScrollX > 0)
			{
				ScrollBy(delta, 0);
				mMomentum.Stop();
				e.Handled = true;
			}
		}
		else if (mAllowVerticalScroll)
		{
			float delta = -e.DeltaY * amount;
			if (delta != 0 && MaxScrollY > 0)
			{
				ScrollBy(0, delta);
				mMomentum.Stop();
				e.Handled = true;
			}
		}
	}

	//==========================================================================
	// Scrollbar Event Handlers
	//==========================================================================

	private void OnVScrollChanged(ScrollBar sb, float value)
	{
		mScrollY = value;
		InvalidateLayout();
	}

	private void OnHScrollChanged(ScrollBar sb, float value)
	{
		mScrollX = value;
		InvalidateLayout();
	}

	//==========================================================================
	// Lifecycle
	//==========================================================================

	public override void OnAttachedToContext(UIContext context)
	{
		base.OnAttachedToContext(context);
		// Attach internal scrollbars so they can access the theme
		mVScrollBar.OnAttachedToContext(context);
		mHScrollBar.OnAttachedToContext(context);
	}

	public override void OnDetachedFromContext(UIContext context)
	{
		mVScrollBar.OnDetachedFromContext(context);
		mHScrollBar.OnDetachedFromContext(context);
		base.OnDetachedFromContext(context);
	}
}
