namespace Sedulous.UI.Tests;

using System;
using Sedulous.UI;

class SelectionModelTests
{
	[Test]
	static void DefaultIsSingleMode()
	{
		let model = scope SelectionModel();
		Test.Assert(model.Mode == .Single);
		Test.Assert(model.Count == 0);
		Test.Assert(model.SelectedPosition == -1);
	}

	[Test]
	static void SingleMode_SelectReplacesPrevious()
	{
		let model = scope SelectionModel();
		model.Select(3);
		Test.Assert(model.IsSelected(3));
		Test.Assert(model.Count == 1);

		model.Select(7);
		Test.Assert(!model.IsSelected(3));
		Test.Assert(model.IsSelected(7));
		Test.Assert(model.Count == 1);
		Test.Assert(model.SelectedPosition == 7);
	}

	[Test]
	static void MultipleMode_MultipleSelected()
	{
		let model = scope SelectionModel();
		model.Mode = .Multiple;

		model.Select(1);
		model.Select(3);
		model.Select(5);
		Test.Assert(model.Count == 3);
		Test.Assert(model.IsSelected(1));
		Test.Assert(model.IsSelected(3));
		Test.Assert(model.IsSelected(5));
		Test.Assert(!model.IsSelected(2));
	}

	[Test]
	static void NoneMode_SelectIgnored()
	{
		let model = scope SelectionModel();
		model.Mode = .None;

		model.Select(5);
		Test.Assert(model.Count == 0);
		Test.Assert(!model.IsSelected(5));
	}

	[Test]
	static void Toggle_SelectsAndDeselects()
	{
		let model = scope SelectionModel();
		model.Mode = .Multiple;

		model.Toggle(3);
		Test.Assert(model.IsSelected(3));

		model.Toggle(3);
		Test.Assert(!model.IsSelected(3));
		Test.Assert(model.Count == 0);
	}

	[Test]
	static void Clear_RemovesAll()
	{
		let model = scope SelectionModel();
		model.Mode = .Multiple;
		model.Select(1);
		model.Select(2);
		model.Select(3);

		model.Clear();
		Test.Assert(model.Count == 0);
		Test.Assert(!model.IsSelected(1));
	}

	[Test]
	static void OnSelectionChanged_Fires()
	{
		let model = scope SelectionModel();
		int fireCount = 0;
		model.OnSelectionChanged.Subscribe(new [&fireCount] (m) => { fireCount++; });

		model.Select(1);
		Test.Assert(fireCount == 1);

		model.Select(2); // replaces in single mode
		Test.Assert(fireCount == 2);

		model.Deselect(2);
		Test.Assert(fireCount == 3);

		model.Deselect(99); // not selected, should not fire
		Test.Assert(fireCount == 3);
	}

	[Test]
	static void ModeChange_ClearsSelection()
	{
		let model = scope SelectionModel();
		model.Select(5);
		Test.Assert(model.Count == 1);

		model.Mode = .Multiple;
		Test.Assert(model.Count == 0);
	}

	[Test]
	static void ShiftIndices_AdjustsPositions()
	{
		let model = scope SelectionModel();
		model.Mode = .Multiple;
		model.Select(2);
		model.Select(5);
		model.Select(8);

		// Insert 3 items at position 4 (shifts positions >= 4 by +3)
		model.ShiftIndices(4, 3);

		Test.Assert(model.IsSelected(2)); // before start, unchanged
		Test.Assert(model.IsSelected(8)); // 5 + 3
		Test.Assert(model.IsSelected(11)); // 8 + 3
		Test.Assert(!model.IsSelected(5)); // old position gone
	}

	[Test]
	static void SingleMode_SelectSameNoEvent()
	{
		let model = scope SelectionModel();
		model.Select(3);

		int fireCount = 0;
		model.OnSelectionChanged.Subscribe(new [&fireCount] (m) => { fireCount++; });

		model.Select(3); // already selected
		Test.Assert(fireCount == 0);
	}
}
