using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

class DialogTests
{
	[Test]
	public static void DialogDefaultProperties()
	{
		let dialog = scope Dialog();
		Test.Assert(dialog.Title == "");
		Test.Assert(dialog.DialogContent == null);
		Test.Assert(dialog.Buttons == .OK);
		Test.Assert(dialog.Result == .None);
	}

	[Test]
	public static void DialogTitle()
	{
		let dialog = scope Dialog();
		dialog.Title = "Test Dialog";
		Test.Assert(dialog.Title == "Test Dialog");
	}

	[Test]
	public static void DialogContent()
	{
		let dialog = scope Dialog();
		let content = new Border();
		dialog.DialogContent = content;

		Test.Assert(dialog.DialogContent == content);
		Test.Assert(content.Parent == dialog);
	}

	[Test]
	public static void DialogReplaceContent()
	{
		let dialog = scope Dialog();
		let content1 = new Border();
		let content2 = new Border();

		dialog.DialogContent = content1;
		Test.Assert(dialog.DialogContent == content1);

		dialog.DialogContent = content2;
		Test.Assert(dialog.DialogContent == content2);
		Test.Assert(content1.Parent == null);

		delete content1;
	}

	[Test]
	public static void DialogButtons()
	{
		let dialog = scope Dialog();

		dialog.Buttons = .OKCancel;
		Test.Assert(dialog.Buttons == .OKCancel);
		Test.Assert(dialog.Buttons.HasFlag(.OK));
		Test.Assert(dialog.Buttons.HasFlag(.Cancel));

		dialog.Buttons = .YesNo;
		Test.Assert(dialog.Buttons == .YesNo);
		Test.Assert(dialog.Buttons.HasFlag(.Yes));
		Test.Assert(dialog.Buttons.HasFlag(.No));

		dialog.Buttons = .YesNoCancel;
		Test.Assert(dialog.Buttons == .YesNoCancel);
		Test.Assert(dialog.Buttons.HasFlag(.Yes));
		Test.Assert(dialog.Buttons.HasFlag(.No));
		Test.Assert(dialog.Buttons.HasFlag(.Cancel));
	}

	[Test]
	public static void DialogCloseWithResult()
	{
		let dialog = scope Dialog();

		var eventFired = false;
		var resultReceived = DialogResult.None;

		delegate void (Dialog, DialogResult) handler = new [&](d,  r) =>
		{
			eventFired = true;
			resultReceived = r;
		};
		dialog.ClosedWithResult.Subscribe(handler);

		dialog.CloseWithResult(.OK);

		Test.Assert(dialog.Result == .OK);
		Test.Assert(eventFired);
		Test.Assert(resultReceived == .OK);
	}

	[Test]
	public static void DialogMeasure()
	{
		let dialog = scope Dialog();
		dialog.Title = "Test";
		dialog.Visibility = .Visible; // Popup defaults to Collapsed

		let content = new Border();
		content.Width = 150;
		content.Height = 80;
		dialog.DialogContent = content;

		dialog.Measure(SizeConstraints.FromMaximum(500, 400));

		// Dialog should measure to some reasonable size
		Test.Assert(dialog.DesiredSize.Width > 0);
		Test.Assert(dialog.DesiredSize.Height > 0);
	}

	[Test]
	public static void DialogModalBehavior()
	{
		let dialog = scope Dialog();
		Test.Assert(dialog.Behavior.HasFlag(.Modal));
		Test.Assert(dialog.IsModal);
	}

	[Test]
	public static void DialogEscapeBehavior()
	{
		let dialog = scope Dialog();
		Test.Assert(dialog.Behavior.HasFlag(.CloseOnEscape));
	}
}

class DialogResultTests
{
	[Test]
	public static void DialogResultValues()
	{
		Test.Assert(DialogResult.None != DialogResult.OK);
		Test.Assert(DialogResult.OK != DialogResult.Cancel);
		Test.Assert(DialogResult.Yes != DialogResult.No);
	}
}

class DialogButtonsTests
{
	[Test]
	public static void DialogButtonsFlags()
	{
		let okCancel = DialogButtons.OKCancel;
		Test.Assert(okCancel.HasFlag(.OK));
		Test.Assert(okCancel.HasFlag(.Cancel));
		Test.Assert(!okCancel.HasFlag(.Yes));
		Test.Assert(!okCancel.HasFlag(.No));

		let yesNo = DialogButtons.YesNo;
		Test.Assert(yesNo.HasFlag(.Yes));
		Test.Assert(yesNo.HasFlag(.No));
		Test.Assert(!yesNo.HasFlag(.OK));
		Test.Assert(!yesNo.HasFlag(.Cancel));

		let yesNoCancel = DialogButtons.YesNoCancel;
		Test.Assert(yesNoCancel.HasFlag(.Yes));
		Test.Assert(yesNoCancel.HasFlag(.No));
		Test.Assert(yesNoCancel.HasFlag(.Cancel));
	}

	[Test]
	public static void DialogButtonsCombinations()
	{
		let custom = DialogButtons.OK | DialogButtons.Yes;
		Test.Assert(custom.HasFlag(.OK));
		Test.Assert(custom.HasFlag(.Yes));
		Test.Assert(!custom.HasFlag(.Cancel));
		Test.Assert(!custom.HasFlag(.No));
	}
}

class MessageBoxTests
{
	[Test]
	public static void MessageBoxIconTypes()
	{
		// Just verify the enum values exist and are distinct
		Test.Assert(MessageBoxIcon.None != MessageBoxIcon.Information);
		Test.Assert(MessageBoxIcon.Information != MessageBoxIcon.Warning);
		Test.Assert(MessageBoxIcon.Warning != MessageBoxIcon.Error);
		Test.Assert(MessageBoxIcon.Error != MessageBoxIcon.Question);
	}
}
