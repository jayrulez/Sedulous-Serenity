using System;
using Sedulous.UI;
using Sedulous.UI.Toolkit;

namespace Sedulous.UI.Tests;

class MenuBarTests
{
	[Test]
	public static void AddMenu_IncreasesMenuCount()
	{
		let bar = scope MenuBar();
		Test.Assert(bar.MenuCount == 0);
		bar.AddMenu("File");
		Test.Assert(bar.MenuCount == 1);
		bar.AddMenu("Edit");
		Test.Assert(bar.MenuCount == 2);
	}

	[Test]
	public static void AddMenu_ReturnsContextMenu()
	{
		let bar = scope MenuBar();
		let menu = bar.AddMenu("View");
		Test.Assert(menu != null);
	}

	[Test]
	public static void AddMenu_AddsChildView()
	{
		let bar = scope MenuBar();
		Test.Assert(bar.ChildCount == 0);
		bar.AddMenu("File");
		Test.Assert(bar.ChildCount == 1);
		bar.AddMenu("Edit");
		Test.Assert(bar.ChildCount == 2);
	}

	[Test]
	public static void AddMenu_CanPopulateReturnedMenu()
	{
		let bar = scope MenuBar();
		let fileMenu = bar.AddMenu("File");
		fileMenu.AddItem("New", new () => { });
		fileMenu.AddItem("Open", new () => { });
		fileMenu.AddSeparator();
		fileMenu.AddItem("Exit", new () => { });
		Test.Assert(fileMenu.ItemCount == 4);
	}

	[Test]
	public static void Measure_HasMinimumHeight()
	{
		let bar = scope MenuBar();
		bar.AddMenu("File");
		bar.Measure(.MakeAtMost(400), .MakeAtMost(400));
		Test.Assert(bar.MeasuredHeight >= 28);
	}

	[Test]
	public static void DefaultOrientation_IsHorizontal()
	{
		let bar = scope MenuBar();
		Test.Assert(bar.Orientation == .Horizontal);
	}
}
