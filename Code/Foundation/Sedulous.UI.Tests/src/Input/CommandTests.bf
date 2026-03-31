using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class CommandTests
{
	//==========================================================================
	// RelayCommand — Execute
	//==========================================================================

	[Test]
	public static void RelayCommand_Execute_CallsDelegate()
	{
		bool called = false;
		let cmd = scope RelayCommand(new [&] () => { called = true; });
		cmd.Execute();
		Test.Assert(called);
	}

	//==========================================================================
	// RelayCommand — CanExecute
	//==========================================================================

	[Test]
	public static void RelayCommand_CanExecute_DefaultTrue()
	{
		let cmd = scope RelayCommand(new () => { });
		Test.Assert(cmd.CanExecute() == true);
	}

	[Test]
	public static void RelayCommand_CanExecute_WithPredicate_ReturnsResult()
	{
		bool enabled = false;
		let cmd = scope RelayCommand(new () => { }, new [&] () => enabled);
		Test.Assert(cmd.CanExecute() == false);
		enabled = true;
		Test.Assert(cmd.CanExecute() == true);
	}

	//==========================================================================
	// RelayCommand — CanExecuteChanged event
	//==========================================================================

	[Test]
	public static void RelayCommand_RaiseCanExecuteChanged_FiresEvent()
	{
		bool eventFired = false;
		let cmd = scope RelayCommand(new () => { });
		delegate void() handler = new [&] () => { eventFired = true; };
		cmd.OnCanExecuteChanged.Subscribe(handler);

		cmd.RaiseCanExecuteChanged();
		Test.Assert(eventFired);

		cmd.OnCanExecuteChanged.Unsubscribe(handler);
	}

	//==========================================================================
	// Button + Command integration (unit-level, no context)
	//==========================================================================

	[Test]
	public static void Button_Command_DisablesWhenCanExecuteFalse()
	{
		bool enabled = true;
		let cmd = new RelayCommand(new () => { }, new [&] () => enabled);
		let button = scope Button("Test");
		button.Command = cmd;

		Test.Assert(button.Enabled == true);

		enabled = false;
		cmd.RaiseCanExecuteChanged();
		Test.Assert(button.Enabled == false);

		enabled = true;
		cmd.RaiseCanExecuteChanged();
		Test.Assert(button.Enabled == true);

		button.Command = null;
		delete cmd;
	}
}
