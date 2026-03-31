namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Tab container for docked panels. Shows tabs at the bottom and content above.
public class DockTabGroup : ViewGroup, IDragSource
{
	private List<DockablePanel> mPanels = new .() ~ delete _; // Non-owning refs
	private int mSelectedIndex = -1;
	private float mTabHeight = 24;
	private int mHoveredTabIndex = -1;
	private List<RectangleF> mTabRects = new .() ~ delete _;

	// Drag state for tab dragging
	private int mDragTabIndex = -1;
	private DockablePanel mDraggedPanel;
	private int mDragOriginalIndex = -1;

	public int SelectedIndex
	{
		get => mSelectedIndex;
		set
		{
			if (value >= -1 && value < mPanels.Count && mSelectedIndex != value)
			{
				// Hide previous content
				if (mSelectedIndex >= 0 && mSelectedIndex < mPanels.Count)
					mPanels[mSelectedIndex].Visibility = .Gone;

				mSelectedIndex = value;

				// Show new content
				if (mSelectedIndex >= 0 && mSelectedIndex < mPanels.Count)
					mPanels[mSelectedIndex].Visibility = .Visible;

				InvalidateLayout();
			}
		}
	}

	public int PanelCount => mPanels.Count;
	public float TabHeight { get => mTabHeight; set { mTabHeight = Math.Max(16, value); InvalidateLayout(); } }

	public DockablePanel SelectedPanel
	{
		get => (mSelectedIndex >= 0 && mSelectedIndex < mPanels.Count) ? mPanels[mSelectedIndex] : null;
	}

	/// Add a panel as a tab. DockTabGroup does NOT take ownership.
	public void AddPanel(DockablePanel panel)
	{
		mPanels.Add(panel);
		panel.Visibility = .Gone;
		AddView(panel);

		if (mSelectedIndex < 0)
			SelectedIndex = 0;
		else
			InvalidateLayout();
	}

	/// Insert a panel at a specific index.
	public void InsertPanel(int index, DockablePanel panel)
	{
		int idx = Math.Clamp(index, 0, mPanels.Count);
		mPanels.Insert(idx, panel);
		panel.Visibility = .Gone;
		AddView(panel);

		if (mSelectedIndex < 0)
			SelectedIndex = 0;
		else
		{
			if (idx <= mSelectedIndex)
				mSelectedIndex++;
			InvalidateLayout();
		}
	}

	/// Remove a panel from this group. Returns the panel (caller takes ownership).
	public DockablePanel RemovePanel(DockablePanel panel)
	{
		int idx = mPanels.IndexOf(panel);
		if (idx < 0) return null;

		mPanels.RemoveAt(idx);
		DetachView(panel);

		if (mSelectedIndex >= mPanels.Count)
			SelectedIndex = mPanels.Count - 1;
		else if (idx <= mSelectedIndex && mSelectedIndex > 0)
			SelectedIndex = mSelectedIndex - 1;
		else
			InvalidateLayout();

		return panel;
	}

	/// Remove a panel at the given index.
	public DockablePanel RemovePanelAt(int index)
	{
		if (index < 0 || index >= mPanels.Count) return null;
		return RemovePanel(mPanels[index]);
	}

	/// Get the panel at the given index.
	public DockablePanel GetPanel(int index)
	{
		if (index >= 0 && index < mPanels.Count) return mPanels[index];
		return null;
	}

