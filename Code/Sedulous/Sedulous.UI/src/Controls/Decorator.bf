using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Base class for controls that wrap a single child element visually.
/// Examples: Border, Viewbox (future).
/// Use the `Child` property to set the wrapped element.
public abstract class Decorator : Control, IVisualChildProvider
{
	private UIElement mChild ~ delete _;

	/// The single child element inside the decorator.
	public UIElement Child
	{
		get => mChild;
		set
		{
			if (mChild != value)
			{
				if (mChild != null)
					mChild.[Friend]mParent = null;

				mChild = value;

				if (mChild != null)
					mChild.[Friend]mParent = this;

				InvalidateMeasure();
			}
		}
	}

	public this()
	{
		// Decorators are not focusable by default
		Focusable = false;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (mChild != null)
		{
			mChild.Measure(constraints);
			return mChild.DesiredSize;
		}
		return .Zero;
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		if (mChild != null)
		{
			mChild.Arrange(contentBounds);
		}
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		if (mChild != null)
			mChild.Render(drawContext);
	}

	/// Decorators handle their own rendering - skip Control's default background/border.
	protected override void OnRender(DrawContext drawContext)
	{
		// Don't call base.OnRender() - decorators draw their own background/border
		// Just render the child content
		RenderContent(drawContext);
	}

	/// Override HitTest to check child.
	public override UIElement HitTest(float x, float y)
	{
		if (Visibility != .Visible)
			return null;

		if (!Bounds.Contains(x, y))
			return null;

		// Check child first
		if (mChild != null)
		{
			let result = mChild.HitTest(x, y);
			if (result != null)
				return result;
		}

		return this;
	}

	/// Override FindElementById to search child.
	public override UIElement FindElementById(UIElementId id)
	{
		if (Id == id)
			return this;

		if (mChild != null)
		{
			let result = mChild.FindElementById(id);
			if (result != null)
				return result;
		}

		return null;
	}

	// === IVisualChildProvider ===

	/// Visits all visual children of this element.
	public void VisitVisualChildren(delegate void(UIElement) visitor)
	{
		if (mChild != null)
			visitor(mChild);
	}
}
