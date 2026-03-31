namespace Sedulous.UI;

using System;
using System.Collections;

/// Manages focus state and tab navigation within a UIContext.
public class FocusManager
{
	private UIContext mContext;
	private View mFocusedView;
	private View mCapturedView;

	// Pooled event args for focus transitions
	private FocusEventArgs mFocusEventArgs = new .() ~ delete _;

	public this(UIContext context)
	{
		mContext = context;
	}

	/// The currently focused view, or null.
	public View FocusedView => mFocusedView;

	/// The view that has mouse capture, or null.
	/// When set, all mouse events route to this view regardless of hit-test position.
	public View CapturedView => mCapturedView;

	/// Set focus to the given view. Pass null to clear focus.
	public void SetFocus(View view)
	{
		if (mFocusedView == view)
			return;

		// Lose focus on old view
		if (mFocusedView != null)
		{
			mFocusedView.[Friend]mIsFocused = false;
			mFocusEventArgs.Reset();
			mFocusedView.OnFocusLost(mFocusEventArgs);
		}

		mFocusedView = view;

		// Gain focus on new view
		if (mFocusedView != null)
		{
			mFocusedView.[Friend]mIsFocused = true;
			mFocusEventArgs.Reset();
			mFocusedView.OnFocusGained(mFocusEventArgs);
		}
	}

	/// Clear focus from the currently focused view.
	public void ClearFocus()
	{
		SetFocus(null);
	}

	/// Set mouse capture. All mouse events will route to this view until released.
	public void SetCapture(View view)
	{
		mCapturedView = view;
	}

	/// Release mouse capture.
	public void ReleaseCapture()
	{
		mCapturedView = null;
	}

	/// Move focus to the next focusable view in tab order.
	public void FocusNext()
	{
		AdvanceFocus(1);
	}

	/// Move focus to the previous focusable view in tab order.
	public void FocusPrevious()
	{
		AdvanceFocus(-1);
	}

	/// Called when a view is about to be deleted. Clears any references to it.
	public void OnElementDeleted(View view)
	{
		if (mFocusedView == view)
		{
			mFocusedView.[Friend]mIsFocused = false;
			mFocusedView = null;
		}

		if (mCapturedView == view)
			mCapturedView = null;
	}

	private void AdvanceFocus(int direction)
	{
		// Collect all focusable tab-stop views
		List<View> focusables = scope .();

		// If a modal popup exists, only collect focusables within it
		let popupLayer = mContext.ActivePopupLayer;
		if (popupLayer != null && popupLayer.HasModalPopup)
		{
			let modalPopup = popupLayer.TopModalPopup;
			if (modalPopup != null)
				CollectFocusableViews(modalPopup, focusables);
		}
		else if (mContext.ActiveInputRoot != null)
		{
			// Scope tab navigation to the active window's root
			CollectFocusableViews(mContext.ActiveInputRoot, focusables);
		}

		if (focusables.Count == 0)
			return;

		// HTML-style tab order:
		// TabIndex > 0 comes first (sorted by value), then TabIndex == 0 in tree order.
		focusables.Sort(scope (a, b) =>
		{
			// Both positive: sort by value
			if (a.TabIndex > 0 && b.TabIndex > 0)
				return a.TabIndex <=> b.TabIndex;
			// Positive comes before zero
			if (a.TabIndex > 0 && b.TabIndex == 0)
				return -1;
			if (a.TabIndex == 0 && b.TabIndex > 0)
				return 1;
			// Both zero: preserve tree order (stable sort)
			return 0;
		});

		// Find current position
		int currentIndex = -1;
		if (mFocusedView != null)
		{
			for (int i = 0; i < focusables.Count; i++)
			{
				if (focusables[i] == mFocusedView)
				{
					currentIndex = i;
					break;
				}
			}
		}

		// Advance with wrap-around
		int nextIndex;
		if (currentIndex < 0)
		{
			// No current focus — go to first (forward) or last (backward)
			nextIndex = (direction > 0) ? 0 : focusables.Count - 1;
		}
		else
		{
			nextIndex = currentIndex + direction;
			if (nextIndex >= focusables.Count)
				nextIndex = 0;
			else if (nextIndex < 0)
				nextIndex = focusables.Count - 1;
		}

		SetFocus(focusables[nextIndex]);
	}

	private static void CollectFocusableViews(View view, List<View> result)
	{
		if (view.Visibility != .Visible || !view.Enabled)
			return;

		if (view.Focusable && view.IsTabStop)
			result.Add(view);

		if (let group = view as ViewGroup)
		{
			for (int i = 0; i < group.ChildCount; i++)
				CollectFocusableViews(group.GetChildAt(i), result);
		}
	}
}
