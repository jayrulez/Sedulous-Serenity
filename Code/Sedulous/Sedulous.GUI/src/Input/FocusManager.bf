using System;
using System.Collections;

namespace Sedulous.GUI;

/// Manages keyboard focus and tab navigation for a GUIContext.
public class FocusManager
{
	private GUIContext mContext;
	private Control mFocusedElement;
	private Control mCapturedElement;

	/// Creates a FocusManager for the specified context.
	public this(GUIContext context)
	{
		mContext = context;
	}

	/// The currently focused element.
	public Control FocusedElement => mFocusedElement;

	/// The element that has captured mouse input.
	public Control CapturedElement => mCapturedElement;

	/// Sets focus to the specified control.
	/// If the control is null, clears focus.
	public void SetFocus(Control control)
	{
		if (mFocusedElement == control)
			return;

		// Don't focus disabled or non-focusable controls
		if (control != null && (!control.IsFocusable || !control.IsEffectivelyEnabled))
			return;

		// Clear old focus
		if (mFocusedElement != null)
		{
			mFocusedElement.IsFocused = false;
		}

		mFocusedElement = control;

		// Set new focus
		if (mFocusedElement != null)
		{
			mFocusedElement.IsFocused = true;
		}
	}

	/// Clears focus from all elements.
	public void ClearFocus()
	{
		SetFocus(null);
	}

	/// Captures mouse input for the specified control.
	/// While captured, the control receives all mouse events regardless of position.
	public void SetCapture(Control control)
	{
		mCapturedElement = control;
	}

	/// Releases mouse capture.
	public void ReleaseCapture()
	{
		mCapturedElement = null;
	}

	/// Moves focus to the next focusable element in tab order.
	public void FocusNext()
	{
		MoveFocus(forward: true);
	}

	/// Moves focus to the previous focusable element in tab order.
	public void FocusPrevious()
	{
		MoveFocus(forward: false);
	}

	/// Moves focus in the specified direction.
	private void MoveFocus(bool forward)
	{
		// Collect all focusable controls
		let focusable = scope List<Control>();
		CollectFocusableControls(mContext.RootElement, focusable);

		if (focusable.Count == 0)
			return;

		// Sort by TabIndex
		focusable.Sort(scope (a, b) => a.TabIndex <=> b.TabIndex);

		// Find current focused index
		int currentIndex = -1;
		if (mFocusedElement != null)
		{
			currentIndex = focusable.IndexOf(mFocusedElement);
		}

		// Calculate next index
		int nextIndex;
		if (forward)
		{
			nextIndex = (currentIndex + 1) % focusable.Count;
		}
		else
		{
			nextIndex = currentIndex - 1;
			if (nextIndex < 0)
				nextIndex = focusable.Count - 1;
		}

		SetFocus(focusable[nextIndex]);
	}

	/// Recursively collects all focusable controls.
	private void CollectFocusableControls(UIElement element, List<Control> focusable)
	{
		if (element == null || element.Visibility != .Visible)
			return;

		// Check if this element is focusable
		if (let control = element as Control)
		{
			if (control.IsFocusable && control.IsTabStop && control.IsEffectivelyEnabled)
			{
				focusable.Add(control);
			}
		}

		// Recurse into visual children using polymorphic access
		let childCount = element.VisualChildCount;
		for (int i = 0; i < childCount; i++)
		{
			let child = element.GetVisualChild(i);
			if (child != null)
				CollectFocusableControls(child, focusable);
		}
	}

	/// Called when an element is about to be deleted.
	/// Clears focus/capture if they reference the element.
	public void OnElementDeleted(UIElement element)
	{
		if (mFocusedElement == element)
			mFocusedElement = null;
		if (mCapturedElement == element)
			mCapturedElement = null;
	}
}
