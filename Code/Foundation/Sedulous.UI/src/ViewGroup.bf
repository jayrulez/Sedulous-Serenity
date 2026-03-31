namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// A View that contains child Views.
/// Manages child list with ownership (destructor deletes children).
/// Subclasses implement layout by overriding OnMeasure and OnLayout.
public abstract class ViewGroup : View
{
	private List<View> mChildren = new .() ~ DeleteContainerAndItems!(_);

	//==========================================================================
	// Child Management
	//==========================================================================

	/// Number of children.
	public int ChildCount => mChildren.Count;

	/// Get child at index.
	public View GetChildAt(int index)
	{
		if (index < 0 || index >= mChildren.Count)
			return null;
		return mChildren[index];
	}

	/// Add a child view. Sets up layout params if needed.
	/// The ViewGroup takes ownership of the child.
	public virtual void AddView(View child)
	{
		if (child == null || child.Parent != null)
			return;

		AddViewInternal(child);
	}

	/// Add a child view with specific layout params.
	public void AddView(View child, LayoutParams lp)
	{
		if (child == null || child.Parent != null)
			return;

		child.LayoutParams = lp;
		AddViewInternal(child);
	}

	/// Insert a child at a specific index.
	public void InsertView(View child, int index)
	{
		if (child == null || child.Parent != null)
			return;

		child.[Friend]SetParent(this);
		EnsureLayoutParams(child);
		int clampedIndex = Math.Clamp(index, 0, mChildren.Count);
		mChildren.Insert(clampedIndex, child);

		if (Context != null)
			child.OnAttachedToContext(Context);

		InvalidateLayout();
	}

	/// Remove a child view. The child is deleted.
	public void RemoveView(View child)
	{
		if (child == null || child.Parent != this)
			return;

		RemoveViewInternal(child);
		delete child;
	}

	/// Remove child at index. The child is deleted.
	public void RemoveViewAt(int index)
	{
		if (index < 0 || index >= mChildren.Count)
			return;

		let child = mChildren[index];
		RemoveViewInternal(child);
		delete child;
	}

	/// Remove all children. All children are deleted.
	public void RemoveAllViews()
	{
		for (let child in mChildren)
		{
			child.[Friend]SetParent(null);
			if (Context != null)
				child.OnDetachedFromContext(Context);
			delete child;
		}
		mChildren.Clear();
		InvalidateLayout();
	}

	/// Remove a child without deleting it. Transfers ownership to the caller.
	/// The caller is responsible for deleting the returned view.
	public View DetachView(View child)
	{
		if (child == null || child.Parent != this)
			return null;

		RemoveViewInternal(child);
		return child;
	}

	/// Find a view by tag recursively.
	public View FindViewByTag(StringView tag)
	{
		if (Tag != null && Tag == tag)
			return this;

		for (let child in mChildren)
		{
			if (child.Tag != null && child.Tag == tag)
				return child;

			if (let childGroup = child as ViewGroup)
			{
				let found = childGroup.FindViewByTag(tag);
				if (found != null)
					return found;
			}
		}

		return null;
	}

	//==========================================================================
	// Internal child management (used by MutationQueue)
	//==========================================================================

	internal void AddViewInternal(View child)
	{
		child.[Friend]SetParent(this);
		EnsureLayoutParams(child);
		mChildren.Add(child);

		if (Context != null)
			child.OnAttachedToContext(Context);

		InvalidateLayout();
	}

	internal void RemoveViewInternal(View child)
	{
		child.[Friend]SetParent(null);
		if (Context != null)
			child.OnDetachedFromContext(Context);

		mChildren.Remove(child);
		InvalidateLayout();
	}

	//==========================================================================
	// Layout Params Factory
	//==========================================================================

	/// Create default layout params for children that don't have any.
	/// Override in subclasses to create specialized LayoutParams.
	protected virtual LayoutParams CreateDefaultLayoutParams()
	{
		return new LayoutParams();
	}

	/// Check if the given layout params are compatible with this ViewGroup.
	/// Override in subclasses to validate or upgrade params.
	protected virtual bool CheckLayoutParams(LayoutParams lp)
	{
		return lp != null;
	}

	private void EnsureLayoutParams(View child)
	{
		if (child.LayoutParams == null || !CheckLayoutParams(child.LayoutParams))
		{
			child.LayoutParams = CreateDefaultLayoutParams();
		}
	}

	//==========================================================================
	// Measure Helpers
	//==========================================================================

