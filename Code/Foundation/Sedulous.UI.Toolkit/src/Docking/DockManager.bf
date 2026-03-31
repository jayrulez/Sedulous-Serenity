namespace Sedulous.UI.Toolkit;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Multi-window docking system. Manages a tree of DockSplits, DockTabGroups,
/// and DockablePanels with support for dragging, floating, and zone-based docking.
public class DockManager : ViewGroup, IDropTarget, IPopupOwner, IDockHost
{
	private View mRootNode;
	private List<DockablePanel> mPanels = new .() ~ delete _; // Non-owning tracking list
	private List<FloatingWindow> mFloatingWindows = new .() ~ delete _; // Non-owning tracking list
	private DockZoneIndicator mZoneIndicator ~ delete _;

	/// Optional host for OS-level floating windows.
	/// When set and SupportsOSWindows is true, floating panels use real OS windows.
	/// When null or unsupported, falls back to PopupLayer virtual floating.
	public IFloatingWindowHost FloatingWindowHost;

	public View RootNode => mRootNode;

	public this()
	{
		mZoneIndicator = new DockZoneIndicator();
		mZoneIndicator.Visibility = .Gone;
	}

	public ~this()
	{
		// Close all floating windows on destruction
		CloseAllFloatingWindows();
	}

	/// Create and add a new dockable panel with content.
	public DockablePanel AddPanel(StringView title, View content)
	{
		let panel = new DockablePanel(title, content);
		panel.OnCloseRequested.Subscribe(new (p) => { ClosePanel(p); });
		panel.[Friend]mDockHost = this;
		mPanels.Add(panel);
		return panel;
	}

	/// Dock a panel at the specified position relative to the root.
	public void DockPanel(DockablePanel panel, DockPosition position)
	{
		DockPanelRelativeTo(panel, position, mRootNode);
	}

	/// Dock a panel at the specified position relative to another node.
	public void DockPanelRelativeTo(DockablePanel panel, DockPosition position, View relativeTo)
	{
		// Remove panel from its current location first (updates mPanels lists,
		// detaches from parent). This is critical — AddView silently refuses
		// views that already have a parent, so we must detach first.
		RemoveFromTree(panel);

		// Save dock position for re-dock after floating
		panel.SaveDockPosition(position, relativeTo);

		if (position == .Float)
		{
			FloatPanel(panel, 100, 100);
			return;
		}

		// Clean up empty nodes left behind by the removal.
		// Grab a safe reference via ViewId in case cleanup invalidates relativeTo.
		ViewId relativeToId = (relativeTo != null) ? relativeTo.Id : .Invalid;
		CleanupEmptyNodes();

		// Re-resolve relativeTo — it may have been collapsed by cleanup
		var target = relativeTo;
		if (relativeToId.IsValid && Context != null)
		{
			let resolved = Context.GetElementById(relativeToId);
			if (resolved != null && !resolved.IsPendingDeletion)
				target = resolved;
			else
				target = mRootNode; // Fallback to root
		}
		else if (target != null && target.IsPendingDeletion)
		{
			target = mRootNode;
		}

		if (position == .Center)
		{
			// Add as tab to existing group or create new group
			if (let tabGroup = target as DockTabGroup)
			{
				tabGroup.AddPanel(panel);
			}
			else if (let existingPanel = target as DockablePanel)
			{
				// Wrap existing panel in a tab group
				let group = new DockTabGroup();
				ReplaceNode(existingPanel, group);
				group.AddPanel(existingPanel);
				group.AddPanel(panel);
			}
			else
			{
				// Target is a DockSplit or null — find first tab group in subtree
				DockTabGroup targetGroup = null;
				if (target != null)
					targetGroup = FindFirstTabGroup(target);
				if (targetGroup == null && mRootNode != null)
					targetGroup = FindFirstTabGroup(mRootNode);

				if (targetGroup != null)
				{
					targetGroup.AddPanel(panel);
				}
				else
				{
					// Empty tree — create new root
					let group = new DockTabGroup();
					group.AddPanel(panel);
					mRootNode = group;
					AddView(group);
				}
			}
			InvalidateLayout();
			return;
		}

		// Create split
		InsertSplit(target, panel, position);
	}

	/// Undock a panel from its current position.
	public void UndockPanel(DockablePanel panel)
	{
		RemoveFromTree(panel);
		CleanupEmptyNodes();
		InvalidateLayout();
	}

