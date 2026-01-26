using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// Base class for popup windows that float above the main UI.
/// Popups are positioned relative to an anchor element or at absolute coordinates.
public class Popup : Control, IVisualChildProvider
{
	private UIElement mAnchor;
	private PopupPlacement mPlacement = .Bottom;
	private PopupBehavior mBehavior = .Default;
	private float mHorizontalOffset;
	private float mVerticalOffset;
	private bool mIsOpen;
	private UIElement mContent ~ delete _;

	// Events
	private EventAccessor<delegate void(Popup)> mOpenedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(Popup)> mClosedEvent = new .() ~ delete _;

	/// The element this popup is anchored to.
	public UIElement Anchor
	{
		get => mAnchor;
		set => mAnchor = value;
	}

	/// How the popup is positioned relative to its anchor.
	public PopupPlacement Placement
	{
		get => mPlacement;
		set => mPlacement = value;
	}

	/// Behavior flags controlling how the popup opens/closes.
	public PopupBehavior Behavior
	{
		get => mBehavior;
		set => mBehavior = value;
	}

	/// Horizontal offset from the calculated position.
	public float HorizontalOffset
	{
		get => mHorizontalOffset;
		set => mHorizontalOffset = value;
	}

	/// Vertical offset from the calculated position.
	public float VerticalOffset
	{
		get => mVerticalOffset;
		set => mVerticalOffset = value;
	}

	/// Whether the popup is currently open.
	public bool IsOpen => mIsOpen;

	/// Whether this popup is modal (blocks input to elements below).
	public bool IsModal => mBehavior.HasFlag(.Modal);

	/// The content displayed in the popup.
	public UIElement Content
	{
		get => mContent;
		set
		{
			if (mContent != value)
			{
				if (mContent != null)
					mContent.[Friend]mParent = null;

				mContent = value;

				if (mContent != null)
					mContent.[Friend]mParent = this;

				InvalidateMeasure();
			}
		}
	}

	/// Fired when the popup opens.
	public EventAccessor<delegate void(Popup)> Opened => mOpenedEvent;

	/// Fired when the popup closes.
	public EventAccessor<delegate void(Popup)> Closed => mClosedEvent;

	public this()
	{
		// Popups are not part of normal tab navigation
		Focusable = false;
		Visibility = .Collapsed;
	}

	public ~this()
	{
		// Unregister from context if still registered
		Context?.ClosePopup(this);
	}

	/// Opens the popup.
	public void Open()
	{
		if (mIsOpen)
			return;

		mIsOpen = true;
		Visibility = .Visible;

		// Register with context
		Context?.OpenPopup(this);

		mOpenedEvent.[Friend]Invoke(this);
		InvalidateMeasure();
	}

	/// Opens the popup at the specified screen position.
	public void OpenAt(float x, float y)
	{
		mPlacement = .Absolute;
		mHorizontalOffset = x;
		mVerticalOffset = y;
		Open();
	}

	/// Opens the popup anchored to an element.
	public void OpenAt(UIElement anchor, PopupPlacement placement = .Bottom)
	{
		mAnchor = anchor;
		mPlacement = placement;
		Open();
	}

	/// Closes the popup.
	public void Close()
	{
		if (!mIsOpen)
			return;

		mIsOpen = false;
		Visibility = .Collapsed;

		// Unregister from context
		Context?.ClosePopup(this);

		mClosedEvent.[Friend]Invoke(this);
	}

