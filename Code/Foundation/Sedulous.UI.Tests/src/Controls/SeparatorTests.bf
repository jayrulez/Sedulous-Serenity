using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class SeparatorTests
{
	private static RootView SetupContext(UIContext ctx, View root, float w, float h)
	{
		return TestHelper.SetupContext(ctx, root, w, h);
	}

	[Test]
	public static void HorizontalSeparator_MeasuresThicknessAsHeight()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let sep = new Separator();
		sep.Orientation = .Horizontal;
		sep.Thickness = 2;
		root.AddView(sep, new LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		Test.Assert(sep.Height == 2);
		Test.Assert(sep.Width == 200);
	}

	[Test]
	public static void VerticalSeparator_MeasuresThicknessAsWidth()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let sep = new Separator();
		sep.Orientation = .Vertical;
		sep.Thickness = 3;
		root.AddView(sep, new LayoutParams(LayoutParams.WrapContent, LayoutParams.MatchParent));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		Test.Assert(sep.Width == 3);
		Test.Assert(sep.Height == 200);
	}

	[Test]
	public static void DefaultThickness_IsZero_MeansAuto()
	{
		let sep = scope Separator();
		Test.Assert(sep.Thickness == 0); // 0 = use theme dimension or default 1
	}

	[Test]
	public static void Orientation_DefaultIsHorizontal()
	{
		let sep = scope Separator();
		Test.Assert(sep.Orientation == .Horizontal);
	}
}