	/// Purge any panels that are pending deletion (defense-in-depth).
	/// This catches cases where a panel was deleted externally without going
	/// through RemovePanel, leaving a dangling pointer in mPanels.
	private void PurgeDeletedPanels()
	{
		bool changed = false;
		for (int i = mPanels.Count - 1; i >= 0; i--)
		{
			if (mPanels[i].IsPendingDeletion || mPanels[i].Parent != this)
			{
				mPanels.RemoveAt(i);
				changed = true;
			}
		}
		if (changed)
		{
			if (mSelectedIndex >= mPanels.Count)
				mSelectedIndex = mPanels.Count - 1;
		}
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		PurgeDeletedPanels();

		float w = widthSpec.Resolve(150, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(100, MinHeight, MaxHeight);

		// Measure the selected panel content
		if (mSelectedIndex >= 0 && mSelectedIndex < mPanels.Count)
		{
			let panel = mPanels[mSelectedIndex];
			if (panel.Visibility != .Gone)
				panel.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(Math.Max(0, h - mTabHeight)));
		}

		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		PurgeDeletedPanels();

		float contentH = Math.Max(0, height - mTabHeight);

		for (int i = 0; i < mPanels.Count; i++)
		{
			let panel = mPanels[i];
			if (i == mSelectedIndex)
			{
				panel.Visibility = .Visible;
				panel.Layout(0, 0, width, contentH);
			}
			else
			{
				panel.Visibility = .Gone;
			}
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Content area background
		float contentH = Height - mTabHeight;
		let contentBg = palette.Surface;
		ctx.FillRect(.(0, 0, Width, contentH), contentBg);

		// Draw selected panel
		if (mSelectedIndex >= 0 && mSelectedIndex < mPanels.Count)
		{
			let panel = mPanels[mSelectedIndex];
			if (panel.Visibility != .Gone)
				panel.Draw(ctx);
		}

		// Tab bar background
		let tabBg = theme?.GetColor("DockTabGroup", "tabBackground") ?? Palette.Darken(palette.Surface, 0.15f);
		ctx.FillRect(.(0, contentH, Width, mTabHeight), tabBg);

		// Draw tabs
		mTabRects.Clear();
		if (Context?.FontService == null) return;

		let font = Context.FontService.GetFont(11);
		if (font == null) return;
		let atlasTexture = Context.FontService.GetAtlasTexture(font);
		if (atlasTexture == null) { Context.FontService.ReleaseFont(font); return; }

		float tabX = 2;
		let activeTabBg = theme?.GetColor("DockTabGroup", "activeTabBackground") ?? palette.Surface;
		let tabTextColor = theme?.GetColor("DockTabGroup", "tabText") ?? palette.Text;

		for (int i = 0; i < mPanels.Count; i++)
		{
			let panel = mPanels[i];
			float textW = font.Font.MeasureString(panel.Title);
			float tabW = textW + 16;
			let tabRect = RectangleF(tabX, contentH, tabW, mTabHeight);
			mTabRects.Add(tabRect);

			// Tab background
			if (i == mSelectedIndex)
				ctx.FillRect(tabRect, activeTabBg);
			else if (i == mHoveredTabIndex)
				ctx.FillRect(tabRect, Palette.Lighten(tabBg, 0.1f));

			// Tab text
			ctx.DrawText(panel.Title, font.Font, font.Atlas, atlasTexture,
				.(tabX + 8, contentH, textW, mTabHeight), .Left, .Middle, tabTextColor);

			tabX += tabW + 2;
		}

		Context.FontService.ReleaseFont(font);
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left) return;

		// Hit test tabs for selection and drag initiation
		mDragTabIndex = -1;
		for (int i = 0; i < mTabRects.Count; i++)
		{
			let r = mTabRects[i];
			if (e.LocalX >= r.X && e.LocalX < r.X + r.Width &&
				e.LocalY >= r.Y && e.LocalY < r.Y + r.Height)
			{
				SelectedIndex = i;
				mDragTabIndex = i; // Mark for potential drag
				e.Handled = true;
				return;
			}
		}
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		int hovered = -1;
		for (int i = 0; i < mTabRects.Count; i++)
		{
			let r = mTabRects[i];
			if (e.LocalX >= r.X && e.LocalX < r.X + r.Width &&
				e.LocalY >= r.Y && e.LocalY < r.Y + r.Height)
			{
				hovered = i;
				break;
			}
		}

		if (hovered != mHoveredTabIndex)
		{
			mHoveredTabIndex = hovered;
			Invalidate();
		}
	}

	public override void OnMouseLeave(MouseEventArgs e)
	{
		if (mHoveredTabIndex != -1)
		{
			mHoveredTabIndex = -1;
			Invalidate();
		}
	}

	// ===== IDragSource =====

	public DragData CreateDragData()
	{
		// Only initiate drag from a tab
		if (mDragTabIndex < 0 || mDragTabIndex >= mPanels.Count)
			return null;

		return new DockPanelDragData(mPanels[mDragTabIndex]);
	}

	public View CreateDragVisual(DragData data)
	{
		if (let panelData = data as DockPanelDragData)
		{
			let label = new Label(panelData.Panel.Title);
			label.FontSize = 11;
			label.Padding = Thickness(4, 2, 4, 2);
			return label;
		}
		return null;
	}

	public void OnDragStarted(DragData data)
	{
		if (let panelData = data as DockPanelDragData)
		{
			// Undock the panel from this group so it can be dropped elsewhere
			mDraggedPanel = panelData.Panel;
			mDragOriginalIndex = mDragTabIndex;

			// Remove from this tab group (the panel is now "in flight")
			RemovePanel(mDraggedPanel);
		}
	}

	public void OnDragCompleted(DragData data, DragDropEffects effect, bool cancelled)
	{
		if (cancelled && mDraggedPanel != null)
		{
			let dockHost = mDraggedPanel.[Friend]mDockHost;
			if (dockHost != null)
			{
				let screenX = dockHost.Context?.DragDrop.LastGlobalX ?? 100;
				let screenY = dockHost.Context?.DragDrop.LastGlobalY ?? 100;
				dockHost.FloatPanel(mDraggedPanel, screenX, screenY);
			}
			else
			{
				// No DockHost found — re-insert at original position as fallback
				InsertPanel(mDragOriginalIndex, mDraggedPanel);
			}
		}

		mDraggedPanel = null;
		mDragOriginalIndex = -1;
		mDragTabIndex = -1;
	}
}
