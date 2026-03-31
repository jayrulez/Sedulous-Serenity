using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

/// Mock clipboard for testing.
class MockClipboard : IClipboard
{
	private String mText = new .() ~ delete _;

	public bool HasText => !mText.IsEmpty;

	public Result<void> GetText(String outText)
	{
		if (mText.IsEmpty)
			return .Err;
		outText.Set(mText);
		return .Ok;
	}

	public Result<void> SetText(StringView text)
	{
		mText.Set(text);
		return .Ok;
	}
}

/// Mock text edit host with monospace 10px-per-char glyph positions.
class MockTextEditHost : ITextEditHost
{
	public String Text = new .() ~ delete _;
	public int32 MaxLength = 0;
	public bool IsReadOnly = false;
	public bool IsMultiline = false;
	public float CurrentTime = 0;
	public IClipboard Clipboard;
	public int32 ModifiedCount = 0;

	StringView ITextEditHost.Text => Text;
	int32 ITextEditHost.MaxLength => MaxLength;
	bool ITextEditHost.IsReadOnly => IsReadOnly;
	bool ITextEditHost.IsMultiline => IsMultiline;
	IClipboard ITextEditHost.Clipboard => Clipboard;
	float ITextEditHost.CurrentTime => CurrentTime;

	int32 ITextEditHost.TextCharCount
	{
		get
		{
			int32 count = 0;
			for (let c in Text.DecodedChars)
				count++;
			return count;
		}
	}

	void ITextEditHost.ReplaceText(int32 charStart, int32 charLength, StringView replacement)
	{
		// Convert char indices to byte offsets
		int32 byteStart = CharToByteOffset(charStart);
		int32 byteEnd = CharToByteOffset(charStart + charLength);
		Text.Remove(byteStart, byteEnd - byteStart);
		Text.Insert(byteStart, replacement);
	}

	void ITextEditHost.OnTextModified()
	{
		ModifiedCount++;
	}

	int32 ITextEditHost.HitTestPosition(float localX, float localY)
	{
		// Simple monospace: each char is 10px wide
		let charIndex = (int32)(localX / 10.0f);
		int32 charCount = 0;
		for (let c in Text.DecodedChars)
			charCount++;
		return Math.Clamp(charIndex, 0, charCount);
	}

	float ITextEditHost.GetCursorXPosition(int32 charIndex)
	{
		return charIndex * 10.0f;
	}

	private int32 CharToByteOffset(int32 charIndex)
	{
		int32 count = 0;
		int32 byteOffset = 0;
		for (let c in Text.DecodedChars)
		{
			if (count >= charIndex)
				break;
			count++;
			byteOffset = (int32)@c.NextIndex;
		}
		if (count < charIndex)
			return (int32)Text.Length;
		return byteOffset;
	}
}

class TextEditingBehaviorTests
{
	[Test]
	public static void Insert_Characters()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');

