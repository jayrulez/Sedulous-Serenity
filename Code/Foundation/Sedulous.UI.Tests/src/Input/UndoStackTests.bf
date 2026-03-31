using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class UndoStackTests
{
	[Test]
	public static void UndoStack_InitiallyEmpty()
	{
		let stack = scope UndoStack();
		Test.Assert(!stack.CanUndo);
		Test.Assert(!stack.CanRedo);
		Test.Assert(stack.UndoCount == 0);
		Test.Assert(stack.RedoCount == 0);
	}

	[Test]
	public static void UndoStack_PushAndUndo()
	{
		let stack = scope UndoStack();
		stack.PushState("hello", 5, 5);

		Test.Assert(stack.CanUndo);
		Test.Assert(!stack.CanRedo);

		let restoredText = scope String();
		int32 cursor = 0, anchor = 0;
		let result = stack.Undo("world", 5, 5, restoredText, out cursor, out anchor);

		Test.Assert(result);
		Test.Assert(restoredText == "hello");
		Test.Assert(cursor == 5);
		Test.Assert(anchor == 5);
		Test.Assert(!stack.CanUndo);
		Test.Assert(stack.CanRedo);
	}

	[Test]
	public static void UndoStack_UndoAndRedo()
	{
		let stack = scope UndoStack();
		stack.PushState("", 0, 0); // initial empty state

		let restoredText = scope String();
		int32 cursor = 0, anchor = 0;

		// Undo back to empty
		Test.Assert(stack.Undo("abc", 3, 3, restoredText, out cursor, out anchor));
		Test.Assert(restoredText == "");

		// Redo back to "abc"
		restoredText.Clear();
		Test.Assert(stack.Redo("", 0, 0, restoredText, out cursor, out anchor));
		Test.Assert(restoredText == "abc");
	}

	[Test]
	public static void UndoStack_NewEditClearsRedo()
	{
		let stack = scope UndoStack();
		stack.PushState("", 0, 0);

		let buf = scope String();
		int32 c = 0, a = 0;
		stack.Undo("abc", 3, 3, buf, out c, out a);
		Test.Assert(stack.CanRedo);

		// New edit should clear redo
		stack.PushState("xyz", 3, 3);
		Test.Assert(!stack.CanRedo);
	}

	[Test]
	public static void UndoStack_UndoWhenEmpty_ReturnsFalse()
	{
		let stack = scope UndoStack();
		let buf = scope String();
		int32 c = 0, a = 0;
		Test.Assert(!stack.Undo("text", 4, 4, buf, out c, out a));
	}

	[Test]
	public static void UndoStack_RedoWhenEmpty_ReturnsFalse()
	{
		let stack = scope UndoStack();
		let buf = scope String();
		int32 c = 0, a = 0;
		Test.Assert(!stack.Redo("text", 4, 4, buf, out c, out a));
	}

	[Test]
	public static void UndoStack_MaxEntries_DropsOldest()
	{
		let stack = scope UndoStack();
		stack.MaxEntries = 3;

		stack.PushState("a", 1, 1);
		stack.PushState("ab", 2, 2);
		stack.PushState("abc", 3, 3);
		stack.PushState("abcd", 4, 4); // should drop "a"

		Test.Assert(stack.UndoCount == 3);

		let buf = scope String();
		int32 c = 0, a = 0;

		// Undo 3 times
		stack.Undo("abcde", 5, 5, buf, out c, out a);
		Test.Assert(buf == "abcd");

		buf.Clear();
		stack.Undo("abcd", 4, 4, buf, out c, out a);
		Test.Assert(buf == "abc");

		buf.Clear();
		stack.Undo("abc", 3, 3, buf, out c, out a);
		Test.Assert(buf == "ab"); // "a" was dropped

		// No more undo
		Test.Assert(!stack.CanUndo);
	}

	[Test]
	public static void UndoStack_Clear_EmptiesBothStacks()
	{
		let stack = scope UndoStack();
		stack.PushState("a", 1, 1);
		stack.PushState("ab", 2, 2);

		let buf = scope String();
		int32 c = 0, a = 0;
		stack.Undo("abc", 3, 3, buf, out c, out a);

		Test.Assert(stack.CanUndo);
		Test.Assert(stack.CanRedo);

		stack.Clear();
		Test.Assert(!stack.CanUndo);
		Test.Assert(!stack.CanRedo);
	}
}