	/// Measure a child with this ViewGroup's constraints.
	protected void MeasureChild(View child, MeasureSpec parentWidthSpec, MeasureSpec parentHeightSpec)
	{
		let lp = child.LayoutParams ?? CreateDefaultLayoutParams();

		let childWidthSpec = GetChildMeasureSpec(parentWidthSpec, Padding.Horizontal, lp.Width);
		let childHeightSpec = GetChildMeasureSpec(parentHeightSpec, Padding.Vertical, lp.Height);

		child.Measure(childWidthSpec, childHeightSpec);
	}

	/// Measure a child considering margins.
	protected void MeasureChildWithMargins(View child, MeasureSpec parentWidthSpec, float widthUsed, MeasureSpec parentHeightSpec, float heightUsed)
	{
		let lp = child.LayoutParams ?? CreateDefaultLayoutParams();

		let childWidthSpec = GetChildMeasureSpec(parentWidthSpec, Padding.Horizontal + lp.Margin.Horizontal + widthUsed, lp.Width);
		let childHeightSpec = GetChildMeasureSpec(parentHeightSpec, Padding.Vertical + lp.Margin.Vertical + heightUsed, lp.Height);

		child.Measure(childWidthSpec, childHeightSpec);
	}

	/// Create a MeasureSpec for a child based on parent constraints and child's layout params.
	public static MeasureSpec GetChildMeasureSpec(MeasureSpec parentSpec, float padding, float childDimension)
	{
		float available = Math.Max(0, parentSpec.Size - padding);

		if (childDimension >= 0)
		{
			// Child wants an exact size
			return .MakeExactly(childDimension);
		}
		else if (childDimension == LayoutParams.MatchParent)
		{
			switch (parentSpec.SpecMode)
			{
			case .Exactly:
				return .MakeExactly(available);
			case .AtMost:
				return .MakeAtMost(available);
			case .Unspecified:
				return .MakeUnspecified();
			}
		}
		else // WrapContent
		{
			switch (parentSpec.SpecMode)
			{
			case .Exactly, .AtMost:
				return .MakeAtMost(available);
			case .Unspecified:
				return .MakeUnspecified();
			}
		}
	}

	//==========================================================================
	// Drawing
	//==========================================================================

	/// Draw children in order (first child is lowest, last child is topmost).
	protected override void OnDraw(DrawContext ctx)
	{
		for (let child in mChildren)
		{
			child.Draw(ctx);
		}
	}

	//==========================================================================
	// Hit Testing
	//==========================================================================

	/// Hit test children in reverse order (topmost first), then self.
	public override View HitTest(Vector2 point)
	{
		if (Visibility != .Visible || !IsHitTestVisible || IsPendingDeletion)
			return null;

		// Convert from parent coords to local coords
		var localPoint = PointToLocal(point);

		// Check bounds
		if (localPoint.X < 0 || localPoint.Y < 0 || localPoint.X > Width || localPoint.Y > Height)
			return null;

		// Test children in reverse order (topmost first)
		for (int i = mChildren.Count - 1; i >= 0; i--)
		{
			let child = mChildren[i];
			let hit = child.HitTest(localPoint);
			if (hit != null)
				return hit;
		}

		// No child hit, return self
		return this;
	}

	//==========================================================================
	// Lifecycle
	//==========================================================================

	public override void OnAttachedToContext(UIContext context)
	{
		base.OnAttachedToContext(context);

		// Propagate to children
		for (let child in mChildren)
		{
			child.OnAttachedToContext(context);
		}
	}

	public override void OnDetachedFromContext(UIContext context)
	{
		// Propagate to children first
		for (let child in mChildren)
		{
			child.OnDetachedFromContext(context);
		}

		base.OnDetachedFromContext(context);
	}

	public override void OnThemeChanged()
	{
		for (let child in mChildren)
			child.OnThemeChanged();
	}

	//==========================================================================
	// Input Interception
	//==========================================================================

	/// Override to intercept mouse events before they reach children.
	/// Return true to steal the event (e.g., for scroll containers).
	/// Default returns false (don't intercept).
	public virtual bool OnInterceptMouseEvent(MouseEventArgs e)
	{
		return false;
	}

	//==========================================================================
	// Iteration
	//==========================================================================

	/// Iterate over children. For use in for-each loops.
	public List<View>.Enumerator GetChildren()
	{
		return mChildren.GetEnumerator();
	}
}