		Test.Assert(host.Text == "abc");
		Test.Assert(behavior.CursorPosition == 3);
	}

	[Test]
	public static void Insert_RespectsMaxLength()
	{
		let host = scope MockTextEditHost();
		host.MaxLength = 3;
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');
		behavior.HandleTextInput('d'); // should be rejected

		Test.Assert(host.Text == "abc");
		Test.Assert(behavior.CursorPosition == 3);
	}

	[Test]
	public static void Backspace_DeletesCharBehindCursor()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');
		behavior.HandleKeyDown(.Backspace, .None);

		Test.Assert(host.Text == "ab");
		Test.Assert(behavior.CursorPosition == 2);
	}

	[Test]
	public static void Backspace_AtStart_DoesNothing()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleKeyDown(.Backspace, .None);
		Test.Assert(host.Text.IsEmpty);
	}

	[Test]
	public static void Delete_DeletesCharAfterCursor()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');

		// Move cursor to position 1
		behavior.HandleKeyDown(.Home, .None);
		behavior.HandleKeyDown(.Right, .None);
		behavior.HandleKeyDown(.Delete, .None);

		Test.Assert(host.Text == "ac");
		Test.Assert(behavior.CursorPosition == 1);
	}

	[Test]
	public static void Delete_AtEnd_DoesNothing()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleKeyDown(.Delete, .None);

		Test.Assert(host.Text == "a");
	}

	[Test]
	public static void ArrowKeys_MoveCursor()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');
		Test.Assert(behavior.CursorPosition == 3);

		behavior.HandleKeyDown(.Left, .None);
		Test.Assert(behavior.CursorPosition == 2);

		behavior.HandleKeyDown(.Left, .None);
		Test.Assert(behavior.CursorPosition == 1);

		behavior.HandleKeyDown(.Right, .None);
		Test.Assert(behavior.CursorPosition == 2);
	}

	[Test]
	public static void HomeEnd_JumpToEnds()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');

		behavior.HandleKeyDown(.Home, .None);
		Test.Assert(behavior.CursorPosition == 0);

		behavior.HandleKeyDown(.End, .None);
		Test.Assert(behavior.CursorPosition == 3);
	}

	[Test]
	public static void ShiftArrow_CreatesSelection()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');

		// Shift+Left twice to select "bc"
		behavior.HandleKeyDown(.Left, .Shift);
		behavior.HandleKeyDown(.Left, .Shift);

		Test.Assert(behavior.IsSelecting);
		Test.Assert(behavior.SelectionStart == 1);
		Test.Assert(behavior.SelectionEnd == 3);
	}

	[Test]
	public static void CtrlA_SelectsAll()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('h');
		behavior.HandleTextInput('i');

		behavior.HandleKeyDown(.A, .Ctrl);

		Test.Assert(behavior.SelectionStart == 0);
		Test.Assert(behavior.SelectionEnd == 2);
	}

	[Test]
	public static void DeleteSelection_RemovesSelectedText()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');
		behavior.HandleTextInput('d');

		// Select "bc" — go to end, then shift-left twice, then shift-left once more to get b too
		behavior.HandleKeyDown(.Home, .None);
		behavior.HandleKeyDown(.Right, .None); // at 1
		behavior.HandleKeyDown(.Right, .Shift); // select 1-2
		behavior.HandleKeyDown(.Right, .Shift); // select 1-3

		behavior.HandleKeyDown(.Backspace, .None);

		Test.Assert(host.Text == "ad");
		Test.Assert(behavior.CursorPosition == 1);
	}

	[Test]
	public static void CtrlWordLeft_JumpsToWordBoundary()
	{
		let host = scope MockTextEditHost();
		host.Text.Set("hello world");
		let behavior = scope TextEditingBehavior(host);
		behavior.CursorPosition = 8;
		behavior.AnchorPosition = 8;

		behavior.HandleKeyDown(.Left, .Ctrl);
		Test.Assert(behavior.CursorPosition == 6); // start of "world"
	}

	[Test]
	public static void CtrlWordRight_JumpsToWordBoundary()
	{
		let host = scope MockTextEditHost();
		host.Text.Set("hello world");
		let behavior = scope TextEditingBehavior(host);
		behavior.CursorPosition = 2;
		behavior.AnchorPosition = 2;

		behavior.HandleKeyDown(.Right, .Ctrl);
		Test.Assert(behavior.CursorPosition == 6); // after "hello " at start of "world"
	}

	[Test]
	public static void ReadOnly_BlocksTextInput()
	{
		let host = scope MockTextEditHost();
		host.IsReadOnly = true;
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		Test.Assert(host.Text.IsEmpty);
	}

	[Test]
	public static void ReadOnly_AllowsNavigation()
	{
		let host = scope MockTextEditHost();
		host.Text.Set("hello");
		host.IsReadOnly = true;
		let behavior = scope TextEditingBehavior(host);
		behavior.CursorPosition = 5;
		behavior.AnchorPosition = 5;

		behavior.HandleKeyDown(.Left, .None);
		Test.Assert(behavior.CursorPosition == 4);
	}

	[Test]
	public static void InputFilter_RejectsFilteredChars()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);
		behavior.Filter = InputFilter.Digits();

		behavior.HandleTextInput('a'); // rejected
		behavior.HandleTextInput('5'); // accepted
		behavior.HandleTextInput('x'); // rejected

		Test.Assert(host.Text == "5");
	}

	[Test]
	public static void Clipboard_CopyPaste()
	{
		let clipboard = scope MockClipboard();
		let host = scope MockTextEditHost();
		host.Clipboard = clipboard;
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('h');
		behavior.HandleTextInput('i');

		// Select all, copy
		behavior.HandleKeyDown(.A, .Ctrl);
		behavior.HandleKeyDown(.C, .Ctrl);

		// Move to end
		behavior.HandleKeyDown(.End, .None);

		// Paste
		behavior.HandleKeyDown(.V, .Ctrl);

		Test.Assert(host.Text == "hihi");
	}

	[Test]
	public static void Clipboard_Cut()
	{
		let clipboard = scope MockClipboard();
		let host = scope MockTextEditHost();
		host.Clipboard = clipboard;
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');

		// Select all, cut
		behavior.HandleKeyDown(.A, .Ctrl);
		behavior.HandleKeyDown(.X, .Ctrl);

		Test.Assert(host.Text.IsEmpty);
		Test.Assert(clipboard.HasText);

		let clipText = scope String();
		clipboard.GetText(clipText);
		Test.Assert(clipText == "abc");
	}

	[Test]
	public static void Undo_RestoresPreviousState()
	{
		let host = scope MockTextEditHost();
		host.CurrentTime = 0;
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');

		// Change time to trigger new undo group
		host.CurrentTime = 2.0f;
		behavior.HandleTextInput('d');

		// Undo should remove 'd'
		behavior.HandleKeyDown(.Z, .Ctrl);

		Test.Assert(host.Text == "abc");
	}

	[Test]
	public static void Redo_RestoresUndoneState()
	{
		let host = scope MockTextEditHost();
		host.CurrentTime = 0;
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');

		host.CurrentTime = 2.0f;
		behavior.HandleTextInput('b');

		// Undo 'b'
		behavior.HandleKeyDown(.Z, .Ctrl);
		Test.Assert(host.Text == "a");

		// Redo 'b'
		behavior.HandleKeyDown(.Y, .Ctrl);
		Test.Assert(host.Text == "ab");
	}

	[Test]
	public static void DoubleClick_SelectsWord()
	{
		let host = scope MockTextEditHost();
		host.Text.Set("hello world");
		let behavior = scope TextEditingBehavior(host);

		// Double-click at x=25 (char index 2, inside "hello")
		behavior.HandleMouseDown(25, 5, 2, .None);

		Test.Assert(behavior.SelectionStart == 0);
		Test.Assert(behavior.SelectionEnd == 5); // "hello"
	}

	[Test]
	public static void TripleClick_SelectsAll()
	{
		let host = scope MockTextEditHost();
		host.Text.Set("hello world");
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleMouseDown(25, 5, 3, .None);

		Test.Assert(behavior.SelectionStart == 0);
		Test.Assert(behavior.SelectionEnd == 11);
	}

	[Test]
	public static void MouseClick_SetsCursor()
	{
		let host = scope MockTextEditHost();
		host.Text.Set("hello");
		let behavior = scope TextEditingBehavior(host);

		// Click at x=30 → char 3
		behavior.HandleMouseDown(30, 5, 1, .None);

		Test.Assert(behavior.CursorPosition == 3);
		Test.Assert(!behavior.IsSelecting);
	}

	[Test]
	public static void MouseDrag_ExtendsSelection()
	{
		let host = scope MockTextEditHost();
		host.Text.Set("hello");
		let behavior = scope TextEditingBehavior(host);

		// Click at position 1
		behavior.HandleMouseDown(10, 5, 1, .None);
		Test.Assert(behavior.CursorPosition == 1);

		// Drag to position 4
		behavior.HandleMouseMove(40, 5);
		Test.Assert(behavior.CursorPosition == 4);
		Test.Assert(behavior.IsSelecting);
		Test.Assert(behavior.SelectionStart == 1);
		Test.Assert(behavior.SelectionEnd == 4);
	}

	[Test]
	public static void LeftArrow_CollapsesSelectionToLeft()
	{
		let host = scope MockTextEditHost();
		host.Text.Set("hello");
		let behavior = scope TextEditingBehavior(host);

		// Select "ell" (positions 1-4)
		behavior.HandleMouseDown(10, 5, 1, .None);
		behavior.HandleMouseMove(40, 5);
		Test.Assert(behavior.IsSelecting);

		// Left arrow without shift collapses to left edge
		behavior.HandleKeyDown(.Left, .None);
		Test.Assert(!behavior.IsSelecting);
		Test.Assert(behavior.CursorPosition == 1);
	}

	[Test]
	public static void RightArrow_CollapsesSelectionToRight()
	{
		let host = scope MockTextEditHost();
		host.Text.Set("hello");
		let behavior = scope TextEditingBehavior(host);

		// Select "ell" (positions 1-4)
		behavior.HandleMouseDown(10, 5, 1, .None);
		behavior.HandleMouseMove(40, 5);

		// Right arrow without shift collapses to right edge
		behavior.HandleKeyDown(.Right, .None);
		Test.Assert(!behavior.IsSelecting);
		Test.Assert(behavior.CursorPosition == 4);
	}

	[Test]
	public static void TypeOverSelection_ReplacesText()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		behavior.HandleTextInput('c');

		// Select all
		behavior.HandleKeyDown(.A, .Ctrl);

		// Type replacement
		behavior.HandleTextInput('x');

		Test.Assert(host.Text == "x");
		Test.Assert(behavior.CursorPosition == 1);
	}

	[Test]
	public static void Reset_ClearsCursorAndUndo()
	{
		let host = scope MockTextEditHost();
		let behavior = scope TextEditingBehavior(host);

		behavior.HandleTextInput('a');
		behavior.HandleTextInput('b');
		Test.Assert(behavior.CursorPosition == 2);

		behavior.Reset();
		Test.Assert(behavior.CursorPosition == 0);
		Test.Assert(!behavior.UndoStack.CanUndo);
	}
}
