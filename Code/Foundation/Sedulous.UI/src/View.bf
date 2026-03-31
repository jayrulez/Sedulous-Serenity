namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// Base class for all UI elements.
/// Handles measurement, layout, drawing, hit-testing, transforms, and state.
public class View
{
	//==========================================================================
	// Identity
	//==========================================================================

	private ViewId mId;
	private View mParent;
	private UIContext mContext;
	private RootView mRootView;

	public ViewId Id => mId;
	public View Parent => mParent;
	public UIContext Context => mContext;

	/// The RootView ancestor for this view (cached on attach).
	public RootView RootView => mRootView;

	//==========================================================================
	// Geometry (relative to parent)
	//==========================================================================

	private float mLeft;
	private float mTop;
	private float mWidth;
	private float mHeight;

	public float Left => mLeft;
	public float Top => mTop;
	public float Width => mWidth;
	public float Height => mHeight;

	//==========================================================================
	// Measurement
	//==========================================================================

	private float mMeasuredWidth;
	private float mMeasuredHeight;
	private bool mLayoutDirty = true;

	public float MeasuredWidth => mMeasuredWidth;
	public float MeasuredHeight => mMeasuredHeight;

	//==========================================================================
	// Layout parameters (set by parent or user)
	//==========================================================================

	private LayoutParams mLayoutParams ~ delete _;

	public LayoutParams LayoutParams
	{
		get => mLayoutParams;
		set
		{
			delete mLayoutParams;
			mLayoutParams = value;
			InvalidateLayout();
		}
	}

	//==========================================================================
	// Padding
	//==========================================================================

	private Thickness mPadding;

	public Thickness Padding
	{
		get => mPadding;
		set
		{
			mPadding = value;
			InvalidateLayout();
		}
	}

	//==========================================================================
	// Constraints
	//==========================================================================

	public float MinWidth;
	public float MinHeight;
	public float MaxWidth;
	public float MaxHeight;

	//==========================================================================
	// Appearance
	//==========================================================================

	private Visibility mVisibility = .Visible;
	private float mAlpha = 1.0f;
	private bool mClipToBounds = false;
	private bool mIsHitTestVisible = true;

	public Visibility Visibility
	{
		get => mVisibility;
		set
		{
			if (mVisibility != value)
			{
				mVisibility = value;
				InvalidateLayout();
			}
		}
	}

	public float Alpha
	{
		get => mAlpha;
		set { mAlpha = Math.Clamp(value, 0.0f, 1.0f); }
	}

	public bool ClipToBounds
	{
		get => mClipToBounds;
		set { mClipToBounds = value; }
	}

	public bool IsHitTestVisible
	{
		get => mIsHitTestVisible;
		set { mIsHitTestVisible = value; }
	}

	//==========================================================================
	// Background
	//==========================================================================

	private Drawable mBackground ~ delete _;

	/// The background drawable for this view.
	public Drawable Background
	{
		get => mBackground;
		set
		{
			if (mBackground != value)
			{
				delete mBackground;
				mBackground = value;
			}
		}
	}

	/// Convenience setter: creates a ColorDrawable as the background.
	public Color BackgroundColor
	{
		set { Background = new ColorDrawable(value); }
	}

	//==========================================================================
	// Cursor
	//==========================================================================

	private CursorType mCursorType = .Default;

	public CursorType CursorType
	{
		get => mCursorType;
		set { mCursorType = value; }
	}

	/// Walk the parent chain to find an explicit cursor.
	/// Returns Default if no ancestor specifies one.
	public CursorType EffectiveCursor
	{
		get
		{
			if (mCursorType != .Default)
				return mCursorType;
			if (mParent != null)
				return mParent.EffectiveCursor;
			return .Default;
		}
	}

	//==========================================================================
	// Render Transform
	//==========================================================================

	private Matrix mRenderTransform = Matrix.Identity;
	private Vector2 mRenderTransformOrigin = .(0.5f, 0.5f);

	/// Arbitrary transform applied during rendering and hit-testing.
	public Matrix RenderTransform
	{
		get => mRenderTransform;
		set { mRenderTransform = value; }
	}

