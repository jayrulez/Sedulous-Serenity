namespace Sedulous.UI;

using System;
using Sedulous.Core;

/// Delegate-based ICommand implementation.
/// Takes ownership of the execute and canExecute delegates.
public class RelayCommand : ICommand
{
	private delegate void() mExecute;
	private delegate bool() mCanExecute;
	private EventAccessor<delegate void()> mOnCanExecuteChanged = new .() ~ delete _;

	/// Create a command. Takes ownership of both delegates.
	/// canExecute may be null (command is always enabled).
	public this(delegate void() execute, delegate bool() canExecute = null)
	{
		mExecute = execute;
		mCanExecute = canExecute;
	}

	public ~this()
	{
		delete mExecute;
		if (mCanExecute != null)
			delete mCanExecute;
	}

	public void Execute()
	{
		mExecute();
	}

	public bool CanExecute()
	{
		return (mCanExecute != null) ? mCanExecute() : true;
	}

	public EventAccessor<delegate void()> OnCanExecuteChanged => mOnCanExecuteChanged;

	/// Call this when external state changes that may affect CanExecute.
	public void RaiseCanExecuteChanged()
	{
		mOnCanExecuteChanged.[Friend]Invoke();
	}
}
