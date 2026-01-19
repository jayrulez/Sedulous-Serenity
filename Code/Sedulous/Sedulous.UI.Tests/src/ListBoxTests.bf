using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

class ListBoxTests
{
	/*[Test]
	public static void ListBoxDefaultProperties()
	{
		let listBox = scope ListBox();
		Test.Assert(listBox.Items != null);
		Test.Assert(listBox.Items.Count == 0);
		Test.Assert(listBox.SelectedIndex == -1);
		Test.Assert(listBox.SelectedItem == null);
		Test.Assert(listBox.SelectionMode == .Single);
		Test.Assert(listBox.ItemHeight == 24);
	}

	[Test]
	public static void ListBoxAddItem()
	{
		let listBox = scope ListBox();
		let item = listBox.AddItem("Item 1");

		Test.Assert(listBox.Items.Count == 1);
		Test.Assert(listBox.Items[0] == item);
		Test.Assert(item.Text == "Item 1");
	}

	[Test]
	public static void ListBoxAddMultipleItems()
	{
		let listBox = scope ListBox();
		listBox.AddItem("First");
		listBox.AddItem("Second");
		listBox.AddItem("Third");

		Test.Assert(listBox.Items.Count == 3);
		Test.Assert(listBox.Items[0].Text == "First");
		Test.Assert(listBox.Items[1].Text == "Second");
		Test.Assert(listBox.Items[2].Text == "Third");
	}

	[Test]
	public static void ListBoxRemoveItem()
	{
		let listBox = scope ListBox();
		listBox.AddItem("Item 1");
		let item2 = listBox.AddItem("Item 2");
		listBox.AddItem("Item 3");

		listBox.RemoveItem(item2);

		Test.Assert(listBox.Items.Count == 2);
		Test.Assert(listBox.Items[0].Text == "Item 1");
		Test.Assert(listBox.Items[1].Text == "Item 3");
	}

	[Test]
	public static void ListBoxClearItems()
	{
		let listBox = scope ListBox();
		listBox.AddItem("Item 1");
		listBox.AddItem("Item 2");
		listBox.SelectedIndex = 1;

		listBox.ClearItems();

		Test.Assert(listBox.Items.Count == 0);
		Test.Assert(listBox.SelectedIndex == -1);
	}

	[Test]
	public static void ListBoxSingleSelection()
	{
		let listBox = scope ListBox();
		listBox.SelectionMode = .Single;
		listBox.AddItem("Item 1");
		listBox.AddItem("Item 2");

		listBox.SelectedIndex = 0;
		Test.Assert(listBox.SelectedIndex == 0);
		Test.Assert(listBox.SelectedItem == listBox.Items[0]);

		listBox.SelectedIndex = 1;
		Test.Assert(listBox.SelectedIndex == 1);
		Test.Assert(listBox.SelectedItem == listBox.Items[1]);
		Test.Assert(!listBox.Items[0].IsSelected);
		Test.Assert(listBox.Items[1].IsSelected);
	}

	[Test]
	public static void ListBoxSelectionIndexClamping()
	{
		let listBox = scope ListBox();
		listBox.AddItem("Item 1");
		listBox.AddItem("Item 2");

		// Index out of range should be clamped
		listBox.SelectedIndex = 10;
		Test.Assert(listBox.SelectedIndex == -1 || listBox.SelectedIndex < listBox.Items.Count);

		listBox.SelectedIndex = -5;
		Test.Assert(listBox.SelectedIndex == -1);
	}

	[Test]
	public static void ListBoxItemHeight()
	{
		let listBox = scope ListBox();
		listBox.ItemHeight = 32;
		Test.Assert(listBox.ItemHeight == 32);

		// Should clamp to minimum (16)
		listBox.ItemHeight = 5;
		Test.Assert(listBox.ItemHeight >= 16);
	}

	[Test]
	public static void ListBoxSelectionCanChange()
	{
		let listBox = scope ListBox();
		listBox.AddItem("Item 1");
		listBox.AddItem("Item 2");

		Test.Assert(listBox.SelectedIndex == -1);
		listBox.SelectedIndex = 1;
		Test.Assert(listBox.SelectedIndex == 1);
		Test.Assert(listBox.Items[1].IsSelected);
	}

	[Test]
	public static void ListBoxMeasure()
	{
		let listBox = scope ListBox();
		listBox.AddItem("Item 1");
		listBox.AddItem("Item 2");
		listBox.AddItem("Item 3");
		listBox.ItemHeight = 24;

		listBox.Measure(SizeConstraints.FromMaximum(200, 300));

		Test.Assert(listBox.DesiredSize.Width > 0);
		Test.Assert(listBox.DesiredSize.Height > 0);
	}*/
}

class ListBoxItemTests
{
	/*[Test]
	public static void ListBoxItemDefaultProperties()
	{
		let item = scope ListBoxItem();
		Test.Assert(item.Text == "");
		Test.Assert(!item.IsSelected);
		Test.Assert(item.Tag == null);
	}

	[Test]
	public static void ListBoxItemWithText()
	{
		let item = scope ListBoxItem("Test Item");
		Test.Assert(item.Text == "Test Item");
	}

	[Test]
	public static void ListBoxItemSetText()
	{
		let item = scope ListBoxItem();
		item.Text = "Changed Text";
		Test.Assert(item.Text == "Changed Text");
	}

	[Test]
	public static void ListBoxItemSelection()
	{
		let item = scope ListBoxItem();
		Test.Assert(!item.IsSelected);

		item.IsSelected = true;
		Test.Assert(item.IsSelected);

		item.IsSelected = false;
		Test.Assert(!item.IsSelected);
	}

	[Test]
	public static void ListBoxItemTag()
	{
		let item = scope ListBoxItem();
		let tagObject = scope Object();
		item.Tag = tagObject;
		Test.Assert(item.Tag == tagObject);
	}*/
}