	/// Calculates the popup position based on anchor and placement.
	public Vector2 CalculatePosition(float viewportWidth, float viewportHeight)
	{
		var x = mHorizontalOffset;
		var y = mVerticalOffset;

		let popupWidth = DesiredSize.Width;
		let popupHeight = DesiredSize.Height;

		switch (mPlacement)
		{
		case .Absolute:
			// Use offsets directly
			break;

		case .Mouse:
			// Position will be set by InputManager when opening
			break;

		case .Center:
			x = (viewportWidth - popupWidth) / 2;
			y = (viewportHeight - popupHeight) / 2;

		case .Bottom, .BottomCenter, .Top, .TopCenter, .Left, .Right:
			if (mAnchor != null)
			{
				let anchorBounds = mAnchor.Bounds;

				switch (mPlacement)
				{
				case .Bottom:
					x = anchorBounds.X + mHorizontalOffset;
					y = anchorBounds.Bottom + mVerticalOffset;

				case .BottomCenter:
					x = anchorBounds.X + (anchorBounds.Width - popupWidth) / 2 + mHorizontalOffset;
					y = anchorBounds.Bottom + mVerticalOffset;

				case .Top:
					x = anchorBounds.X + mHorizontalOffset;
					y = anchorBounds.Y - popupHeight + mVerticalOffset;

				case .TopCenter:
					x = anchorBounds.X + (anchorBounds.Width - popupWidth) / 2 + mHorizontalOffset;
					y = anchorBounds.Y - popupHeight + mVerticalOffset;

				case .Right:
					x = anchorBounds.Right + mHorizontalOffset;
					y = anchorBounds.Y + mVerticalOffset;

				case .Left:
					x = anchorBounds.X - popupWidth + mHorizontalOffset;
					y = anchorBounds.Y + mVerticalOffset;

				default:
				}
			}
		}

		// Clamp to viewport bounds
		x = Math.Clamp(x, 0, Math.Max(0, viewportWidth - popupWidth));
		y = Math.Clamp(y, 0, Math.Max(0, viewportHeight - popupHeight));

		return .(x, y);
	}

	/// Called by UIContext to check if a click outside should close this popup.
	public bool ShouldCloseOnClickOutside(float x, float y)
	{
		if (!mBehavior.HasFlag(.CloseOnClickOutside))
			return false;

		// Check if click is inside the popup
		if (Bounds.Contains(x, y))
			return false;

		// Check if click is inside the anchor (anchored popups stay open when clicking anchor)
		if (mAnchor != null && mAnchor.Bounds.Contains(x, y))
			return false;

		return true;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (mContent != null)
		{
			mContent.Measure(constraints);
			return mContent.DesiredSize;
		}
		return .(0, 0);
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		if (mContent != null)
		{
			mContent.Arrange(contentBounds);
		}
	}

	protected override void OnRender(DrawContext drawContext)
	{
		// Draw popup background with shadow effect
		let theme = GetTheme();
		let bg = Background ?? theme?.GetColor("Surface") ?? Color(50, 50, 55);
		let border = BorderBrush ?? theme?.GetColor("Border") ?? Color(80, 80, 90);

		// Shadow (offset dark rectangle)
		let shadowOffset = 4.0f;
		let shadowBounds = RectangleF(Bounds.X + shadowOffset, Bounds.Y + shadowOffset, Bounds.Width, Bounds.Height);
		drawContext.FillRect(shadowBounds, Color(0, 0, 0, 80));

		// Background
		drawContext.FillRect(Bounds, bg);

		// Border
		drawContext.DrawRect(Bounds, border, 1.0f);

		// Render content
		RenderContent(drawContext);
	}

	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		if (args.Key == .Escape && mBehavior.HasFlag(.CloseOnEscape))
		{
			Close();
			args.Handled = true;
		}
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		if (mContent != null)
			mContent.Render(drawContext);
	}

	/// Override HitTest to check content.
	public override UIElement HitTest(float x, float y)
	{
		if (Visibility != .Visible)
			return null;

		if (!Bounds.Contains(x, y))
			return null;

		// Check content first
		if (mContent != null)
		{
			let result = mContent.HitTest(x, y);
			if (result != null)
				return result;
		}

		return this;
	}

	/// Override FindElementById to search content.
	public override UIElement FindElementById(UIElementId id)
	{
		if (Id == id)
			return this;

		if (mContent != null)
		{
			let result = mContent.FindElementById(id);
			if (result != null)
				return result;
		}

		return null;
	}

	// === IVisualChildProvider ===

	/// Visits all visual children of this element.
	public void VisitVisualChildren(delegate void(UIElement) visitor)
	{
		if (mContent != null)
			visitor(mContent);
	}
}