	/// Float a panel at the given position.
	/// Uses OS windows if FloatingWindowHost supports it, otherwise PopupLayer.
	public void FloatPanel(DockablePanel panel, float x, float y)
	{
		// Remove from current position if docked
		RemoveFromTree(panel);

		let floating = new FloatingWindow(panel);
		mFloatingWindows.Add(floating);

		// Subscribe to dock/close requests
		floating.OnDockRequested.Subscribe(new (fw) => { RedockFloatingWindow(fw); });
		floating.OnCloseRequested.Subscribe(new (fw) => { CloseFloatingWindow(fw); });

		bool useOSWindow = (FloatingWindowHost != null && FloatingWindowHost.SupportsOSWindows);

		if (useOSWindow)
		{
			// OS window mode
			floating.[Friend]mIsOSWindow = true;
			// Pass close callback so Application can notify us when the OS window is closed
			FloatingWindowHost.CreateFloatingWindow(floating, 300, 250, x, y,
				new (view) => {
					if (let fw = view as FloatingWindow)
						CloseFloatingWindow(fw);
				});
		}
		else
		{
			// Virtual mode via PopupLayer
			floating.[Friend]mIsOSWindow = false;
			if (Context != null)
			{
				RootView?.PopupLayer?.ShowPopup(floating, this, x, y, false, true);
			}
		}

		CleanupEmptyNodes();
		InvalidateLayout();
	}

	/// Close a panel (undock and delete).
	public void ClosePanel(DockablePanel panel)
	{
		UndockPanel(panel);
		mPanels.Remove(panel);
		QueueDeleteNode(panel);
	}

	/// Re-dock a floating window back into the dock tree.
	public void RedockFloatingWindow(FloatingWindow floating)
	{
		let panel = floating.DetachPanel();
		if (panel == null) return;

		// Remove floating window
		DestroyFloatingWindow(floating);

		// Try to dock at last known position
		View relativeTo = null;
		if (panel.mLastRelativeToId.IsValid && Context != null)
			relativeTo = Context.GetElementById(panel.mLastRelativeToId);

		if (relativeTo != null)
			DockPanelRelativeTo(panel, panel.mLastDockPosition, relativeTo);
		else
			DockPanel(panel, .Center);
	}

	/// Close a floating window (destroy window, close panel).
	public void CloseFloatingWindow(FloatingWindow floating)
	{
		let panel = floating.DetachPanel();

		DestroyFloatingWindow(floating);

		if (panel != null)
		{
			mPanels.Remove(panel);
			QueueDeleteNode(panel);
		}
	}

	/// Close all floating windows.
	private void CloseAllFloatingWindows()
	{
		for (int i = mFloatingWindows.Count - 1; i >= 0; i--)
		{
			let floating = mFloatingWindows[i];
			let panel = floating.DetachPanel();

			if (floating.[Friend]mIsOSWindow && FloatingWindowHost != null)
			{
				FloatingWindowHost.DestroyFloatingWindow(floating);
				delete floating;
			}
			else
			{
				RootView?.PopupLayer?.ClosePopup(floating);
			}

			mFloatingWindows.RemoveAt(i);

			// Panel was detached from the floating window and is now orphaned.
			// Delete it so it doesn't leak.
			if (panel != null)
			{
				mPanels.Remove(panel);
				delete panel;
			}
		}
	}

	/// Destroy a single floating window (OS or virtual).
	public void DestroyFloatingWindow(FloatingWindow floating)
	{
		// Remove from tracking
		mFloatingWindows.Remove(floating);

		if (floating.[Friend]mIsOSWindow && FloatingWindowHost != null)
		{
			// Application detaches floating from RootView but doesn't delete it
			FloatingWindowHost.DestroyFloatingWindow(floating);
			QueueDeleteNode(floating);
		}
		else
		{
			// ClosePopup handles deletion (ownsView=true)
			RootView?.PopupLayer?.ClosePopup(floating);
		}
	}

	// ===== Internal tree operations =====

