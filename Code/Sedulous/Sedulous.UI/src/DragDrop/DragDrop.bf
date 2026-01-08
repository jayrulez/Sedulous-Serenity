using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// Effects allowed for a drag operation.
[AllowDuplicates]
public enum DragDropEffects
{
	/// No drag operation allowed.
	None = 0,
	/// Copy the data.
	Copy = 1,
	/// Move the data.
	Move = 2,
	/// Link to the data.
	Link = 4,
	/// Scroll the target.
	Scroll = 8,
	/// All effects allowed.
	All = Copy | Move | Link | Scroll
}

/// Data object that can be dragged.
public class DragData
{
	private Dictionary<String, Object> mData = new .() ~ {
		for (let kv in _)
		{
			delete kv.key;
		}
		delete _;
	};

	/// Sets data of a specific format.
	public void SetData(StringView format, Object data)
	{
		let key = new String(format);
		if (mData.ContainsKey(key))
		{
			mData[key] = data;
			delete key;
		}
		else
		{
			mData[key] = data;
		}
	}

	/// Gets data of a specific format.
	public Object GetData(StringView format)
	{
		for (let kv in mData)
		{
			if (StringView(kv.key) == format)
				return kv.value;
		}
		return null;
	}

	/// Checks if data of a specific format is available.
	public bool HasData(StringView format)
	{
		for (let kv in mData)
		{
			if (StringView(kv.key) == format)
				return true;
		}
		return false;
	}

	/// Gets all available formats.
	public void GetFormats(List<StringView> outFormats)
	{
		for (let kv in mData)
		{
			outFormats.Add(kv.key);
		}
	}
}

/// Event arguments for drag events.
public class DragEventArgs
{
	/// The data being dragged.
	public DragData Data;

	/// Current mouse X position (logical coordinates).
	public float X;

	/// Current mouse Y position (logical coordinates).
	public float Y;

	/// Keyboard modifiers during the drag.
	public KeyModifiers Modifiers;

	/// The element being dragged from.
	public UIElement Source;

	/// The current drop target element.
	public UIElement Target;

	/// The allowed effects for this operation.
	public DragDropEffects AllowedEffects = .All;

	/// The effect that will be applied if dropped here.
	public DragDropEffects Effect = .None;

	/// Set to true to indicate the drop is handled.
	public bool Handled;
}

/// Interface for elements that can be drag sources.
public interface IDragSource
{
	/// Called when a drag operation starts.
	/// Return the data to drag, or null to cancel.
	DragData OnDragStart(float x, float y);

	/// Called to get the allowed effects for this drag.
	DragDropEffects GetAllowedEffects();

	/// Called when the drag operation completes.
	void OnDragComplete(DragDropEffects effect);

	/// Called when the drag operation is cancelled.
	void OnDragCancelled();
}

/// Interface for elements that can be drop targets.
public interface IDropTarget
{
	/// Called when a drag enters this element.
	/// Set args.Effect to indicate what effect is allowed.
	void OnDragEnter(DragEventArgs args);

	/// Called when a drag moves over this element.
	/// Set args.Effect to indicate what effect is allowed.
	void OnDragOver(DragEventArgs args);

	/// Called when a drag leaves this element.
	void OnDragLeave(DragEventArgs args);

	/// Called when a drop occurs on this element.
	/// Set args.Handled = true if the drop was accepted.
	void OnDrop(DragEventArgs args);
}

/// Manages drag and drop operations.
public class DragDropManager
{
	private UIContext mContext;
	private bool mIsDragging;
	private DragData mDragData ~ delete _;
	private DragEventArgs mDragArgs = new .() ~ delete _;
	private UIElement mDragSource;
	private UIElement mCurrentTarget;
	private DragDropEffects mAllowedEffects;
	private float mDragStartX;
	private float mDragStartY;
	private float mCurrentX;
	private float mCurrentY;

	// Visual feedback
	private String mDragText ~ delete _;
	private Color mDragVisualColor = Color(100, 150, 255, 200);

	/// Whether a drag operation is in progress.
	public bool IsDragging => mIsDragging;

	/// The current drag data.
	public DragData DragData => mDragData;

	/// The element being dragged from.
	public UIElement DragSource => mDragSource;

	/// The current drop target.
	public UIElement CurrentTarget => mCurrentTarget;

	public this(UIContext context)
	{
		mContext = context;
	}

	/// Starts a drag operation from the specified element.
	/// Call this from a mouse down handler when you want to initiate a drag.
	public bool StartDrag(UIElement source, DragData data, DragDropEffects allowedEffects, float x, float y)
	{
		if (mIsDragging || data == null)
			return false;

		mIsDragging = true;
		mDragData = data;
		mDragSource = source;
		mAllowedEffects = allowedEffects;
		mDragStartX = x;
		mDragStartY = y;
		mCurrentX = x;
		mCurrentY = y;
		mCurrentTarget = null;

		// Capture mouse to receive all events
		mContext.CaptureMouse(source);

		return true;
	}

	/// Starts a drag operation using the IDragSource interface.
	public bool StartDrag(UIElement sourceElement, float x, float y)
	{
		if (sourceElement == null)
			return false;

		if (let source = sourceElement as IDragSource)
		{
			let data = source.OnDragStart(x, y);
			if (data == null)
				return false;

			let allowedEffects = source.GetAllowedEffects();
			return StartDrag(sourceElement, data, allowedEffects, x, y);
		}

		return false;
	}