	/// Origin for the render transform, in normalized coordinates (0-1).
	/// Default is (0.5, 0.5) = center of the view.
	public Vector2 RenderTransformOrigin
	{
		get => mRenderTransformOrigin;
		set { mRenderTransformOrigin = value; }
	}

	/// Whether this view has a non-identity render transform.
	public bool HasRenderTransform => mRenderTransform != Matrix.Identity;

	//==========================================================================
	// State
	//==========================================================================

	private bool mEnabled = true;
	private bool mFocusable = false;
	private bool mIsTabStop = true;
	private int32 mTabIndex = 0;

	// These are managed by UIContext/InputManager
	internal bool mIsFocused;
	internal bool mIsHovered;
	internal bool mIsPressed;
	internal bool mIsPendingDeletion;

	public bool Enabled
	{
		get => mEnabled;
		set { mEnabled = value; }
	}

	public bool Focusable
	{
		get => mFocusable;
		set { mFocusable = value; }
	}

	public bool IsTabStop
	{
		get => mIsTabStop;
		set { mIsTabStop = value; }
	}

	public int32 TabIndex
	{
		get => mTabIndex;
		set { mTabIndex = value; }
	}

	public bool IsFocused => mIsFocused;
	public bool IsHovered => mIsHovered;
	public bool IsPressed => mIsPressed;
	public bool IsPendingDeletion => mIsPendingDeletion;

	//==========================================================================
	// Tooltip & Accessibility
	//==========================================================================

	public String TooltipText ~ delete _;
	public String ContentDescription ~ delete _;

	//==========================================================================
	// Tag (user data)
	//==========================================================================

	public String Tag ~ delete _;

	//==========================================================================
	// Constructor
	//==========================================================================

	public this()
	{
		mId = ViewId.Generate();
	}

	public ~this()
	{
	}

	//==========================================================================
	// Measurement
	//==========================================================================

	/// Measure this view with the given constraints.
	/// Stores the result in MeasuredWidth/MeasuredHeight.
	public void Measure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		if (mVisibility == .Gone)
		{
			mMeasuredWidth = 0;
			mMeasuredHeight = 0;
			return;
		}