	private void InsertSplit(View existingNode, DockablePanel panel, DockPosition position)
	{
		let orientation = (position == .Left || position == .Right) ? Orientation.Horizontal : Orientation.Vertical;
		let split = new DockSplit(orientation);

		let group = new DockTabGroup();
		group.AddPanel(panel);

		if (existingNode == null)
		{
			if (mRootNode != null)
			{
				// Detach root BEFORE SetChildren — AddView silently refuses
				// views that already have a parent.
				DetachView(mRootNode);

				bool panelFirst = (position == .Left || position == .Top);
				if (panelFirst)
					split.SetChildren(group, mRootNode);
				else
					split.SetChildren(mRootNode, group);
			}
			else
			{
				split.SetChildren(group, null);
			}
			mRootNode = split;
			AddView(split);
		}
		else
		{
			bool panelFirst = (position == .Left || position == .Top);

			let parent = existingNode.Parent;
			if (parent == this)
			{
				DetachView(existingNode);
				if (panelFirst)
					split.SetChildren(group, existingNode);
				else
					split.SetChildren(existingNode, group);
				mRootNode = split;
				AddView(split);
			}
			else if (let parentSplit = parent as DockSplit)
			{
				// Capture the other child BEFORE detaching — DockSplit.First/Second
				// are index-based, so detaching shifts the array. Also must detach
				// both to prevent SetChildren → RemoveAllViews from deleting them.
				bool isFirst = (parentSplit.First == existingNode);
				let otherChild = isFirst ? parentSplit.Second : parentSplit.First;

				parentSplit.DetachView(existingNode);
				if (otherChild != null) parentSplit.DetachView(otherChild);

				if (panelFirst)
					split.SetChildren(group, existingNode);
				else
					split.SetChildren(existingNode, group);

				if (isFirst)
					parentSplit.SetChildren(split, otherChild);
				else
					parentSplit.SetChildren(otherChild, split);
			}
		}

		InvalidateLayout();
	}

	private void RemoveFromTree(DockablePanel panel)
	{
		// Check if in a tab group
		if (let tabGroup = panel.Parent as DockTabGroup)
		{
			tabGroup.RemovePanel(panel);
			return;
		}

		// Direct child of a split or root
		if (panel.Parent == this && mRootNode == panel)
		{
			DetachView(panel);
			mRootNode = null;
			return;
		}

		// In a floating window
		for (int i = 0; i < mFloatingWindows.Count; i++)
		{
			if (mFloatingWindows[i].Panel == panel)
			{
				let floating = mFloatingWindows[i];
				floating.DetachPanel();
				DestroyFloatingWindow(floating);
				return;
			}
		}
	}

	private void ReplaceNode(View oldNode, View newNode)
	{
		if (oldNode == mRootNode)
		{
			DetachView(oldNode);
			mRootNode = newNode;
			AddView(newNode);
		}
		else if (let parentSplit = oldNode.Parent as DockSplit)
		{
			// Capture other child and detach both BEFORE SetChildren.
			// RemoveAllViews (called by SetChildren) DELETES children,
			// so we must detach to prevent use-after-free.
			bool isFirst = (parentSplit.First == oldNode);
			let other = isFirst ? parentSplit.Second : parentSplit.First;

			parentSplit.DetachView(oldNode);
			if (other != null) parentSplit.DetachView(other);

			if (isFirst)
				parentSplit.SetChildren(newNode, other);
			else
				parentSplit.SetChildren(other, newNode);
		}
	}

	private void CleanupEmptyNodes()
	{
		if (mRootNode != null)
			mRootNode = CleanupNode(mRootNode);
	}

	private View CleanupNode(View node)
	{
		if (let split = node as DockSplit)
		{
			// Detach both children upfront to avoid index-shifting bugs.
			// DockSplit.First/Second are index-based (GetChildAt(0/1)), so detaching
			// the first child shifts the second to index 0. SetChildren() calls
			// RemoveAllViews() which DELETES remaining children. By detaching both
			// first, we own them safely and avoid use-after-free.
			let first = split.First;
			let second = split.Second;

			if (second != null) split.DetachView(second);
			if (first != null) split.DetachView(first);

			// Recursively clean the detached children
			let cleanFirst = (first != null) ? CleanupNode(first) : null;
			let cleanSecond = (second != null) ? CleanupNode(second) : null;

			// Queue originals for deletion if they were replaced
			if (first != null && cleanFirst != first) QueueDeleteNode(first);
			if (second != null && cleanSecond != second) QueueDeleteNode(second);

			// Rebuild based on results
			if (cleanFirst != null && cleanSecond != null)
			{
				// Both survived — re-attach to split
				split.AddView(cleanFirst);
				split.AddView(cleanSecond);
				return node;
			}
			else if (cleanFirst != null)
			{
				// Only first survived — collapse split
				if (split == mRootNode)
				{
					DetachView(split);
					QueueDeleteNode(split);
					AddView(cleanFirst);
				}
				else
					QueueDeleteNode(split);
				return cleanFirst;
			}
			else if (cleanSecond != null)
			{
				// Only second survived — collapse split
				if (split == mRootNode)
				{
					DetachView(split);
					QueueDeleteNode(split);
					AddView(cleanSecond);
				}
				else
					QueueDeleteNode(split);
				return cleanSecond;
			}
			else
			{
				// Both null — split is empty
				if (split == mRootNode)
				{
					DetachView(split);
					QueueDeleteNode(split);
				}
				else
					QueueDeleteNode(split);
				return null;
			}
		}
		else if (let tabGroup = node as DockTabGroup)
		{
			if (tabGroup.PanelCount == 0)
			{
				if (tabGroup == mRootNode)
				{
					DetachView(tabGroup);
					QueueDeleteNode(tabGroup);
				}
				// Non-root empty tab groups: caller handles deletion
				return null;
			}
		}

		return node;
	}