	/// Updates the drag operation (called during mouse move).
	public void UpdateDrag(float x, float y, KeyModifiers modifiers)
	{
		if (!mIsDragging)
			return;

		mCurrentX = x;
		mCurrentY = y;

		// Find drop target at current position
		let newTarget = FindDropTarget(x, y);

		// Handle target changes
		if (newTarget != mCurrentTarget)
		{
			// Leave old target
			if (mCurrentTarget != null)
			{
				if (let dropTarget = mCurrentTarget as IDropTarget)
				{
					SetupDragArgs(modifiers);
					dropTarget.OnDragLeave(mDragArgs);
				}
			}

			mCurrentTarget = newTarget;

			// Enter new target
			if (mCurrentTarget != null)
			{
				if (let dropTarget = mCurrentTarget as IDropTarget)
				{
					SetupDragArgs(modifiers);
					dropTarget.OnDragEnter(mDragArgs);
				}
			}
		}
		else if (mCurrentTarget != null)
		{
			// Still over same target - send drag over
			if (let dropTarget = mCurrentTarget as IDropTarget)
			{
				SetupDragArgs(modifiers);
				dropTarget.OnDragOver(mDragArgs);
			}
		}

		mContext.InvalidateVisual();
	}

	/// Ends the drag operation (called on mouse up).
	public void EndDrag(float x, float y, KeyModifiers modifiers)
	{
		if (!mIsDragging)
			return;

		var effect = DragDropEffects.None;

		// Try to drop on current target
		if (mCurrentTarget != null)
		{
			if (let dropTarget = mCurrentTarget as IDropTarget)
			{
				SetupDragArgs(modifiers);
				dropTarget.OnDrop(mDragArgs);

				if (mDragArgs.Handled)
					effect = mDragArgs.Effect;
			}
		}

		// Notify source of completion
		if (mDragSource != null)
		{
			if (let dragSource = mDragSource as IDragSource)
			{
				if (effect != .None)
					dragSource.OnDragComplete(effect);
				else
					dragSource.OnDragCancelled();
			}
		}

		// Cleanup
		EndDragInternal();
	}

	/// Cancels the current drag operation.
	public void CancelDrag()
	{
		if (!mIsDragging)
			return;

		// Notify source
		if (mDragSource != null)
		{
			if (let dragSource = mDragSource as IDragSource)
				dragSource.OnDragCancelled();
		}

		// Leave current target
		if (mCurrentTarget != null)
		{
			if (let dropTarget = mCurrentTarget as IDropTarget)
			{
				SetupDragArgs(.None);
				dropTarget.OnDragLeave(mDragArgs);
			}
		}

		EndDragInternal();
	}

	private void EndDragInternal()
	{
		mIsDragging = false;
		delete mDragData;
		mDragData = null;
		mDragSource = null;
		mCurrentTarget = null;
		mAllowedEffects = .None;

		mContext.ReleaseMouseCapture();
		mContext.InvalidateVisual();
	}

	private void SetupDragArgs(KeyModifiers modifiers)
	{
		mDragArgs.Data = mDragData;
		mDragArgs.X = mCurrentX;
		mDragArgs.Y = mCurrentY;
		mDragArgs.Modifiers = modifiers;
		mDragArgs.Source = mDragSource;
		mDragArgs.Target = mCurrentTarget;
		mDragArgs.AllowedEffects = mAllowedEffects;
		mDragArgs.Effect = .None;
		mDragArgs.Handled = false;
	}

	private UIElement FindDropTarget(float x, float y)
	{
		// Hit test to find element at position
		let element = mContext.HitTestLogical(x, y);

		// Walk up the tree to find a drop target
		var current = element;
		while (current != null)
		{
			if (current is IDropTarget)
				return current;
			current = current.Parent;
		}

		return null;
	}

	/// Renders the drag visual feedback.
	public void RenderDragVisual(DrawContext drawContext)
	{
		if (!mIsDragging)
			return;

		// Draw a simple drag indicator at cursor position
		let size = 24.0f;
		let x = mCurrentX - size / 2;
		let y = mCurrentY - size / 2;

		// Semi-transparent drag indicator
		let effectColor = mDragArgs.Effect != .None ? Color(100, 200, 100, 180) : Color(200, 100, 100, 180);
		drawContext.FillRect(.(x, y, size, size), effectColor);
		drawContext.DrawRect(.(x, y, size, size), Color(255, 255, 255, 200), 2.0f);

		// Draw effect icon
		let iconY = y + size / 2;
		let iconX = x + size / 2;

		switch (mDragArgs.Effect)
		{
		case .Copy:
			// Plus sign
			drawContext.FillRect(.(iconX - 5, iconY - 1, 10, 2), Color.White);
			drawContext.FillRect(.(iconX - 1, iconY - 5, 2, 10), Color.White);
		case .Move:
			// Arrow
			drawContext.FillRect(.(iconX - 4, iconY - 1, 8, 2), Color.White);
			drawContext.FillRect(.(iconX + 2, iconY - 3, 2, 6), Color.White);
		case .Link:
			// Chain link (simplified)
			drawContext.DrawRect(.(iconX - 5, iconY - 3, 6, 6), Color.White, 1.0f);
			drawContext.DrawRect(.(iconX - 1, iconY - 3, 6, 6), Color.White, 1.0f);
		default:
			// X for not allowed
			drawContext.FillRect(.(iconX - 4, iconY - 4, 8, 2), Color.White);
			drawContext.FillRect(.(iconX - 4, iconY + 2, 8, 2), Color.White);
		}
	}

	/// Sets custom text to display during drag.
	public void SetDragText(StringView text)
	{
		if (mDragText == null)
			mDragText = new String();
		mDragText.Set(text);
	}
}
