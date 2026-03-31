namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Overlay container that manages popups, dialogs, and tooltips.
/// Added as the last root view in UIContext so it draws on top and hit-tests first.
/// When empty, hit-testing passes through (returns null).
public class PopupLayer : ViewGroup
{
	private struct PopupEntry
	{
		public View Popup;
		public IPopupOwner Owner;
		public bool CloseOnClickOutside;
		public bool IsModal;
		public bool OwnsView; // If false, DetachView instead of RemoveView on close
		public float X;
		public float Y;
	}

	private List<PopupEntry> mEntries = new .() ~ delete _;
	private ModalBackdrop mBackdrop ~ {
		// Delete if detached (not in mChildren — ViewGroup handles children)
		if (_ != null && _.Parent != this) delete _;
	};

	/// Whether any popups are active.
	public bool HasPopups => mEntries.Count > 0;

	/// Whether any modal popup is active.
	public bool HasModalPopup
	{
		get
		{
			for (let entry in mEntries)
				if (entry.IsModal) return true;
			return false;
		}
	}

	/// The topmost modal popup view, or null.
	public View TopModalPopup
	{
		get
		{
			for (int i = mEntries.Count - 1; i >= 0; i--)
				if (mEntries[i].IsModal) return mEntries[i].Popup;
			return null;
		}
	}

	/// Number of active popups.
	public int PopupCount => mEntries.Count;

	/// Update the stored position of an active popup.
	public void UpdatePopupPosition(View popup, float x, float y)
	{
		for (int i = 0; i < mEntries.Count; i++)
		{
			if (mEntries[i].Popup == popup)
			{
				var entry = mEntries[i];
				entry.X = x;
				entry.Y = y;
				mEntries[i] = entry;
				InvalidateLayout();
				return;
			}
		}
	}

	public this()
	{
		// PopupLayer itself is invisible to hit-test when empty
		IsHitTestVisible = true;
	}

	public ~this()
	{
		// Detach non-owned popups before ViewGroup's destructor deletes all children.
		// These popups are owned elsewhere (e.g. MenuItem owns submenus) and would
		// otherwise be double-deleted.
		for (int i = mEntries.Count - 1; i >= 0; i--)
		{
			if (!mEntries[i].OwnsView && mEntries[i].Popup.Parent == this)
				DetachView(mEntries[i].Popup);
		}
	}

	/// Show a popup at the given position. PopupLayer takes ownership unless ownsView is false.
	public void ShowPopup(View popup, IPopupOwner owner, float x, float y, bool closeOnClickOutside = true, bool ownsView = true)
	{
		if (popup == null) return;

		// Don't add if already showing
		if (popup.Parent == this) return;

		PopupEntry entry;
		entry.Popup = popup;
		entry.Owner = owner;
		entry.CloseOnClickOutside = closeOnClickOutside;
		entry.IsModal = false;
		entry.OwnsView = ownsView;
		entry.X = x;
		entry.Y = y;
		mEntries.Add(entry);

		AddView(popup);
		InvalidateLayout();
	}

	/// Show a modal popup centered in the viewport. PopupLayer takes ownership.
	/// A backdrop is shown behind the popup to block input.
	public void ShowModalPopup(View popup, IPopupOwner owner = null)
	{
		if (popup == null) return;

		// Add backdrop if this is the first modal
		if (!HasModalPopup)
		{
			if (mBackdrop == null)
				mBackdrop = new ModalBackdrop();
			AddView(mBackdrop);
		}

		PopupEntry entry;
		entry.Popup = popup;
		entry.Owner = owner;
		entry.CloseOnClickOutside = false;
		entry.IsModal = true;
		entry.OwnsView = true;
		entry.X = 0; // Will be centered in OnLayout
		entry.Y = 0;
		mEntries.Add(entry);

		AddView(popup);
		InvalidateLayout();
	}

	/// Close a specific popup. Notifies the owner and deletes the popup view.
	public void ClosePopup(View popup)
	{
		if (popup == null) return;

		for (int i = 0; i < mEntries.Count; i++)
		{
			if (mEntries[i].Popup == popup)
			{
				let entry = mEntries[i];
				mEntries.RemoveAt(i);

				// Notify InputManager/FocusManager to clear references to the popup
				// and all its descendants before deletion (prevents dangling pointers)
				NotifyTreeDeleted(popup);

				// Remove the popup — delete if owned, detach if not
				if (entry.OwnsView)
					RemoveView(popup);
				else
					DetachView(popup);

				// Notify owner
				entry.Owner?.OnPopupClosed(popup);

				// Remove backdrop if no more modals
				if (!HasModalPopup && mBackdrop != null && mBackdrop.Parent == this)
				{
					DetachView(mBackdrop);
				}

				InvalidateLayout();
				return;
			}
		}
	}