	/// Delete a dock tree node safely via MutationQueue or direct delete.
	private void QueueDeleteNode(View node)
	{
		if (Context != null)
			Context.MutationQueue.QueueDelete(node);
		else
			delete node;
	}

	// ===== Layout & Drawing =====

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(400, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(300, MinHeight, MaxHeight);

		if (mRootNode != null)
			mRootNode.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(h));

		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		if (mRootNode != null)
			mRootNode.Layout(0, 0, width, height);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		let bgColor = theme?.GetColor("DockManager", "background") ?? Palette.Darken(palette.Background, 0.05f);
		ctx.FillRect(.(0, 0, Width, Height), bgColor);

		if (mRootNode != null)
			mRootNode.Draw(ctx);

		// Draw zone indicator overlay
		if (mZoneIndicator.Visibility != .Gone)
			mZoneIndicator.Draw(ctx);
	}

	// ===== IDropTarget =====

	public DragDropEffects CanAcceptDrop(DragData data, float localX, float localY)
	{
		if (data.Format == "dock/panel")
			return .Move;
		return .None;
	}

	public void OnDragEnter(DragData data, float localX, float localY)
	{
		System.Console.WriteLine($"[DockManager.OnDragEnter] format='{data.Format}' at ({localX}, {localY})");
		if (data.Format == "dock/panel")
			ShowZoneIndicators(localX, localY);
	}

	public void OnDragOver(DragData data, float localX, float localY)
	{
		if (mZoneIndicator.Visibility != .Gone)
		{
			// Regenerate zone indicators based on current cursor position
			ShowZoneIndicators(localX, localY);
			mZoneIndicator.UpdateHover(localX, localY);
		}
	}

	public void OnDragLeave(DragData data)
	{
		System.Console.WriteLine("[DockManager.OnDragLeave]");
		HideZoneIndicators();
	}

	public DragDropEffects OnDrop(DragData data, float localX, float localY)
	{
		System.Console.WriteLine($"[DockManager.OnDrop] at ({localX}, {localY})");
		if (let panelData = data as DockPanelDragData)
		{
			let target = mZoneIndicator.GetHoveredTarget(localX, localY);
			HideZoneIndicators();

			if (target.HasValue)
			{
				let t = target.Value;
				if (t.Position == .Float)
					FloatPanel(panelData.Panel, localX, localY);
				else
					DockPanelRelativeTo(panelData.Panel, t.Position, t.TargetNode);
				return .Move;
			}
			else
			{
				// Dropped inside DockManager but not on a zone — float at cursor
				let screenPos = ToScreen(.(localX, localY));
				FloatPanel(panelData.Panel, screenPos.X, screenPos.Y);
				return .Move;
			}
		}

		HideZoneIndicators();
		return .None;
	}

	private void ShowZoneIndicators(float cursorX, float cursorY)
	{
		let targets = scope List<DockTarget>();
		float zoneSize = 40;

		if (mRootNode == null)
		{
			// No root — just show center zone
			float cx = Width * 0.5f;
			float cy = Height * 0.5f;
			targets.Add(.(DockPosition.Center, null, .(cx - zoneSize * 0.5f, cy - zoneSize * 0.5f, zoneSize, zoneSize)));
		}
		else
		{
			// Root-level edge zones always shown
			float cx = Width * 0.5f;
			float cy = Height * 0.5f;

			targets.Add(.(DockPosition.Top, mRootNode, .(cx - zoneSize * 0.5f, 8, zoneSize, zoneSize)));
			targets.Add(.(DockPosition.Bottom, mRootNode, .(cx - zoneSize * 0.5f, Height - zoneSize - 8, zoneSize, zoneSize)));
			targets.Add(.(DockPosition.Left, mRootNode, .(8, cy - zoneSize * 0.5f, zoneSize, zoneSize)));
			targets.Add(.(DockPosition.Right, mRootNode, .(Width - zoneSize - 8, cy - zoneSize * 0.5f, zoneSize, zoneSize)));

			// Walk tree to find the hovered leaf node and add its zones
			let hoveredNode = FindHoveredDockNode(mRootNode, cursorX, cursorY);
			if (hoveredNode != null)
			{
				let bounds = GetNodeBounds(hoveredNode);

				if (bounds.Width > 0 && bounds.Height > 0)
				{
					float ncx = bounds.X + bounds.Width * 0.5f;
					float ncy = bounds.Y + bounds.Height * 0.5f;
					float smallZone = 32;

					// Center zone (add as tab)
					targets.Add(.(DockPosition.Center, hoveredNode,
						.(ncx - smallZone * 0.5f, ncy - smallZone * 0.5f, smallZone, smallZone)));

					// Edge zones on the hovered node
					float edgeOffset = smallZone + 4;
					targets.Add(.(DockPosition.Top, hoveredNode,
						.(ncx - smallZone * 0.5f, ncy - edgeOffset - smallZone * 0.5f, smallZone, smallZone)));
					targets.Add(.(DockPosition.Bottom, hoveredNode,
						.(ncx - smallZone * 0.5f, ncy + edgeOffset - smallZone * 0.5f, smallZone, smallZone)));
					targets.Add(.(DockPosition.Left, hoveredNode,
						.(ncx - edgeOffset - smallZone * 0.5f, ncy - smallZone * 0.5f, smallZone, smallZone)));
					targets.Add(.(DockPosition.Right, hoveredNode,
						.(ncx + edgeOffset - smallZone * 0.5f, ncy - smallZone * 0.5f, smallZone, smallZone)));
				}
			}
		}

		mZoneIndicator.SetTargets(targets);
		mZoneIndicator.Visibility = .Visible;
		mZoneIndicator.Layout(0, 0, Width, Height);
	}

	/// Find the leaf DockTabGroup or DockSplit that the cursor is over.
	private View FindHoveredDockNode(View node, float localX, float localY)
	{
		if (let split = node as DockSplit)
		{
			// Check which child the cursor is over
			if (split.First != null)
			{
				let bounds = GetNodeBounds(split.First);
				if (localX >= bounds.X && localX < bounds.X + bounds.Width &&
					localY >= bounds.Y && localY < bounds.Y + bounds.Height)
				{
					return FindHoveredDockNode(split.First, localX, localY);
				}
			}
			if (split.Second != null)
			{
				let bounds = GetNodeBounds(split.Second);
				if (localX >= bounds.X && localX < bounds.X + bounds.Width &&
					localY >= bounds.Y && localY < bounds.Y + bounds.Height)
				{
					return FindHoveredDockNode(split.Second, localX, localY);
				}
			}
			return node;
		}
		else if (node is DockTabGroup)
		{
			return node;
		}
		return node;
	}

	/// Find the first DockTabGroup in a subtree (depth-first).
	private DockTabGroup FindFirstTabGroup(View node)
	{
		if (let tabGroup = node as DockTabGroup)
			return tabGroup;

		if (let split = node as DockSplit)
		{
			if (split.First != null)
			{
				let result = FindFirstTabGroup(split.First);
				if (result != null) return result;
			}
			if (split.Second != null)
				return FindFirstTabGroup(split.Second);
		}

		return null;
	}

	/// Get the bounds of a dock tree node in DockManager local coordinates.
	private RectangleF GetNodeBounds(View node)
	{
		// Walk up from node to DockManager, accumulating offsets
		float x = 0;
		float y = 0;
		var current = node;
		while (current != null && current != this)
		{
			x += current.Left;
			y += current.Top;
			current = current.Parent;
		}
		return .(x, y, node.Width, node.Height);
	}

	private void HideZoneIndicators()
	{
		mZoneIndicator.ClearTargets();
		mZoneIndicator.Visibility = .Gone;
	}

	// ===== IPopupOwner =====

	public void OnPopupClosed(View popup)
	{
		// Remove floating window tracking when popup is closed
		for (int i = mFloatingWindows.Count - 1; i >= 0; i--)
		{
			if (mFloatingWindows[i] == popup)
			{
				mFloatingWindows.RemoveAt(i);
				break;
			}
		}
	}
}
