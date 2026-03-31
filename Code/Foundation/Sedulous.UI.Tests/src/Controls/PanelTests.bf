using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class PanelTests
{
	private static RootView SetupContext(UIContext ctx, View root, float w, float h)
	{
		return TestHelper.SetupContext(ctx, root, w, h);
	}

	[Test]
	public static void Panel_LayoutsChildrenLikeFrameLayout()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let panel = new Panel();
		panel.FillColor = .(0.2f, 0.2f, 0.2f, 1.0f);
		root.AddView(panel, new LayoutParams(LayoutParams.MatchParent, LayoutParams.MatchParent));

		let child = new ColorView(.(1.0f, 0, 0, 1.0f));
		panel.AddView(child, new FrameLayout.LayoutParams(50, 50, .Center));

		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Child should be centered in the panel
		Test.Assert(child.Width == 50);
		Test.Assert(child.Height == 50);
		Test.Assert(child.Left == 75); // (200 - 50) / 2
		Test.Assert(child.Top == 75);
	}

	[Test]
	public static void Panel_DefaultBorderWidthIsZero()
	{
		let panel = scope Panel();
		Test.Assert(panel.BorderWidth == 0);
	}

	[Test]
	public static void Panel_DefaultCornerRadiusIsZero()
	{
		let panel = scope Panel();
		Test.Assert(panel.CornerRadius == 0);
	}

	[Test]
	public static void Panel_PaddingAffectsChildLayout()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let panel = new Panel();
		panel.Padding = .(10);
		root.AddView(panel, new LayoutParams(LayoutParams.MatchParent, LayoutParams.MatchParent));

		let child = new ColorView(.(1.0f, 0, 0, 1.0f));
		panel.AddView(child, new LayoutParams(LayoutParams.MatchParent, LayoutParams.MatchParent));

		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Child should be inset by padding
		Test.Assert(child.Left == 10);
		Test.Assert(child.Top == 10);
		Test.Assert(child.Width == 180);
		Test.Assert(child.Height == 180);
	}
}
