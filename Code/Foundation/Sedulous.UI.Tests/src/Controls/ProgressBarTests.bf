using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class ProgressBarTests
{
	[Test]
	public static void ProgressBar_DefaultProgress()
	{
		let pb = scope ProgressBar();
		Test.Assert(pb.Progress == 0);
	}

	[Test]
	public static void ProgressBar_SetProgress_ClampsToRange()
	{
		let pb = scope ProgressBar();

		pb.Progress = 0.5f;
		Test.Assert(pb.Progress == 0.5f);

		pb.Progress = 1.5f;
		Test.Assert(pb.Progress == 1.0f);

		pb.Progress = -0.5f;
		Test.Assert(pb.Progress == 0);
	}

	[Test]
	public static void ProgressBar_DefaultHeight_FromTheme()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let pb = new ProgressBar();
		root.AddView(pb, new LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent));
		let rootView = TestHelper.SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Default DarkTheme sets ProgressBar height to 6
		Test.Assert(pb.Height == 6);
	}
}