	/// Close all popups.
	public void CloseAllPopups()
	{
		while (mEntries.Count > 0)
		{
			ClosePopup(mEntries[mEntries.Count - 1].Popup);
		}
	}

	/// Close all popups owned by the given owner.
	public void ClosePopupsOwnedBy(IPopupOwner owner)
	{
		for (int i = mEntries.Count - 1; i >= 0; i--)
		{
			if (mEntries[i].Owner == owner)
				ClosePopup(mEntries[i].Popup);
		}
	}

	/// Close the topmost popup (used by Escape key).
	public void CloseTopPopup()
	{
		if (mEntries.Count > 0)
			ClosePopup(mEntries[mEntries.Count - 1].Popup);
	}

	/// Handle a click outside all popups. Closes all close-on-click-outside popups
	/// (topmost first) so that submenu chains dismiss in a single click.
	public void HandleClickOutside(float screenX, float screenY)
	{
		while (true)
		{
			bool found = false;
			for (int i = mEntries.Count - 1; i >= 0; i--)
			{
				if (mEntries[i].CloseOnClickOutside)
				{
					ClosePopup(mEntries[i].Popup);
					found = true;
					break; // Restart since list was modified
				}
			}
			if (!found) break;
		}
	}

	public override View HitTest(Vector2 point)
	{
		if (Visibility != .Visible || IsPendingDeletion)
			return null;

		// When no popups, pass through entirely
		if (mEntries.Count == 0)
			return null;

		// Convert to local coords
		var localPoint = PointToLocal(point);

		// Hit-test children in reverse order (topmost popup first)
		for (int i = ChildCount - 1; i >= 0; i--)
		{
			let child = GetChildAt(i);
			let hit = child.HitTest(localPoint);
			if (hit != null)
				return hit;
		}

		// If a modal popup is active, the backdrop should have caught the click.
		// But if we reach here with modals, return self to block pass-through.
		if (HasModalPopup)
			return this;

		// No popup hit and not modal — pass through
		return null;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(0, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(0, MinHeight, MaxHeight);

		// Measure each popup child with AtMost constraints
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;

			if (child == mBackdrop)
			{
				child.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(h));
			}
			else
			{
				child.Measure(MeasureSpec.MakeAtMost(w), MeasureSpec.MakeAtMost(h));
			}
		}

		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		// Layout backdrop to fill
		if (mBackdrop != null && mBackdrop.Parent == this)
			mBackdrop.Layout(0, 0, width, height);

		// Layout each popup at its stored position
		for (let entry in mEntries)
		{
			let popup = entry.Popup;
			if (popup.Visibility == .Gone) continue;

			float x = entry.X;
			float y = entry.Y;

			if (entry.IsModal)
			{
				// Center modal popups
				x = (width - popup.MeasuredWidth) / 2;
				y = (height - popup.MeasuredHeight) / 2;
				if (x < 0) x = 0;
				if (y < 0) y = 0;
			}

			popup.Layout(x, y, popup.MeasuredWidth, popup.MeasuredHeight);
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		// Only draw if there are popups
		if (mEntries.Count == 0 && (mBackdrop == null || mBackdrop.Parent != this))
			return;

		// Draw all children (backdrop first, then popups in order)
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			child.Draw(ctx);
		}
	}

	/// Recursively notify that a view and all its descendants are about to be deleted.
	/// This clears dangling references in InputManager (mHoveredView, mPressedView)
	/// and FocusManager (mFocusedView, mCapturedView) before the actual deletion.
	private void NotifyTreeDeleted(View view)
	{
		if (view == null || Context == null) return;

		// Notify for children first (depth-first)
		if (let group = view as ViewGroup)
		{
			for (int i = 0; i < group.ChildCount; i++)
				NotifyTreeDeleted(group.GetChildAt(i));
		}

		Context.NotifyElementDeleted(view);
	}
}
