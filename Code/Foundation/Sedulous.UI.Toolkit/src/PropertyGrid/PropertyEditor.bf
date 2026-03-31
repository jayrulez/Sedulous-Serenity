namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Core;

/// Abstract base class for property editors used by PropertyGrid.
/// Subclass to create specific editors for different data types.
///
/// Supports transactional editing for undo/redo integration:
///   OnEditBegin   — fired once when an edit gesture starts (drag begins, text field focused)
///   OnValueChanged — fired each time the value changes during the edit
///   OnEditEnd     — fired once when the edit gesture completes (drag ends, Enter pressed)
///   OnEditCancelled — fired if the edit is cancelled (Escape pressed)
///
/// Consumers should create one undo entry per Begin→End transaction, not per value change.
public abstract class PropertyEditor
{
	private String mPropertyName ~ delete _;
	private String mCategory ~ delete _;
	private View mView;
	private bool mIsEditing;

	private EventAccessor<delegate void(PropertyEditor)> mOnValueChanged = new .() ~ delete _;
	private EventAccessor<delegate void(PropertyEditor)> mOnEditBegin = new .() ~ delete _;
	private EventAccessor<delegate void(PropertyEditor)> mOnEditEnd = new .() ~ delete _;
	private EventAccessor<delegate void(PropertyEditor)> mOnEditCancelled = new .() ~ delete _;

	public StringView PropertyName => mPropertyName;
	public StringView Category => mCategory;

	/// Whether an edit gesture is currently in progress.
	public bool IsEditing => mIsEditing;

	/// Fired each time the value changes (may fire multiple times per edit gesture).
	public EventAccessor<delegate void(PropertyEditor)> OnValueChanged => mOnValueChanged;

	/// Fired once when an edit gesture begins (drag start, text field focus, etc.).
	public EventAccessor<delegate void(PropertyEditor)> OnEditBegin => mOnEditBegin;

	/// Fired once when an edit gesture completes successfully.
	public EventAccessor<delegate void(PropertyEditor)> OnEditEnd => mOnEditEnd;

	/// Fired if an edit gesture is cancelled (Escape key, etc.).
	public EventAccessor<delegate void(PropertyEditor)> OnEditCancelled => mOnEditCancelled;

	/// The view created by this editor. Null until CreateView() is called.
	public View EditorView => mView;

	public this(StringView name, StringView category = "")
	{
		mPropertyName = new String(name);
		mCategory = new String(category);
	}

	/// Create the editor's view. Called by PropertyGrid.
	public View GetOrCreateView()
	{
		if (mView == null)
			mView = CreateEditorView();
		return mView;
	}

	/// Override to create the specific editor widget(s).
	protected abstract View CreateEditorView();

	/// Refresh the view to reflect the current value (e.g. after external change).
	public abstract void RefreshView();

	/// Get a display string for the current value.
	public virtual void GetDisplayValue(String outValue) { }

	/// Fire the value-changed event.
	protected void NotifyValueChanged()
	{
		mOnValueChanged.[Friend]Invoke(this);
	}

	/// Call when an edit gesture begins. Subclasses should call this at the start
	/// of a drag, when a text field gains focus, etc.
	protected void BeginEdit()
	{
		if (!mIsEditing)
		{
			mIsEditing = true;
			mOnEditBegin.[Friend]Invoke(this);
		}
	}

	/// Call when an edit gesture completes successfully. Subclasses should call this
	/// when a drag ends, Enter is pressed, text field loses focus, etc.
	protected void EndEdit()
	{
		if (mIsEditing)
		{
			mIsEditing = false;
			mOnEditEnd.[Friend]Invoke(this);
		}
	}

	/// Call when an edit gesture is cancelled. Subclasses should call this
	/// when Escape is pressed or the edit is otherwise abandoned.
	protected void CancelEdit()
	{
		if (mIsEditing)
		{
			mIsEditing = false;
			mOnEditCancelled.[Friend]Invoke(this);
		}
	}
}
