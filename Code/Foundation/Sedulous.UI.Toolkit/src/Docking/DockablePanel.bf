namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// A content panel with a title bar, suitable for docking.
public class DockablePanel : ViewGroup, IDragSource
{
	private String mTitle = new .("Panel") ~ delete _;
	private View mContentView;
	private bool mClosable = true;
	private float mHeaderHeight = 24;
	private float mFontSize = 12;
	private bool mDragFromHeader;
	private float mOriginalAlpha = 1.0f;
	internal IDockHost mDockHost;

	/// Last dock position for re-dock after floating.
	public DockPosition mLastDockPosition = .Center;
	/// Last relative-to view ID for re-dock after floating.
	public ViewId mLastRelativeToId = .Invalid;

	private EventAccessor<delegate void(DockablePanel)> mOnCloseRequested = new .() ~ delete _;

	/// Fired when the close button is clicked.
	public EventAccessor<delegate void(DockablePanel)> OnCloseRequested => mOnCloseRequested;

	public StringView Title
	{
		get => mTitle;
		set { mTitle.Set(value); Invalidate(); }
	}

	public bool Closable { get => mClosable; set { mClosable = value; Invalidate(); } }
	public float HeaderHeight { get => mHeaderHeight; set { mHeaderHeight = Math.Max(16, value); InvalidateLayout(); } }
	public View ContentView => mContentView;

	public this() { }

	public this(StringView title)
	{
		mTitle.Set(title);
	}

	public this(StringView title, View content)
	{
		mTitle.Set(title);
		SetContent(content);
	}

	/// Set the content view. Replaces any existing content.
	public void SetContent(View content)
	{
		if (mContentView != null)
			RemoveView(mContentView);

		mContentView = content;
		if (content != null)
			AddView(content);
	}

	/// Save current dock position for later re-dock.
	public void SaveDockPosition(DockPosition position, View relativeTo)
	{
		mLastDockPosition = position;
		mLastRelativeToId = (relativeTo != null) ? relativeTo.Id : .Invalid;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(150, MinWidth, MaxWidth);
		float h = mHeaderHeight;

		if (mContentView != null && mContentView.Visibility != .Gone)
		{
			MeasureSpec contentH;
			if (heightSpec.SpecMode == .Exactly)
				contentH = MeasureSpec.MakeExactly(Math.Max(0, heightSpec.Size - mHeaderHeight));
			else if (heightSpec.SpecMode == .AtMost)
				contentH = MeasureSpec.MakeAtMost(Math.Max(0, heightSpec.Size - mHeaderHeight));
			else
				contentH = MeasureSpec.MakeUnspecified();

			mContentView.Measure(MeasureSpec.MakeExactly(w), contentH);
			h += mContentView.MeasuredHeight;
		}

		SetMeasuredDimension(
			widthSpec.Resolve(w, MinWidth, MaxWidth),
			heightSpec.Resolve(h, MinHeight, MaxHeight)
		);
	}

	protected override void OnLayout(float width, float height)
	{
		if (mContentView != null && mContentView.Visibility != .Gone)
		{
			float contentH = Math.Max(0, height - mHeaderHeight);
			mContentView.Layout(0, mHeaderHeight, width, contentH);
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Header background
		let headerBg = theme?.GetColor("DockablePanel", "headerBackground") ?? Palette.Darken(palette.Surface, 0.2f);
		ctx.FillRect(.(0, 0, Width, mHeaderHeight), headerBg);

		// Header text
		if (Context?.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				let atlasTexture = Context.FontService.GetAtlasTexture(font);
				if (atlasTexture != null)
				{
					let textColor = theme?.GetColor("DockablePanel", "headerText") ?? palette.Text;
					float textX = 6;
					float textW = Width - 12;
					if (mClosable) textW -= mHeaderHeight; // Reserve space for close button
					ctx.DrawText(mTitle, font.Font, font.Atlas, atlasTexture,
						.(textX, 0, textW, mHeaderHeight), .Left, .Middle, textColor);
				}
				Context.FontService.ReleaseFont(font);
			}
		}

		// Close button (X shape via two diagonal quads)
		if (mClosable)
		{
			float s = 4; // half-size of the X
			float t = 1; // half-thickness
			float cx = Width - mHeaderHeight * 0.5f;
			float cy = mHeaderHeight * 0.5f;
			let closeColor = Palette.WithAlpha(palette.Text, 180);

			// Top-left to bottom-right diagonal
			Vector2[4] d1 = .(
				.(cx - s, cy - s - t), .(cx - s, cy - s + t),
				.(cx + s, cy + s + t), .(cx + s, cy + s - t));
			ctx.FillPolygon(d1, closeColor);

			// Bottom-left to top-right diagonal
			Vector2[4] d2 = .(
				.(cx - s, cy + s + t), .(cx - s, cy + s - t),
				.(cx + s, cy - s - t), .(cx + s, cy - s + t));
			ctx.FillPolygon(d2, closeColor);
		}

		// Content area
		if (mContentView != null && mContentView.Visibility != .Gone)
		{
			let contentBg = theme?.GetColor("DockablePanel", "contentBackground") ?? palette.Surface;
			ctx.FillRect(.(0, mHeaderHeight, Width, Height - mHeaderHeight), contentBg);
			mContentView.Draw(ctx);
		}
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left) return;

