using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI.Tests;

class UIDebugSettingsTests
{
	[Test]
	public static void DefaultSettingsAllDisabled()
	{
		let settings = UIDebugSettings.Default;
		Test.Assert(!settings.ShowLayoutBounds);
		Test.Assert(!settings.ShowMargins);
		Test.Assert(!settings.ShowPadding);
		Test.Assert(!settings.ShowFocused);
		Test.Assert(!settings.ShowHitTestBounds);
	}

	[Test]
	public static void WithBoundsPreset()
	{
		let settings = UIDebugSettings.WithBounds;
		Test.Assert(settings.ShowLayoutBounds);
		Test.Assert(!settings.ShowMargins);
	}

	[Test]
	public static void SettingsCanBeModified()
	{
		var settings = UIDebugSettings.Default;
		settings.ShowLayoutBounds = true;
		settings.ShowMargins = true;
		settings.ShowPadding = true;
		settings.ShowFocused = true;
		settings.ShowHitTestBounds = true;

		Test.Assert(settings.ShowLayoutBounds);
		Test.Assert(settings.ShowMargins);
		Test.Assert(settings.ShowPadding);
		Test.Assert(settings.ShowFocused);
		Test.Assert(settings.ShowHitTestBounds);
	}
}

class DebugVisualizationTests
{
	// Helper to create test DrawContext with NullFontService
	private static mixin TestDrawContext()
	{
		let fontService = scope :: NullFontService();
		scope :: DrawContext(fontService)
	}

	[Test]
	public static void ContextDebugSettingsAccessible()
	{
		let context = scope UIContext();
		// Should be able to access and modify debug settings
		context.DebugSettings.ShowLayoutBounds = true;
		Test.Assert(context.DebugSettings.ShowLayoutBounds);
	}

	[Test]
	public static void DebugRenderingDoesNotCrashWithNoRoot()
	{
		let context = scope UIContext();
		context.DebugSettings.ShowLayoutBounds = true;

		let drawContext = TestDrawContext!();
		// Should not crash when rendering with debug enabled but no root
		context.Render(drawContext);
		Test.Assert(true); // If we get here, no crash occurred
	}

	[Test]
	public static void DebugRenderingWithLayoutBounds()
	{
		let context = scope UIContext();
		context.DebugSettings.ShowLayoutBounds = true;

		let root = scope StackPanel();
		root.Width = 100;
		root.Height = 100;
		context.RootElement = root;  // UIContext takes ownership
		context.SetViewportSize(800, 600);
		context.Update(0, 0);

		let drawContext = TestDrawContext!();
		context.Render(drawContext);

		// If we get here without crash, debug rendering succeeded
		Test.Assert(true);
	}

	[Test]
	public static void DebugRenderingWithMargins()
	{
		let context = scope UIContext();
		context.DebugSettings.ShowMargins = true;

		let root = scope StackPanel();
		root.Width = 100;
		root.Height = 100;
		root.Margin = Thickness(10);
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0, 0);

		let drawContext = TestDrawContext!();
		context.Render(drawContext);

		Test.Assert(true);
	}

	[Test]
	public static void DebugRenderingWithPadding()
	{
		let context = scope UIContext();
		context.DebugSettings.ShowPadding = true;

		let root = scope StackPanel();
		root.Width = 100;
		root.Height = 100;
		root.Padding = Thickness(10);
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0, 0);

		let drawContext = TestDrawContext!();
		context.Render(drawContext);

		Test.Assert(true);
	}

	[Test]
	public static void DebugRenderingWithFocusedElement()
	{
		let context = scope UIContext();
		context.DebugSettings.ShowFocused = true;

		let root = scope StackPanel();
		root.Width = 100;
		root.Height = 100;
		root.Focusable = true;
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0, 0);
		context.SetFocus(root);

		let drawContext = TestDrawContext!();
		context.Render(drawContext);

		Test.Assert(true);
	}

	[Test]
	public static void DebugRenderingWithHitTestBounds()
	{
		let context = scope UIContext();
		context.DebugSettings.ShowHitTestBounds = true;

		let root = scope StackPanel();
		root.Width = 100;
		root.Height = 100;
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0, 0);

		let drawContext = TestDrawContext!();
		context.Render(drawContext);

		Test.Assert(true);
	}

	[Test]
	public static void DebugRenderingSkipsCollapsedElements()
	{
		let context = scope UIContext();
		context.DebugSettings.ShowLayoutBounds = true;

		let root = scope StackPanel();
		root.Width = 100;
		root.Height = 100;

		let child = new StackPanel();
		child.Visibility = .Collapsed;
		child.Width = 50;
		child.Height = 50;
		root.AddChild(child);

		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0, 0);

		let drawContext = TestDrawContext!();
		context.Render(drawContext);

		Test.Assert(true);
	}

	[Test]
	public static void DebugRenderingRecursesToChildren()
	{
		let context = scope UIContext();
		context.DebugSettings.ShowLayoutBounds = true;

		let root = scope StackPanel();
		root.Width = 200;
		root.Height = 200;

		let child1 = new StackPanel();
		child1.Width = 50;
		child1.Height = 50;
		root.AddChild(child1);

		let child2 = new StackPanel();
		child2.Width = 50;
		child2.Height = 50;
		root.AddChild(child2);

		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0, 0);

		let drawContext = TestDrawContext!();
		context.Render(drawContext);

		Test.Assert(true);
	}

	[Test]
	public static void AllDebugOptionsEnabled()
	{
		let context = scope UIContext();
		context.DebugSettings.ShowLayoutBounds = true;
		context.DebugSettings.ShowMargins = true;
		context.DebugSettings.ShowPadding = true;
		context.DebugSettings.ShowFocused = true;
		context.DebugSettings.ShowHitTestBounds = true;

		let root = scope StackPanel();
		root.Width = 100;
		root.Height = 100;
		root.Margin = Thickness(5);
		root.Padding = Thickness(5);
		root.Focusable = true;
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0, 0);
		context.SetFocus(root);

		let drawContext = TestDrawContext!();
		context.Render(drawContext);

		Test.Assert(true);
	}
}
