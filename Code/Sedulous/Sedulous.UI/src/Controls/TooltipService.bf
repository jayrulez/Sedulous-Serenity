using System;
using System.Collections;

namespace Sedulous.UI;

/// Interface for tooltip services.
public interface ITooltipService
{
	/// Attaches a tooltip with the specified text to an element.
	void SetTooltip(UIElement element, StringView text);

	/// Gets the tooltip text attached to an element, or empty if none.
	StringView GetTooltip(UIElement element);

	/// Checks if an element has a tooltip attached.
	bool HasTooltip(UIElement element);

	/// Removes the tooltip from an element.
	void ClearTooltip(UIElement element);

	/// Updates the tooltip system. Called from UIContext.Update().
	void Update(UIContext context, float deltaTime);

	/// Hides the current tooltip.
	void Hide();

	/// Called when an element is about to be deleted.
	/// Cleans up any tooltip state associated with the element.
	void OnElementDeleted(UIElement element);
}

/// Service for managing tooltips attached to UI elements.
public class TooltipService : ITooltipService
{
	private Dictionary<UIElement, String> mTooltipTexts = new .() ~ DeleteDictionaryAndValues!(_);
	private Tooltip mSharedTooltip ~ delete _;
	private UIElement mCurrentTarget;
	private float mHoverTime;
	private bool mIsShowing;

	public ~this()
	{
		Hide();
		mCurrentTarget = null;
	}

	/// Attaches a tooltip with the specified text to an element.
	public void SetTooltip(UIElement element, StringView text)
	{
		if (element == null)
			return;

		if (text.Length == 0)
		{
			// Remove tooltip
			if (mTooltipTexts.GetAndRemove(element) case .Ok(let pair))
				delete pair.value;
			return;
		}

		// Add or update tooltip text
		if (mTooltipTexts.TryGetValue(element, let existing))
		{
			existing.Set(text);
		}
		else
		{
			mTooltipTexts[element] = new String(text);
		}
	}

	/// Gets the tooltip text attached to an element, or empty if none.
	public StringView GetTooltip(UIElement element)
	{
		if (element != null && mTooltipTexts.TryGetValue(element, let text))
			return text;
		return "";
	}

	/// Checks if an element has a tooltip attached.
	public bool HasTooltip(UIElement element)
	{
		return element != null && mTooltipTexts.ContainsKey(element);
	}

	/// Removes the tooltip from an element.
	public void ClearTooltip(UIElement element)
	{
		if (element != null)
		{
			if (mTooltipTexts.GetAndRemove(element) case .Ok(let pair))
				delete pair.value;

			if (mCurrentTarget == element)
				Hide();
		}
	}

	/// Updates the tooltip system. Should be called from UIContext.Update().
	public void Update(UIContext context, float deltaTime)
	{
		if (context == null)
			return;

		let hoveredElement = context.[Friend]mHoveredElement;

		// Check if we have a tooltip for the hovered element
		UIElement tooltipTarget = null;
		String tooltipText = null;

		// Walk up the tree to find an element with a tooltip
		var element = hoveredElement;
		while (element != null)
		{
			if (mTooltipTexts.TryGetValue(element, let text))
			{
				tooltipTarget = element;
				tooltipText = text;
				break;
			}
			element = element.Parent;
		}

		if (tooltipTarget != mCurrentTarget)
		{
			// Target changed - hide current tooltip and reset timer
			if (mIsShowing)
				Hide();

			mCurrentTarget = tooltipTarget;
			mHoverTime = 0;
		}

		if (mCurrentTarget != null && !mIsShowing)
		{
			// Accumulate hover time
			mHoverTime += deltaTime;

			// Show after delay
			let delay = mSharedTooltip?.ShowDelay ?? 0.5f;
			if (mHoverTime >= delay && tooltipText != null)
			{
				Show(context, mCurrentTarget, tooltipText);
			}
		}
	}

	/// Shows a tooltip for the specified element.
	private void Show(UIContext context, UIElement target, StringView text)
	{
		if (mSharedTooltip == null)
			mSharedTooltip = new Tooltip();

		mSharedTooltip.Text = text;

		// Set context directly - tooltips are not part of the normal layout tree
		mSharedTooltip.[Friend]mContext = context;

		// Position below the target element
		let targetBounds = target.Bounds;
		let x = targetBounds.X;
		let y = targetBounds.Bottom + 4;

		// Measure tooltip to get size
		mSharedTooltip.Measure(SizeConstraints.FromMaximum(400, 100));
		let tooltipSize = mSharedTooltip.DesiredSize;

		// Clamp to viewport
		let viewportWidth = context.ViewportWidth;
		let viewportHeight = context.ViewportHeight;

		var posX = x;
		var posY = y;

		// Keep within horizontal bounds
		if (posX + tooltipSize.Width > viewportWidth)
			posX = viewportWidth - tooltipSize.Width - 4;
		if (posX < 4)
			posX = 4;

		// If tooltip would go below viewport, show above target
		if (posY + tooltipSize.Height > viewportHeight)
			posY = targetBounds.Y - tooltipSize.Height - 4;

		mSharedTooltip.OpenAt(posX, posY);
		mIsShowing = true;
	}

	/// Hides the current tooltip.
	public void Hide()
	{
		if (mSharedTooltip != null && mIsShowing)
		{
			mSharedTooltip.Close();
			mIsShowing = false;
		}
		mHoverTime = 0;
	}

	/// Called when an element is about to be deleted.
	/// Cleans up any tooltip state associated with the element.
	public void OnElementDeleted(UIElement element)
	{
		if (element == null)
			return;

		// Clear tooltip text for this element
		if (mTooltipTexts.GetAndRemove(element) case .Ok(let pair))
			delete pair.value;

		// Clear current target if it was this element
		if (mCurrentTarget == element)
		{
			Hide();
			mCurrentTarget = null;
		}
	}
}
