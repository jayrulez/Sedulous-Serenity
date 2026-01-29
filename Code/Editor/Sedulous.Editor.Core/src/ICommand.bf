namespace Sedulous.Editor.Core;

using System;

/// Interface for undoable commands.
interface ICommand : IDisposable
{
	/// Execute the command.
	void Execute();

	/// Undo the command.
	void Undo();

	/// Whether this command can be merged with the previous command.
	bool CanMergeWith(ICommand previous);

	/// Merge with previous command (for continuous operations like dragging).
	void MergeWith(ICommand previous);

	/// Get description for undo menu.
	void GetDescription(String outDesc);
}
