using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// A panel that can be docked to edges or floated.
public class DockablePanel : Control, IVisualChildProvider
{
	private String mTitle ~ delete _;
	private UIElement mContent ~ delete _;
	private DockZone mDockZone = .None;
	private bool mCanClose = true;
	private bool mCanFloat = true;
	private bool mIsDragging;
	private float mDragStartX;
	private float mDragStartY;
	private float mTitleBarHeight = 24;

	// Events
	private EventAccessor<delegate void(DockablePanel)> mClosingEvent = new .() ~ delete _;
	private EventAccessor<delegate void(DockablePanel)> mClosedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(DockablePanel, DockZone)> mDockedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(DockablePanel)> mFloatedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(DockablePanel, float, float)> mDragStartedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(DockablePanel, float, float)> mDraggingEvent = new .() ~ delete _;
	private EventAccessor<delegate void(DockablePanel)> mDragEndedEvent = new .() ~ delete _;

	/// The panel title.
	public StringView Title
	{
		get => mTitle ?? "";
		set
		{
			if (mTitle == null)
				mTitle = new String();
			mTitle.Set(value);
			InvalidateVisual();
		}
	}

	/// The panel content.
	public UIElement PanelContent
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

	/// The current dock zone.
	public DockZone DockZone
	{
		get => mDockZone;
		set
		{
			if (mDockZone != value)
			{
				mDockZone = value;
				mDockedEvent.[Friend]Invoke(this, value);
			}
		}
	}

	/// Whether the panel is currently docked (not floating).
	public bool IsDocked => mDockZone != .None && mDockZone != .Float;

	/// Whether the panel is floating.
	public bool IsFloating => mDockZone == .Float;

	/// Whether the close button is shown.
	public bool CanClose
	{
		get => mCanClose;
		set
		{
			mCanClose = value;
			InvalidateVisual();
		}
	}

	/// Whether the panel can be floated.
	public bool CanFloat
	{
		get => mCanFloat;
		set => mCanFloat = value;
	}

	/// The height of the title bar.
	public float TitleBarHeight
	{
		get => mTitleBarHeight;
		set
		{
			if (mTitleBarHeight != value)
			{
				mTitleBarHeight = Math.Max(16, value);
				InvalidateMeasure();
			}
		}
	}

	/// Fired before closing (can be cancelled by not calling Close).
	public EventAccessor<delegate void(DockablePanel)> Closing => mClosingEvent;

	/// Fired after the panel is closed.
	public EventAccessor<delegate void(DockablePanel)> Closed => mClosedEvent;

	/// Fired when the panel is docked.
	public EventAccessor<delegate void(DockablePanel, DockZone)> Docked => mDockedEvent;

	/// Fired when the panel is floated.
	public EventAccessor<delegate void(DockablePanel)> Floated => mFloatedEvent;

	/// Fired when dragging starts.
	public EventAccessor<delegate void(DockablePanel, float, float)> DragStarted => mDragStartedEvent;

	/// Fired during dragging.
	public EventAccessor<delegate void(DockablePanel, float, float)> Dragging => mDraggingEvent;

	/// Fired when dragging ends.
	public EventAccessor<delegate void(DockablePanel)> DragEnded => mDragEndedEvent;

	public this()
	{
		BorderThickness = Thickness(1);
		ClipToBounds = true;
	}

	public this(StringView title) : this()
	{
		Title = title;
	}

	/// Closes the panel.
	public void ClosePanel()
	{
		mClosingEvent.[Friend]Invoke(this);

		// Remove from parent (only CompositeControl has RemoveChild)
		if (Parent != null)
		{
			if (let composite = Parent as CompositeControl)
				composite.RemoveChild(this);
			else
				this.[Friend]mParent = null; // Just clear parent
		}

		mDockZone = .None;
		mClosedEvent.[Friend]Invoke(this);
	}

	/// Makes the panel floating.
	public void Float()
	{
		if (!mCanFloat)
			return;

		mDockZone = .Float;
		mFloatedEvent.[Friend]Invoke(this);
	}

	/// Gets the title bar bounds relative to this panel.
	public RectangleF GetTitleBarBounds()
	{
		return RectangleF(0, 0, Bounds.Width, mTitleBarHeight);
	}

