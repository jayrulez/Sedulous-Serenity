using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

class ComboBoxTests
{
	[Test]
	public static void ComboBoxDefaultProperties()
	{
		let comboBox = scope ComboBox();
		Test.Assert(comboBox.Items != null);
		Test.Assert(comboBox.Items.Count == 0);
		Test.Assert(comboBox.SelectedIndex == -1);
		Test.Assert(comboBox.SelectedItem == "");
		Test.Assert(!comboBox.IsDropDownOpen);
		Test.Assert(comboBox.MaxDropDownHeight == 200);
		Test.Assert(comboBox.PlaceholderText == "");
	}

	[Test]
	public static void ComboBoxAddItem()
	{
		let comboBox = scope ComboBox();
		comboBox.AddItem("Option 1");

		Test.Assert(comboBox.Items.Count == 1);
		Test.Assert(comboBox.Items[0] == "Option 1");
	}

	[Test]
	public static void ComboBoxAddMultipleItems()
	{
		let comboBox = scope ComboBox();
		comboBox.AddItem("Red");
		comboBox.AddItem("Green");
		comboBox.AddItem("Blue");

		Test.Assert(comboBox.Items.Count == 3);
		Test.Assert(comboBox.Items[0] == "Red");
		Test.Assert(comboBox.Items[1] == "Green");
		Test.Assert(comboBox.Items[2] == "Blue");
	}

	[Test]
	public static void ComboBoxRemoveItem()
	{
		let comboBox = scope ComboBox();
		comboBox.AddItem("Item 1");
		comboBox.AddItem("Item 2");
		comboBox.AddItem("Item 3");

		comboBox.RemoveItem(1);

		Test.Assert(comboBox.Items.Count == 2);
		Test.Assert(comboBox.Items[0] == "Item 1");
		Test.Assert(comboBox.Items[1] == "Item 3");
	}

	[Test]
	public static void ComboBoxClearItems()
	{
		let comboBox = scope ComboBox();
		comboBox.AddItem("Item 1");
		comboBox.AddItem("Item 2");
		comboBox.SelectedIndex = 1;

		comboBox.ClearItems();

		Test.Assert(comboBox.Items.Count == 0);
		Test.Assert(comboBox.SelectedIndex == -1);
	}

	[Test]
	public static void ComboBoxSelection()
	{
		let comboBox = scope ComboBox();
		comboBox.AddItem("Apple");
		comboBox.AddItem("Banana");
		comboBox.AddItem("Cherry");

		comboBox.SelectedIndex = 1;
		Test.Assert(comboBox.SelectedIndex == 1);
		Test.Assert(comboBox.SelectedItem == "Banana");

		comboBox.SelectedIndex = 0;
		Test.Assert(comboBox.SelectedIndex == 0);
		Test.Assert(comboBox.SelectedItem == "Apple");
	}

	[Test]
	public static void ComboBoxSelectionIndexClamping()
	{
		let comboBox = scope ComboBox();
		comboBox.AddItem("Item 1");
		comboBox.AddItem("Item 2");

		// Index out of range should reset to -1
		comboBox.SelectedIndex = 10;
		Test.Assert(comboBox.SelectedIndex == -1);

		comboBox.SelectedIndex = -5;
		Test.Assert(comboBox.SelectedIndex == -1);
	}

	[Test]
	public static void ComboBoxMaxDropDownHeight()
	{
		let comboBox = scope ComboBox();
		comboBox.MaxDropDownHeight = 300;
		Test.Assert(comboBox.MaxDropDownHeight == 300);

		// Should clamp to minimum
		comboBox.MaxDropDownHeight = 20;
		Test.Assert(comboBox.MaxDropDownHeight >= 50);
	}

	[Test]
	public static void ComboBoxPlaceholderText()
	{
		let comboBox = scope ComboBox();
		comboBox.PlaceholderText = "Select an option...";
		Test.Assert(comboBox.PlaceholderText == "Select an option...");
	}

	[Test]
	public static void ComboBoxSelectionChangedEvent()
	{
		let comboBox = scope ComboBox();
		comboBox.AddItem("Item 1");
		comboBox.AddItem("Item 2");

		var eventFired = false;
		var oldIndexVal = -999;
		var newIndexVal = -999;

		delegate void(ComboBox, int, int) handler = new [&](cb, oi, ni) =>
		{
			eventFired = true;
			oldIndexVal = oi;
			newIndexVal = ni;
		};
		comboBox.SelectionChanged.Subscribe(handler);

		comboBox.SelectedIndex = 1;

		Test.Assert(eventFired);
		Test.Assert(oldIndexVal == -1);
		Test.Assert(newIndexVal == 1);
	}

	[Test]
	public static void ComboBoxMeasure()
	{
		let comboBox = scope ComboBox();
		comboBox.AddItem("Option 1");
		comboBox.AddItem("Option 2");

		comboBox.Measure(SizeConstraints.FromMaximum(200, 100));

		Test.Assert(comboBox.DesiredSize.Width > 0);
		Test.Assert(comboBox.DesiredSize.Height > 0);
	}

	[Test]
	public static void ComboBoxSelectedItemWhenEmpty()
	{
		let comboBox = scope ComboBox();
		Test.Assert(comboBox.SelectedItem == "");
		Test.Assert(comboBox.SelectedIndex == -1);
	}

	[Test]
	public static void ComboBoxRemoveSelectedItem()
	{
		let comboBox = scope ComboBox();
		comboBox.AddItem("Item 1");
		comboBox.AddItem("Item 2");
		comboBox.AddItem("Item 3");
		comboBox.SelectedIndex = 2;

		// Remove last item which is selected
		comboBox.RemoveItem(2);

		// Selection should be adjusted
		Test.Assert(comboBox.SelectedIndex <= 1);
		Test.Assert(comboBox.Items.Count == 2);
	}
}
