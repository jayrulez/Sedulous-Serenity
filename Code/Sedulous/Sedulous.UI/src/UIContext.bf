using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Main UI context - manages widget tree and rendering.
class UIContext
{
	private Widget mRoot;
	private InputManager mInput ~ delete _;
	private DrawContext mDrawContext ~ delete _;
	private Vector2 mViewportSize;
	private bool mNeedsLayout = true;

	/// Creates a new UI context.
	public this()
	{
		mInput = new InputManager(this);
		mDrawContext = new DrawContext();
	}

	/// Gets or sets the root widget.
	public Widget Root
	{
		get => mRoot;
		set
		{
			if (mRoot != null)
				mRoot.Context = null;

			mRoot = value;

			if (mRoot != null)
				mRoot.Context = this;

			mNeedsLayout = true;
		}
	}

	/// Gets the input manager.
	public InputManager Input => mInput;

	/// Gets or sets the viewport size.
	public Vector2 ViewportSize
	{
		get => mViewportSize;
		set
		{
			if (mViewportSize != value)
			{
				mViewportSize = value;
				mNeedsLayout = true;
			}
		}
	}

	// ============ Update ============

	/// Updates the UI (call once per frame).
	public void Update(float deltaTime)
	{
		if (mRoot == null)
			return;

		// Update layout if needed
		if (mNeedsLayout)
		{
			UpdateLayout();
		}

		// Update widgets
		mRoot.Update(deltaTime);
	}

	/// Forces a layout update.
	public void UpdateLayout()
	{
		if (mRoot == null)
			return;

		mRoot.Measure(mViewportSize);
		mRoot.Arrange(RectangleF(0, 0, mViewportSize.X, mViewportSize.Y));
		mNeedsLayout = false;
	}

	/// Invalidates layout, causing re-layout on next update.
	public void InvalidateLayout()
	{
		mNeedsLayout = true;
	}

	// ============ Rendering ============

	/// Renders the UI to a draw batch.
	public DrawBatch RenderToBatch()
	{
		mDrawContext.Clear();

		if (mRoot != null)
		{
			mRoot.Render(mDrawContext);
		}

		return mDrawContext.Finish();
	}

	/// Renders the UI using the provided draw context.
	public void Render(DrawContext dc)
	{
		if (mRoot != null)
		{
			mRoot.Render(dc);
		}
	}

	// ============ Input Injection ============

	/// Injects mouse movement.
	public void InjectMouseMove(Vector2 position)
	{
		mInput.ProcessMouseMove(position);
	}

	/// Injects mouse button event.
	public void InjectMouseButton(MouseButton button, bool pressed)
	{
		mInput.ProcessMouseButton(button, pressed, mInput.MousePosition);
	}

	/// Injects mouse button event at position.
	public void InjectMouseButton(MouseButton button, bool pressed, Vector2 position)
	{
		mInput.ProcessMouseButton(button, pressed, position);
	}

	/// Injects mouse wheel event.
	public void InjectMouseWheel(float deltaX, float deltaY)
	{
		mInput.ProcessMouseWheel(deltaX, deltaY, mInput.MousePosition);
	}

	/// Injects key down event.
	public void InjectKeyDown(KeyCode key, KeyModifiers modifiers = .None, bool isRepeat = false)
	{
		mInput.ProcessKeyDown(key, modifiers, isRepeat);
	}

	/// Injects key up event.
	public void InjectKeyUp(KeyCode key, KeyModifiers modifiers = .None)
	{
		mInput.ProcessKeyUp(key, modifiers);
	}

	/// Injects text input.
	public void InjectTextInput(StringView text)
	{
		mInput.ProcessTextInput(text);
	}

	// ============ Widget Lookup ============

	/// Finds a widget by ID.
	public Widget FindWidgetById(WidgetId id)
	{
		if (mRoot == null)
			return null;

		return FindWidgetByIdRecursive(mRoot, id);
	}

	/// Finds a widget by name.
	public Widget FindWidgetByName(StringView name)
	{
		if (mRoot == null)
			return null;

		return FindWidgetByNameRecursive(mRoot, name);
	}

	/// Finds a widget by name and casts to type.
	public T FindWidget<T>(StringView name) where T : Widget
	{
		return FindWidgetByName(name) as T;
	}

	private Widget FindWidgetByIdRecursive(Widget widget, WidgetId id)
	{
		if (widget.Id == id)
			return widget;

		for (let child in widget.Children)
		{
			let result = FindWidgetByIdRecursive(child, id);
			if (result != null)
				return result;
		}

		return null;
	}

	private Widget FindWidgetByNameRecursive(Widget widget, StringView name)
	{
		if (widget.Name == name)
			return widget;

		for (let child in widget.Children)
		{
			let result = FindWidgetByNameRecursive(child, name);
			if (result != null)
				return result;
		}

		return null;
	}

	// ============ Hit Testing ============

	/// Performs hit testing at the specified position.
	public Widget HitTest(Vector2 position)
	{
		if (mRoot == null)
			return null;

		return mRoot.HitTestRecursive(position);
	}
}
