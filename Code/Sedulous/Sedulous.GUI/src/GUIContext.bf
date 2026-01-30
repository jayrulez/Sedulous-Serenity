using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.GUI;

/// Central context that owns and manages the UI system.
/// All UI elements belong to a context, and services are registered here.
public class GUIContext
{
	// Element registry - maps IDs to elements for safe handle resolution
	private Dictionary<UIElementId, UIElement> mElementRegistry = new .() ~ delete _;

	// Root element of the UI tree
	private UIElement mRootElement;

	// Mutation queue for deferred tree modifications
	private MutationQueue mMutationQueue = new .() ~ delete _;

	// Layout state
	private bool mLayoutDirty = true;
	private float mViewportWidth;
	private float mViewportHeight;

	// Timing
	private double mTotalTime;
	private float mDeltaTime;

	/// The root element of the UI tree.
	public UIElement RootElement
	{
		get => mRootElement;
		set
		{
			if (mRootElement == value)
				return;

			// Detach old root
			if (mRootElement != null)
			{
				mRootElement.OnDetachedFromContext();
			}

			mRootElement = value;

			// Attach new root
			if (mRootElement != null)
			{
				mRootElement.OnAttachedToContext(this);
			}

			InvalidateLayout();
		}
	}

	/// The mutation queue for deferred tree modifications.
	public MutationQueue MutationQueue => mMutationQueue;

	/// The current viewport width.
	public float ViewportWidth => mViewportWidth;

	/// The current viewport height.
	public float ViewportHeight => mViewportHeight;

	/// Total elapsed time in seconds.
	public double TotalTime => mTotalTime;

	/// Time since last frame in seconds.
	public float DeltaTime => mDeltaTime;

	// === Element Registry ===

	/// Registers an element in the registry.
	/// Called automatically when elements are attached to the context.
	public void RegisterElement(UIElement element)
	{
		if (element == null)
			return;
		mElementRegistry[element.Id] = element;
	}

	/// Unregisters an element from the registry.
	/// Called automatically when elements are detached or deleted.
	public void UnregisterElement(UIElement element)
	{
		if (element == null)
			return;
		mElementRegistry.Remove(element.Id);
	}

	/// Gets an element by its ID.
	/// Returns null if the element doesn't exist.
	public UIElement GetElementById(UIElementId id)
	{
		if (mElementRegistry.TryGetValue(id, let element))
			return element;
		return null;
	}

	/// Gets an element by ID and casts to the specified type.
	/// Returns null if not found or wrong type.
	public T GetElementById<T>(UIElementId id) where T : UIElement
	{
		return GetElementById(id) as T;
	}

	// === Viewport ===

	/// Sets the viewport size.
	public void SetViewportSize(float width, float height)
	{
		if (mViewportWidth != width || mViewportHeight != height)
		{
			mViewportWidth = width;
			mViewportHeight = height;
			InvalidateLayout();
		}
	}

	// === Layout ===

	/// Marks the layout as needing recalculation.
	public void InvalidateLayout()
	{
		mLayoutDirty = true;
	}

	/// Updates the layout if needed.
	private void UpdateLayout()
	{
		if (!mLayoutDirty || mRootElement == null)
			return;

		// Measure pass
		let constraints = SizeConstraints.FromMaximum(mViewportWidth, mViewportHeight);
		mRootElement.Measure(constraints);

		// Arrange pass
		let viewport = RectangleF(0, 0, mViewportWidth, mViewportHeight);
		mRootElement.Arrange(viewport);

		mLayoutDirty = false;
	}

	// === Update ===

	/// Updates the UI system. Call once per frame.
	/// @param deltaTime Time since last frame in seconds.
	/// @param totalTime Total elapsed time in seconds.
	public void Update(float deltaTime, double totalTime)
	{
		mDeltaTime = deltaTime;
		mTotalTime = totalTime;

		// Update layout
		UpdateLayout();

		// Process any pending mutations
		mMutationQueue.Process(this);
	}

	// === Rendering ===

	/// Renders the UI tree.
	public void Render(DrawContext ctx)
	{
		if (mRootElement == null)
			return;

		mRootElement.Render(ctx);
	}

	// === Hit Testing ===

	/// Performs hit testing at the given screen coordinates.
	/// Returns the topmost element at that position, or null.
	public UIElement HitTest(float x, float y)
	{
		if (mRootElement == null)
			return null;

		return mRootElement.HitTest(.(x, y));
	}

	// === Deletion ===

	/// Queues an element for deletion.
	/// The element will be removed from its parent and deleted at the end of the frame.
	/// Safe to call from event handlers.
	public void QueueDelete(UIElement element)
	{
		mMutationQueue.QueueDelete(element);
	}
}