		// Close button hit test
		if (mClosable && e.LocalY < mHeaderHeight)
		{
			float btnX = Width - mHeaderHeight;
			if (e.LocalX >= btnX)
			{
				mOnCloseRequested.[Friend]Invoke(this);
				e.Handled = true;
				return;
			}
		}

		// Track header click for drag source
		mDragFromHeader = (e.LocalY < mHeaderHeight);
		System.Console.WriteLine($"[DockablePanel.OnMouseDown] '{mTitle}' localY={e.LocalY} headerH={mHeaderHeight} dragFromHeader={mDragFromHeader} parent={Parent?.GetType()} clickCount={e.ClickCount}");
	}

	// ===== IDragSource =====

	public DragData CreateDragData()
	{
		System.Console.WriteLine($"[DockablePanel.CreateDragData] '{mTitle}' mDragFromHeader={mDragFromHeader}");
		// Only initiate drag from header area
		if (!mDragFromHeader)
			return null;

		return new DockPanelDragData(this);
	}

	public View CreateDragVisual(DragData data)
	{
		// Semi-transparent label with panel title
		let label = new Label(mTitle);
		label.FontSize = 11;
		label.Padding = Thickness(4, 2, 4, 2);
		return label;
	}

	public void OnDragStarted(DragData data)
	{
		mOriginalAlpha = Alpha;

		let parentView = Parent;
		let isFloating = parentView != null && parentView is IDockableWindow;
		System.Console.WriteLine($"[DockablePanel.OnDragStarted] '{mTitle}' parent={parentView?.GetType()} isFloating={isFloating} context={Context != null}");

		if (isFloating)
		{
			if (let fw = parentView as FloatingWindow)
			{
				if (fw.[Friend]mIsOSWindow)
				{
					// OS floating: just dim the panel. Application handles
					// cross-window coordinate routing to find DockManager.
					Alpha = 0.4f;
					System.Console.WriteLine("[DockablePanel.OnDragStarted] OS floating — dimmed panel");
				}
				else
				{
					// Virtual floating: dim + disable hit-test so DockManager underneath is found
					parentView.Alpha = 0.3f;
					parentView.IsHitTestVisible = false;
					System.Console.WriteLine("[DockablePanel.OnDragStarted] Virtual floating — dimmed window, disabled hit-test");
				}
			}
		}
		else
		{
			// Docked → dim while dragging
			Alpha = 0.4f;
		}
	}

	public void OnDragCompleted(DragData data, DragDropEffects effect, bool cancelled)
	{
		System.Console.WriteLine($"[DockablePanel.OnDragCompleted] '{mTitle}' effect={effect} cancelled={cancelled} dockHost={mDockHost != null}");
		Alpha = mOriginalAlpha;
		mDragFromHeader = false;

		// Restore virtual floating window state (OS windows don't need this)
		if (Parent != null && Parent is IDockableWindow)
		{
			if (let fw = Parent as FloatingWindow)
			{
				if (!fw.[Friend]mIsOSWindow)
				{
					Parent.Alpha = 1.0f;
					Parent.IsHitTestVisible = true;
				}
			}
		}

		if (cancelled && mDockHost != null)
		{
			// OS floating window: the Application already moved the window to
			// follow the cursor during the drag — nothing to do.
			if (Parent != null)
			{
				if (let fw = Parent as FloatingWindow)
				{
					if (fw.[Friend]mIsOSWindow)
					{
						System.Console.WriteLine("[DockablePanel.OnDragCompleted] OS floating — window already at cursor position");
						return;
					}
				}
			}

			// Virtual or docked: float at cursor position (creates new FloatingWindow).
			let screenX = mDockHost.Context?.DragDrop.LastGlobalX ?? 100;
			let screenY = mDockHost.Context?.DragDrop.LastGlobalY ?? 100;
			System.Console.WriteLine($"[DockablePanel.OnDragCompleted] Re-floating at ({screenX}, {screenY})");
			mDockHost.FloatPanel(this, screenX, screenY);
		}
	}
}
