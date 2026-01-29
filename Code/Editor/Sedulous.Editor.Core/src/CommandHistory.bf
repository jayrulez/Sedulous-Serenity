namespace Sedulous.Editor.Core;

using System;
using System.Collections;

/// Manages undo/redo command history.
class CommandHistory : IDisposable
{
	private List<ICommand> mUndoStack = new .() ~ DeleteContainerAndDisposeItems!(_);
	private List<ICommand> mRedoStack = new .() ~ DeleteContainerAndDisposeItems!(_);
	private int mMaxHistorySize = 100;

	// Compound command support
	private CompoundCommand mActiveCompound;
	private int mCompoundDepth = 0;

	/// Maximum number of commands to keep in history.
	public int MaxHistorySize
	{
		get => mMaxHistorySize;
		set => mMaxHistorySize = Math.Max(1, value);
	}

	/// Whether undo is available.
	public bool CanUndo => mUndoStack.Count > 0;

	/// Whether redo is available.
	public bool CanRedo => mRedoStack.Count > 0;

	/// Number of commands in undo stack.
	public int UndoCount => mUndoStack.Count;

	/// Number of commands in redo stack.
	public int RedoCount => mRedoStack.Count;

	/// Event fired when history changes.
	public Event<delegate void()> OnHistoryChanged ~ _.Dispose();

	public void Dispose()
	{
	}

	/// Execute a command and add to history.
	public void Execute(ICommand command)
	{
		if (command == null)
			return;

		// Execute the command
		command.Execute();

		// If we're in a compound command, add to it
		if (mActiveCompound != null)
		{
			mActiveCompound.AddCommand(command);
			return;
		}

		// Try to merge with previous command
		if (mUndoStack.Count > 0)
		{
			let previous = mUndoStack.Back;
			if (command.CanMergeWith(previous))
			{
				command.MergeWith(previous);
				mUndoStack.PopBack();
				delete previous;
			}
		}

		// Add to undo stack
		mUndoStack.Add(command);

		// Clear redo stack (new action invalidates redo history)
		ClearRedoStack();

		// Trim history if too large
		TrimHistory();

		OnHistoryChanged.Invoke();
	}

	/// Undo last command.
	public void Undo()
	{
		if (!CanUndo)
			return;

		let command = mUndoStack.PopBack();
		command.Undo();
		mRedoStack.Add(command);

		OnHistoryChanged.Invoke();
	}

	/// Redo last undone command.
	public void Redo()
	{
		if (!CanRedo)
			return;

		let command = mRedoStack.PopBack();
		command.Execute();
		mUndoStack.Add(command);

		OnHistoryChanged.Invoke();
	}

	/// Clear all history.
	public void Clear()
	{
		ClearUndoStack();
		ClearRedoStack();
		OnHistoryChanged.Invoke();
	}

	/// Begin a compound command (multiple operations as one undo).
	public void BeginCompound(StringView description)
	{
		if (mCompoundDepth == 0)
		{
			mActiveCompound = new CompoundCommand(description);
		}
		mCompoundDepth++;
	}

	/// End compound command.
	public void EndCompound()
	{
		if (mCompoundDepth == 0)
			return;

		mCompoundDepth--;

		if (mCompoundDepth == 0 && mActiveCompound != null)
		{
			if (mActiveCompound.HasCommands)
			{
				mUndoStack.Add(mActiveCompound);
				ClearRedoStack();
				TrimHistory();
				OnHistoryChanged.Invoke();
			}
			else
			{
				delete mActiveCompound;
			}
			mActiveCompound = null;
		}
	}

	/// Get description of the command that would be undone.
	public void GetUndoDescription(String outDesc)
	{
		if (CanUndo)
			mUndoStack.Back.GetDescription(outDesc);
	}

	/// Get description of the command that would be redone.
	public void GetRedoDescription(String outDesc)
	{
		if (CanRedo)
			mRedoStack.Back.GetDescription(outDesc);
	}

	private void ClearUndoStack()
	{
		for (let cmd in mUndoStack)
			delete cmd;
		mUndoStack.Clear();
	}

	private void ClearRedoStack()
	{
		for (let cmd in mRedoStack)
			delete cmd;
		mRedoStack.Clear();
	}

	private void TrimHistory()
	{
		while (mUndoStack.Count > mMaxHistorySize)
		{
			let cmd = mUndoStack[0];
			mUndoStack.RemoveAt(0);
			delete cmd;
		}
	}
}

/// A compound command that groups multiple commands into one undoable action.
class CompoundCommand : ICommand
{
	private String mDescription = new .() ~ delete _;
	private List<ICommand> mCommands = new .() ~ DeleteContainerAndDisposeItems!(_);

	public bool HasCommands => mCommands.Count > 0;

	public this(StringView description)
	{
		mDescription.Set(description);
	}

	public void Dispose()
	{
	}

	public void AddCommand(ICommand command)
	{
		mCommands.Add(command);
	}

	public void Execute()
	{
		// Commands were already executed when added
		// This is called on redo
		for (let cmd in mCommands)
			cmd.Execute();
	}

	public void Undo()
	{
		// Undo in reverse order
		for (int i = mCommands.Count - 1; i >= 0; i--)
			mCommands[i].Undo();
	}

	public bool CanMergeWith(ICommand previous)
	{
		return false;
	}

	public void MergeWith(ICommand previous)
	{
		// Compound commands don't merge
	}

	public void GetDescription(String outDesc)
	{
		outDesc.Set(mDescription);
	}
}