	/// Gets the close button bounds relative to this panel.
	public RectangleF GetCloseButtonBounds()
	{
		if (!mCanClose)
			return RectangleF.Empty;

		let size = mTitleBarHeight - 6;
		return RectangleF(Bounds.Width - size - 4, 3, size, size);
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		var contentWidth = 100f;
		var contentHeight = mTitleBarHeight;

		if (mContent != null)
		{
			let contentConstraints = SizeConstraints.FromMaximum(
				constraints.MaxWidth - Padding.TotalHorizontal,
				constraints.MaxHeight - mTitleBarHeight - Padding.TotalVertical);
			mContent.Measure(contentConstraints);
			contentWidth = Math.Max(contentWidth, mContent.DesiredSize.Width);
			contentHeight += mContent.DesiredSize.Height;
		}

		return .(contentWidth + Padding.TotalHorizontal, contentHeight + Padding.TotalVertical);
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		if (mContent != null)
		{
			let contentArea = RectangleF(
				contentBounds.X,
				contentBounds.Y + mTitleBarHeight,
				contentBounds.Width,
				contentBounds.Height - mTitleBarHeight);
			mContent.Arrange(contentArea);
		}
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Background
		let bg = Background ?? theme?.GetColor("Surface") ?? Color(250, 250, 250);
		drawContext.FillRect(bounds, bg);

		// Title bar
		let titleBarBounds = RectangleF(bounds.X, bounds.Y, bounds.Width, mTitleBarHeight);
		let titleBarBg = theme?.GetColor("DockPanelHeader") ?? theme?.GetColor("BackgroundDark") ?? Color(230, 230, 230);
		drawContext.FillRect(titleBarBounds, titleBarBg);

		// Title text
		if (mTitle != null && mTitle.Length > 0)
		{
			let titleColor = Foreground ?? theme?.GetColor("Foreground") ?? Color.Black;
			let fontService = GetFontService();
			let cachedFont = fontService?.GetFont(FontFamily, FontSize);

			if (fontService != null && cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);

				if (atlas != null && atlasTexture != null)
				{
					let textRight = mCanClose ? bounds.Width - mTitleBarHeight : bounds.Width - 4;
					let textBounds = RectangleF(bounds.X + 6, bounds.Y, textRight - 6, mTitleBarHeight);
					drawContext.DrawText(mTitle, font, atlas, atlasTexture, textBounds, .Left, .Middle, titleColor);
				}
			}
		}

		// Close button
		if (mCanClose)
		{
			let closeBounds = GetCloseButtonBounds();
			let closeAbsBounds = RectangleF(bounds.X + closeBounds.X, bounds.Y + closeBounds.Y, closeBounds.Width, closeBounds.Height);

			// Hover highlight
			if (IsMouseOverCloseButton())
			{
				let hoverBg = theme?.GetColor("Hover") ?? Color(200, 200, 200);
				drawContext.FillRect(closeAbsBounds, hoverBg);
			}

			// X icon
			let xColor = theme?.GetColor("Foreground") ?? Color.Black;
			let cx = closeAbsBounds.X + closeAbsBounds.Width / 2;
			let cy = closeAbsBounds.Y + closeAbsBounds.Height / 2;
			let xSize = 4f;

			for (int i < (int)xSize)
			{
				drawContext.FillRect(.(cx - xSize + i, cy - xSize + i, 2, 2), xColor);
				drawContext.FillRect(.(cx + xSize - i - 2, cy - xSize + i, 2, 2), xColor);
			}
		}

		// Border
		let border = BorderBrush ?? theme?.GetColor("Border") ?? Color(180, 180, 180);
		drawContext.DrawRect(bounds, border, 1);

		// Render content
		RenderContent(drawContext);
	}

	private bool IsMouseOverCloseButton()
	{
		if (!mCanClose || !IsMouseOver)
			return false;

		// Simplified - would need proper hit testing with actual local mouse coords
		return IsMouseOver;
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		base.OnMouseDownRouted(args);

		if (args.Button == .Left)
		{
			// Check if clicking close button
			if (mCanClose)
			{
				let closeBounds = GetCloseButtonBounds();
				if (args.LocalX >= closeBounds.X && args.LocalX <= closeBounds.Right &&
					args.LocalY >= closeBounds.Y && args.LocalY <= closeBounds.Bottom)
				{
					ClosePanel();
					args.Handled = true;
					return;
				}
			}

			// Check if clicking title bar (for dragging)
			if (args.LocalY < mTitleBarHeight && mCanFloat)
			{
				mIsDragging = true;
				mDragStartX = args.LocalX;
				mDragStartY = args.LocalY;
				Context?.CaptureMouse(this);
				mDragStartedEvent.[Friend]Invoke(this, args.LocalX, args.LocalY);
				args.Handled = true;
			}
		}
	}

	protected override void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		base.OnMouseUpRouted(args);

		if (args.Button == .Left && mIsDragging)
		{
			mIsDragging = false;
			Context?.ReleaseMouseCapture();
			mDragEndedEvent.[Friend]Invoke(this);
			args.Handled = true;
		}
	}

	protected override void OnMouseMoveRouted(MouseEventArgs args)
	{
		base.OnMouseMoveRouted(args);

		if (mIsDragging)
		{
			let deltaX = args.LocalX - mDragStartX;
			let deltaY = args.LocalY - mDragStartY;
			mDraggingEvent.[Friend]Invoke(this, deltaX, deltaY);
			args.Handled = true;
		}
	}

	/// Gets the font service from the context.
	private IFontService GetFontService()
	{
		let context = Context;
		if (context != null)
		{
			if (context.GetService<IFontService>() case .Ok(let service))
				return service;
		}
		return null;
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
