using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// Base class for UI elements that can contain multiple children.
/// Used for layout containers like Panel, StackPanel, Grid, etc.
public abstract class CompositeControl : UIElement, IVisualChildProvider
{
	// Tree structure - children management
	private List<UIElement> mChildren = new .() ~ DeleteContainerAndItems!(_);

	/// Children of this element.
	public List<UIElement> Children => mChildren;

	// === Tree Manipulation ===

	/// Adds a child element.
	public void AddChild(UIElement child)
	{
		if (child.[Friend]mParent != null)
		{
			// Remove from previous parent
			if (let composite = child.[Friend]mParent as CompositeControl)
				composite.RemoveChild(child);
			else
				child.[Friend]mParent = null;
		}

		child.[Friend]mParent = this;
		mChildren.Add(child);
		InvalidateMeasure();
	}

	/// Inserts a child at the specified index.
	public void InsertChild(int index, UIElement child)
	{
		if (child.[Friend]mParent != null)
		{
			// Remove from previous parent
			if (let composite = child.[Friend]mParent as CompositeControl)
				composite.RemoveChild(child);
			else
				child.[Friend]mParent = null;
		}

		child.[Friend]mParent = this;
		mChildren.Insert(index, child);
		InvalidateMeasure();
	}

	/// Removes a child element.
	public bool RemoveChild(UIElement child)
	{
		if (mChildren.Remove(child))
		{
			child.[Friend]mParent = null;
			InvalidateMeasure();
			return true;
		}
		return false;
	}

	/// Removes all children.
	public void ClearChildren()
	{
		for (let child in mChildren)
		{
			child.[Friend]mParent = null;
			delete child;
		}
		mChildren.Clear();
		InvalidateMeasure();
	}

	// === Layout ===

	/// Override to measure content. Returns the desired content size.
	/// Default implementation measures children and returns size of largest.
	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		var maxWidth = 0.0f;
		var maxHeight = 0.0f;

		for (let child in mChildren)
		{
			child.Measure(constraints);
			maxWidth = Math.Max(maxWidth, child.DesiredSize.Width);
			maxHeight = Math.Max(maxHeight, child.DesiredSize.Height);
		}

		return .(maxWidth, maxHeight);
	}

	/// Override to arrange children within the content bounds.
	/// Default implementation arranges all children to fill content bounds.
	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		for (let child in mChildren)
		{
			child.Arrange(contentBounds);
		}
	}

	// === Rendering ===

	/// Renders the element and its children.
	public override void Render(DrawContext drawContext)
	{
		// Let base handle visibility, opacity, transform, clipping, and OnRender
		base.Render(drawContext);
	}

	/// Called after base rendering to render children.
	protected override void OnRender(DrawContext drawContext)
	{
		base.OnRender(drawContext);

		// Render children
		for (let child in mChildren)
		{
			child.Render(drawContext);
		}
	}

	// === Hit Testing ===

	/// Tests if the specified point hits this element or any child.
	/// Returns the deepest element hit, or null if no hit.
	public override UIElement HitTest(float x, float y)
	{
		if (Visibility != .Visible)
			return null;

		// Transform hit point if this element has a render transform
		var hitX = x;
		var hitY = y;

		if (HasRenderTransform)
		{
			// Calculate the inverse transform to map screen point to local space
			let originX = Bounds.X + Bounds.Width * RenderTransformOrigin.X;
			let originY = Bounds.Y + Bounds.Height * RenderTransformOrigin.Y;

			let toOrigin = Matrix.CreateTranslation(-originX, -originY, 0);
			let fromOrigin = Matrix.CreateTranslation(originX, originY, 0);
			let fullTransform = toOrigin * RenderTransform * fromOrigin;

			// Try to invert the transform
			Matrix inverseTransform;
			if (Matrix.TryInvert(fullTransform, out inverseTransform))
			{
				let transformed = Vector2.Transform(.(x, y), inverseTransform);
				hitX = transformed.X;
				hitY = transformed.Y;
			}
		}

		// Check if point is within bounds
		if (!Bounds.Contains(hitX, hitY))
			return null;

		// Check children in reverse order (front to back)
		for (int i = mChildren.Count - 1; i >= 0; i--)
		{
			let result = mChildren[i].HitTest(hitX, hitY);
			if (result != null)
				return result;
		}

		// No child hit, return this element
		return this;
	}

	// === Tree Searching ===

	/// Finds an element by ID in this element and its descendants.
	public override UIElement FindElementById(UIElementId id)
	{
		if (Id == id)
			return this;

		for (let child in mChildren)
		{
			let result = child.FindElementById(id);
			if (result != null)
				return result;
		}

		return null;
	}

	// === IVisualChildProvider ===

	/// Visits all visual children of this element.
	public void VisitVisualChildren(delegate void(UIElement) visitor)
	{
		for (let child in mChildren)
			visitor(child);
	}
}