		OnMeasure(widthSpec, heightSpec);
	}

	/// Override to provide custom measurement logic.
	/// Call SetMeasuredDimension to store results.
	protected virtual void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		// Default: use padding as minimum size
		float defaultWidth = mPadding.Horizontal;
		float defaultHeight = mPadding.Vertical;

		SetMeasuredDimension(
			widthSpec.Resolve(defaultWidth, MinWidth, MaxWidth),
			heightSpec.Resolve(defaultHeight, MinHeight, MaxHeight)
		);
	}

	/// Store the measured dimensions.
	protected void SetMeasuredDimension(float width, float height)
	{
		mMeasuredWidth = Math.Max(0, width);
		mMeasuredHeight = Math.Max(0, height);
	}

	//==========================================================================
	// Layout
	//==========================================================================

	/// Position and size this view within its parent.
	public void Layout(float left, float top, float width, float height)
	{
		mLeft = left;
		mTop = top;
		mWidth = Math.Max(0, width);
		mHeight = Math.Max(0, height);
		mLayoutDirty = false;

		OnLayout(mWidth, mHeight);
	}

	/// Override to lay out children.
	protected virtual void OnLayout(float width, float height)
	{
	}

	/// Mark this view's layout as needing recalculation.
	public void InvalidateLayout()
	{
		mLayoutDirty = true;
	}

	/// Mark this view as needing a redraw.
	public void Invalidate()
	{
		// With always-redraw this is a no-op, but serves as a hook
		// for future dirty-tracking optimization.
	}

	public bool IsLayoutDirty => mLayoutDirty;

	//==========================================================================
	// Drawing
	//==========================================================================

	/// Draw this view. Applies transform, opacity, and calls OnDraw.
	public void Draw(DrawContext ctx)
	{
		if (mVisibility != .Visible)
			return;

		if (mAlpha <= 0)
			return;

		ctx.PushState();

		// Apply position translation
		ctx.Translate(mLeft, mTop);

		// Apply render transform (around origin)
		if (HasRenderTransform)
		{
			float originX = mWidth * mRenderTransformOrigin.X;
			float originY = mHeight * mRenderTransformOrigin.Y;
			ctx.Translate(originX, originY);
			ctx.SetTransform(mRenderTransform * ctx.GetTransform());
			ctx.Translate(-originX, -originY);
		}

		// Apply opacity
		if (mAlpha < 1.0f)
			ctx.PushOpacity(mAlpha);

		// Clip if requested
		if (mClipToBounds)
			ctx.PushClipRect(.(0, 0, mWidth, mHeight));

		// Draw background
		if (mBackground != null)
			mBackground.Draw(ctx, .(0, 0, mWidth, mHeight));

		// Draw content
		OnDraw(ctx);

		// Pop clip
		if (mClipToBounds)
			ctx.PopClip();

		// Pop opacity
		if (mAlpha < 1.0f)
			ctx.PopOpacity();

		ctx.PopState();
	}

	/// Override to draw this view's content.
	/// Coordinates are local (0,0 is top-left of this view).
	protected virtual void OnDraw(DrawContext ctx)
	{
	}

	//==========================================================================
	// Hit Testing
	//==========================================================================

	/// Test if a point (in parent coordinates) hits this view.
	/// Returns this view if hit, null otherwise.
	public virtual View HitTest(Vector2 point)
	{
		if (mVisibility != .Visible || !mIsHitTestVisible || mIsPendingDeletion)
			return null;

		// Convert from parent coords to local coords
		var localPoint = PointToLocal(point);

		// Check bounds
		if (localPoint.X < 0 || localPoint.Y < 0 || localPoint.X > mWidth || localPoint.Y > mHeight)
			return null;

		return this;
	}

	//==========================================================================
	// Coordinate Conversion
	//==========================================================================

	/// Convert a point from parent coordinates to this view's local coordinates.
	public Vector2 PointToLocal(Vector2 parentPoint)
	{
		var p = Vector2(parentPoint.X - mLeft, parentPoint.Y - mTop);

		if (HasRenderTransform)
		{
			// Undo render transform
			float originX = mWidth * mRenderTransformOrigin.X;
			float originY = mHeight * mRenderTransformOrigin.Y;
			p.X -= originX;
			p.Y -= originY;
			var inverse = Matrix.Invert(mRenderTransform);
			p = Vector2.Transform(p, inverse);
			p.X += originX;
			p.Y += originY;
		}

		return p;
	}

	/// Convert a point from this view's local coordinates to screen coordinates.
	public Vector2 ToScreen(Vector2 localPoint)
	{
		var p = localPoint;

		// Apply render transform
		if (HasRenderTransform)
		{
			float originX = mWidth * mRenderTransformOrigin.X;
			float originY = mHeight * mRenderTransformOrigin.Y;
			p.X -= originX;
			p.Y -= originY;
			p = Vector2.Transform(p, mRenderTransform);
			p.X += originX;
			p.Y += originY;
		}

		// Add position offset
		p.X += mLeft;
		p.Y += mTop;

		// Walk up the parent chain
		if (mParent != null)
			return mParent.ToScreen(p);

		return p;
	}

	/// Convert a point from screen coordinates to this view's local coordinates.
	public Vector2 ToLocal(Vector2 screenPoint)
	{
		// Walk up to root, collecting parents
		if (mParent != null)
		{
			var parentLocal = mParent.ToLocal(screenPoint);
			return PointToLocal(parentLocal);
		}

		return PointToLocal(screenPoint);
	}

	/// Get the bounds of this view in local coordinates.
	public RectangleF LocalBounds => .(0, 0, mWidth, mHeight);

	/// Get the content area (bounds minus padding) in local coordinates.
	public RectangleF ContentBounds => .(
		mPadding.Left, mPadding.Top,
		Math.Max(0, mWidth - mPadding.Horizontal),
		Math.Max(0, mHeight - mPadding.Vertical)
	);

	//==========================================================================
	// Lifecycle
	//==========================================================================

	/// Called when this view is attached to a UIContext (added to the tree).
	public virtual void OnAttachedToContext(UIContext context)
	{
		mContext = context;
		context.RegisterElement(this);

		// Cache RootView reference
		if (let rv = this as RootView)
			mRootView = rv;
		else
			mRootView = mParent?.[Friend]mRootView;
	}

	/// Called when this view is detached from a UIContext (removed from the tree).
	public virtual void OnDetachedFromContext(UIContext context)
	{
		context.UnregisterElement(this);
		mContext = null;
		mRootView = null;
	}

	//==========================================================================
	// Control State (for theming)
	//==========================================================================

	/// Returns the current visual state of this view for theming purposes.
	/// Priority: Disabled > Pressed > Focused > Hover > Normal.
	public ControlState GetControlState()
	{
		if (!mEnabled) return .Disabled;
		if (mIsPressed) return .Pressed;
		if (mIsFocused) return .Focused;
		if (mIsHovered) return .Hover;
		return .Normal;
	}

	//==========================================================================
	// Theme helpers
	//==========================================================================

	/// Default background color for this view's current state.
	/// Override in controls that need a specific default.
	public virtual Color GetStateBackground()
	{
		let theme = mContext?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;
		return Palette.ResolveState(palette.Surface, GetControlState(), palette.Accent);
	}

	/// Default text/foreground color for this view's current state.
	public virtual Color GetStateForeground()
	{
		let theme = mContext?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;
		let baseColor = palette.Text;
		if (!mEnabled)
			return Palette.WithAlpha(baseColor, (uint8)(baseColor.A / 2));
		return baseColor;
	}

	/// Default border color for this view's current state.
	public virtual Color GetStateBorderColor()
	{
		let theme = mContext?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;
		return palette.Border;
	}

	/// Focus border color, from theme with white fallback.
	public Color GetFocusBorderColor()
	{
		let theme = mContext?.Theme;
		return theme?.GetColor("Focus", "borderColor") ?? .(1.0f, 1.0f, 1.0f, 0.7f);
	}

	/// Draw focus indicator. Uses theme drawable "Focus"/"indicator" if available,
	/// otherwise falls back to a rounded rect border with focus color.
	public void DrawFocusIndicator(DrawContext ctx, RectangleF rect, float fallbackCornerRadius = 4)
	{
		let theme = mContext?.Theme;
		let focusDrawable = theme?.GetDrawable("Focus", "indicator");
		if (focusDrawable != null)
			focusDrawable.Draw(ctx, rect, GetControlState());
		else
			ctx.DrawBorderRoundedRect(rect, fallbackCornerRadius, GetFocusBorderColor(), 2);
	}

	//==========================================================================
	// Baseline (for text alignment in horizontal layouts)
	//==========================================================================

	/// Returns the distance from the top of this view to its text baseline,
	/// or -1 if this view has no meaningful baseline.
	/// Called after measurement/layout to support baseline alignment in LinearLayout.
	public virtual float GetBaseline()
	{
		return -1;
	}

	//==========================================================================
	// Input Event Handlers (overridden by controls)
	//==========================================================================

	public virtual void OnMouseDown(MouseButtonEventArgs e) { }
	public virtual void OnMouseUp(MouseButtonEventArgs e) { }
	public virtual void OnMouseMove(MouseEventArgs e) { }
	public virtual void OnMouseWheel(MouseWheelEventArgs e) { }
	public virtual void OnMouseEnter(MouseEventArgs e) { }
	public virtual void OnMouseLeave(MouseEventArgs e) { }
	public virtual void OnKeyDown(KeyEventArgs e) { }
	public virtual void OnKeyUp(KeyEventArgs e) { }
	public virtual void OnTextInput(TextInputEventArgs e) { }
	public virtual void OnFocusGained(FocusEventArgs e) { }
	public virtual void OnFocusLost(FocusEventArgs e) { }

	//==========================================================================
	// Per-Frame Update
	//==========================================================================

	/// Called once per frame before measurement/layout.
	/// Override for per-frame logic (momentum, animation, etc.).
	public virtual void OnTick(float deltaTime) { }

	/// Called when the UIContext's theme changes.
	/// Override to re-read theme properties. ViewGroup propagates to children.
	public virtual void OnThemeChanged() { }

	//==========================================================================
	// Parent management (internal, set by ViewGroup)
	//==========================================================================

	internal void SetParent(View parent)
	{
		mParent = parent;
	}
}
