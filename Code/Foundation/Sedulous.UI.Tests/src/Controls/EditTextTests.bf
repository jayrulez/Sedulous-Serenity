using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class EditTextTests
{
	[Test]
	public static void EditText_IsFocusable()
	{
		let edit = scope EditText();
		Test.Assert(edit.Focusable);
	}

	[Test]
	public static void EditText_HasTextCursor()
	{
		let edit = scope EditText();
		Test.Assert(edit.CursorType == .Text);
	}

	[Test]
	public static void EditText_SetText_UpdatesText()
	{
		let edit = scope EditText();
		edit.Text = "hello";
		Test.Assert(edit.Text == "hello");
	}

	[Test]
	public static void EditText_SetText_ResetsCursor()
	{
		let edit = scope EditText();
		edit.Text = "hello";
		Test.Assert(edit.CursorPosition == 0);
	}

	[Test]
	public static void EditText_HintText_Property()
	{
		let edit = scope EditText("Type here...");
		Test.Assert(edit.HintText == "Type here...");

		edit.HintText = "Enter name";
		Test.Assert(edit.HintText == "Enter name");
	}

	[Test]
	public static void EditText_FontSize_Property()
	{
		let edit = scope EditText();
		Test.Assert(edit.FontSize == 16); // default

		edit.FontSize = 24;
		Test.Assert(edit.FontSize == 24);

		// Minimum of 1
		edit.FontSize = 0;
		Test.Assert(edit.FontSize == 1);
	}

	[Test]
	public static void EditText_ReadOnly_Property()
	{
		let edit = scope EditText();
		Test.Assert(!edit.ReadOnly);

		edit.ReadOnly = true;
		Test.Assert(edit.ReadOnly);
	}

	[Test]
	public static void EditText_MaxLength_Property()
	{
		let edit = scope EditText();
		Test.Assert(edit.MaxLength == 0);

		edit.MaxLength = 10;
		Test.Assert(edit.MaxLength == 10);
	}

	[Test]
	public static void EditText_Multiline_Property()
	{
		let edit = scope EditText();
		Test.Assert(!edit.Multiline);

		edit.Multiline = true;
		Test.Assert(edit.Multiline);
	}

	[Test]
	public static void EditText_DefaultPadding()
	{
		let edit = scope EditText();
		Test.Assert(edit.Padding.Left == 8);
		Test.Assert(edit.Padding.Top == 6);
		Test.Assert(edit.Padding.Right == 8);
		Test.Assert(edit.Padding.Bottom == 6);
	}

	[Test]
	public static void PasswordBox_MasksText()
	{
		let pw = scope PasswordBox();
		pw.Text = "secret";

		let display = scope String();
		pw.[Friend]GetDisplayText(display);

		// Should be 6 mask characters
		int32 charCount = 0;
		for (let c in display.DecodedChars)
			charCount++;
		Test.Assert(charCount == 6);

		// None should be the actual text
		Test.Assert(display != "secret");
	}

	[Test]
	public static void PasswordBox_CustomMaskChar()
	{
		let pw = scope PasswordBox();
		pw.MaskChar = '*';
		pw.Text = "abc";

		let display = scope String();
		pw.[Friend]GetDisplayText(display);
		Test.Assert(display == "***");
	}

	[Test]
	public static void PasswordBox_ActualTextPreserved()
	{
		let pw = scope PasswordBox();
		pw.Text = "mypassword";
		Test.Assert(pw.Text == "mypassword");
	}

	[Test]
	public static void PasswordBox_DefaultMaskIsAsterisk()
	{
		let pw = scope PasswordBox();
		Test.Assert(pw.MaskChar == '*');
		pw.Text = "ab";
		let display = scope String();
		pw.[Friend]GetDisplayText(display);
		Test.Assert(display == "**");
	}

	[Test]
	public static void PasswordBox_CopyDisabledByDefault()
	{
		let pw = scope PasswordBox();
		Test.Assert(!pw.[Friend]mBehavior.AllowClipboardCopy);
	}
}
