using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

class TooltipTests
{
	[Test]
	public static void TooltipDefaultProperties()
	{
		let tooltip = scope Tooltip();
		Test.Assert(tooltip.Text == "");
		Test.Assert(tooltip.ShowDelay == 0.5f);
	}

	[Test]
	public static void TooltipText()
	{
		let tooltip = scope Tooltip();
		tooltip.Text = "This is a tooltip";
		Test.Assert(tooltip.Text == "This is a tooltip");
	}

	[Test]
	public static void TooltipShowDelay()
	{
		let tooltip = scope Tooltip();
		Test.Assert(tooltip.ShowDelay == 0.5f); // Default value

		tooltip.ShowDelay = 1.0f;
		Test.Assert(tooltip.ShowDelay == 1.0f);

		tooltip.ShowDelay = 0.0f;
		Test.Assert(tooltip.ShowDelay == 0.0f);
	}

	[Test]
	public static void TooltipMeasure()
	{
		let tooltip = scope Tooltip();
		tooltip.Text = "Test tooltip text";
		tooltip.Visibility = .Visible; // Popup defaults to Collapsed

		tooltip.Measure(SizeConstraints.FromMaximum(400, 200));

		Test.Assert(tooltip.DesiredSize.Width > 0);
		Test.Assert(tooltip.DesiredSize.Height > 0);
	}

	[Test]
	public static void TooltipInheritsFromPopup()
	{
		let tooltip = scope Tooltip();
		Test.Assert(tooltip is Popup);
	}
}

class TooltipServiceTests
{
	[Test]
	public static void TooltipServiceSetAndGet()
	{
		let service = scope TooltipService();
		let element = scope Border();

		service.SetTooltip(element, "Test tooltip");

		Test.Assert(service.HasTooltip(element));
		Test.Assert(service.GetTooltip(element) == "Test tooltip");
	}

	[Test]
	public static void TooltipServiceClearTooltip()
	{
		let service = scope TooltipService();
		let element = scope Border();

		service.SetTooltip(element, "Test tooltip");
		Test.Assert(service.HasTooltip(element));

		service.ClearTooltip(element);
		Test.Assert(!service.HasTooltip(element));
		Test.Assert(service.GetTooltip(element) == "");
	}

	[Test]
	public static void TooltipServiceUpdateTooltip()
	{
		let service = scope TooltipService();
		let element = scope Border();

		service.SetTooltip(element, "First tooltip");
		Test.Assert(service.GetTooltip(element) == "First tooltip");

		service.SetTooltip(element, "Updated tooltip");
		Test.Assert(service.GetTooltip(element) == "Updated tooltip");
	}

	[Test]
	public static void TooltipServiceEmptyTextRemovesTooltip()
	{
		let service = scope TooltipService();
		let element = scope Border();

		service.SetTooltip(element, "Test tooltip");
		Test.Assert(service.HasTooltip(element));

		service.SetTooltip(element, "");
		Test.Assert(!service.HasTooltip(element));
	}

	[Test]
	public static void TooltipServiceNullElement()
	{
		let service = scope TooltipService();

		// Should handle null gracefully
		service.SetTooltip(null, "Test");
		Test.Assert(!service.HasTooltip(null));
		Test.Assert(service.GetTooltip(null) == "");
	}

	[Test]
	public static void TooltipServiceMultipleElements()
	{
		let service = scope TooltipService();
		let element1 = scope Border();
		let element2 = scope Button();
		let element3 = scope TextBlock();

		service.SetTooltip(element1, "Tooltip 1");
		service.SetTooltip(element2, "Tooltip 2");
		service.SetTooltip(element3, "Tooltip 3");

		Test.Assert(service.GetTooltip(element1) == "Tooltip 1");
		Test.Assert(service.GetTooltip(element2) == "Tooltip 2");
		Test.Assert(service.GetTooltip(element3) == "Tooltip 3");
	}

	[Test]
	public static void TooltipServiceHide()
	{
		let service = scope TooltipService();
		// Hide should not throw even when nothing is showing
		service.Hide();
	}

	[Test]
	public static void TooltipServiceClearNonExistentTooltip()
	{
		let service = scope TooltipService();
		let element = scope Border();

		// Should not throw when clearing tooltip that doesn't exist
		service.ClearTooltip(element);
		Test.Assert(!service.HasTooltip(element));
	}

	[Test]
	public static void TooltipServiceImplementsInterface()
	{
		let service = scope TooltipService();
		Test.Assert(service is ITooltipService);
	}
}
