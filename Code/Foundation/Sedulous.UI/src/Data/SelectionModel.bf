namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Core;

/// Selection mode for data-driven views.
public enum SelectionMode
{
	None,
	Single,
	Multiple
}

/// Manages selection state for ListView/TreeView.
/// Decoupled from the view so it can be shared or replaced.
public class SelectionModel
{
	private SelectionMode mMode = .Single;
	private HashSet<int> mSelected = new .() ~ delete _;

	private EventAccessor<delegate void(SelectionModel)> mOnSelectionChanged
		= new .() ~ delete _;

	public SelectionMode Mode
	{
		get => mMode;
		set
		{
			if (mMode != value)
			{
				mMode = value;
				Clear();
			}
		}
	}

	/// Event fired whenever selection changes.
	public EventAccessor<delegate void(SelectionModel)> OnSelectionChanged
		=> mOnSelectionChanged;

	/// Number of selected items.
	public int Count => mSelected.Count;

	/// Whether the given position is selected.
	public bool IsSelected(int position) => mSelected.Contains(position);

	/// Select a position. In Single mode, clears previous selection.
	public void Select(int position)
	{
		if (mMode == .None) return;

		if (mMode == .Single)
		{
			if (mSelected.Count == 1 && mSelected.Contains(position))
				return;
			mSelected.Clear();
		}
		else if (mSelected.Contains(position))
			return;

		mSelected.Add(position);
		mOnSelectionChanged.[Friend]Invoke(this);
	}

	/// Deselect a position.
	public void Deselect(int position)
	{
		if (mSelected.Remove(position))
			mOnSelectionChanged.[Friend]Invoke(this);
	}

	/// Toggle selection at position.
	public void Toggle(int position)
	{
		if (IsSelected(position))
			Deselect(position);
		else
			Select(position);
	}

	/// Clear all selections.
	public void Clear()
	{
		if (mSelected.Count > 0)
		{
			mSelected.Clear();
			mOnSelectionChanged.[Friend]Invoke(this);
		}
	}

	/// Get the single selected position, or -1 if none.
	public int SelectedPosition
	{
		get
		{
			if (mSelected.Count == 0) return -1;
			for (let pos in mSelected)
				return pos;
			return -1;
		}
	}

	/// Get all selected positions as a set.
	public HashSet<int> SelectedPositions => mSelected;

	/// Adjust selection indices when items shift (e.g., tree expand/collapse).
	/// Positions >= startPos are shifted by delta.
	public void ShiftIndices(int startPos, int delta)
	{
		if (mSelected.Count == 0 || delta == 0) return;

		let shifted = scope List<int>();
		let toRemove = scope List<int>();

		for (let pos in mSelected)
		{
			if (pos >= startPos)
			{
				toRemove.Add(pos);
				let newPos = pos + delta;
				if (newPos >= 0)
					shifted.Add(newPos);
			}
		}

		for (let pos in toRemove)
			mSelected.Remove(pos);
		for (let pos in shifted)
			mSelected.Add(pos);
	}
}
