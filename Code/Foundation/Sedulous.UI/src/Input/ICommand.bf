namespace Sedulous.UI;

using Sedulous.Core;

/// Interface for an executable command with enabled-state tracking.
/// Decouples UI controls from action logic.
public interface ICommand
{
	/// Execute the command.
	void Execute();

	/// Whether the command can currently execute.
	bool CanExecute();

	/// Raised when the result of CanExecute may have changed.
	EventAccessor<delegate void()> OnCanExecuteChanged { get; }
}
