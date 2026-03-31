using System;
using Sedulous.UI;
using Sedulous.Fonts;

namespace Sedulous.UI.Tests;

class LabelTests
{
	private static RootView SetupContext(UIContext ctx, View root, float w, float h)
	{
		return TestHelper.SetupContext(ctx, root, w, h);
	}

	[Test]
	public static void Label_DefaultTextIsEmpty()
	{
		let label = scope Label();
		Test.Assert(label.Text.IsEmpty);
	}

	[Test]
	public static void Label_SetText_StoresValue()
	{
		let label = scope Label();
		label.Text = "Hello";
		Test.Assert(label.Text == "Hello");
	}

	[Test]
	public static void Label_ConstructorWithText()
	{
		let label = scope Label("World");
		Test.Assert(label.Text == "World");
	}

	[Test]
	public static void Label_DefaultFontSize()
	{
		let label = scope Label();
		Test.Assert(label.FontSize == 16);
	}

	[Test]
	public static void Label_SetFontSize_ClampsToMin()
	{
		let label = scope Label();
		label.FontSize = -5;
		Test.Assert(label.FontSize >= 1);
	}

	[Test]
	public static void Label_DefaultAlignment()
	{
		let label = scope Label();
		Test.Assert(label.TextAlignment == .Left);
		Test.Assert(label.VerticalAlignment == .Top);
	}

	[Test]
	public static void Label_EmptyText_NoFontService_MeasuresToPadding()
	{
		let ctx = scope UIContext(); // no font service
		let root = new FrameLayout();
		let label = new Label();
		label.Padding = .(5, 10, 5, 10);
		root.AddView(label, new LayoutParams(LayoutParams.WrapContent, LayoutParams.WrapContent));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		// No text and no font service — should just be padding
		Test.Assert(label.MeasuredWidth == 10); // 5 + 5
		Test.Assert(label.MeasuredHeight == 20); // 10 + 10
	}

	[Test]
	public static void Label_WordWrap_DefaultOff()
	{
		let label = scope Label();
		Test.Assert(!label.WordWrap);
	}
}
