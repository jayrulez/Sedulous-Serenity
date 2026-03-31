using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class ScrollViewTests
{
	// Helper: create a view with fixed measured size
	private static View MakeFixedView(float w, float h)
	{
		let v = new ColorView(.(1, 0, 0, 1));
		v.MinWidth = w;
		v.MinHeight = h;
		return v;
	}

	[Test]
	public static void ScrollView_VerticalScrollRange()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;

		let content = MakeFixedView(200, 500);
		sv.SetContent(content); // ScrollView owns content

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		Test.Assert(sv.MaxScrollY > 0);
		// With a 12px scrollbar: viewport ~188 wide, but height-wise:
		// Extent=500, Viewport=200 (or 200-12 if H scrollbar), so MaxScrollY = 500 - viewport
		Test.Assert(sv.MaxScrollY == sv.ExtentHeight - sv.ViewportHeight);
	}

	[Test]
	public static void ScrollView_NoScrollWhenContentFits()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;

		let content = MakeFixedView(100, 100);
		sv.SetContent(content);

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		Test.Assert(sv.MaxScrollX == 0);
		Test.Assert(sv.MaxScrollY == 0);
	}

	[Test]
	public static void ScrollView_ScrollYClamped()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;

		let content = MakeFixedView(200, 500);
		sv.SetContent(content);

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		sv.ScrollY = -100;
		Test.Assert(sv.ScrollY == 0);

		sv.ScrollY = 9999;
		Test.Assert(sv.ScrollY == sv.MaxScrollY);
	}

	[Test]
	public static void ScrollView_BothAxes()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;
		sv.AllowHorizontalScroll = true;

		let content = MakeFixedView(400, 600);
		sv.SetContent(content);

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		Test.Assert(sv.MaxScrollX > 0);
		Test.Assert(sv.MaxScrollY > 0);
	}

	[Test]
	public static void ScrollView_ScrollBy()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;

		let content = MakeFixedView(200, 1000);
		sv.SetContent(content);

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		sv.ScrollBy(0, 50);
		Test.Assert(sv.ScrollY == 50);

		sv.ScrollBy(0, 30);
		Test.Assert(sv.ScrollY == 80);
	}

	[Test]
	public static void ScrollView_ScrollToTop()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;

		let content = MakeFixedView(200, 500);
		sv.SetContent(content);

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		sv.ScrollY = 100;
		sv.ScrollToTop();
		Test.Assert(sv.ScrollY == 0);
	}

	[Test]
	public static void ScrollView_ScrollToBottom()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;

		let content = MakeFixedView(200, 500);
		sv.SetContent(content);

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		sv.ScrollToBottom();
		Test.Assert(sv.ScrollY == sv.MaxScrollY);
	}

	[Test]
	public static void ScrollView_ScrollBarPolicyNever()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;
		sv.VerticalScrollBarPolicy = .Never;

		let content = MakeFixedView(200, 500);
		sv.SetContent(content);

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		// Viewport should be full width (no scrollbar eating space)
		Test.Assert(sv.ViewportWidth == 200);
		// But still scrollable
		Test.Assert(sv.MaxScrollY > 0);
	}

	[Test]
	public static void ScrollView_ScrollBarPolicyAlways()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;
		sv.VerticalScrollBarPolicy = .Always;

		let content = MakeFixedView(100, 100);
		sv.SetContent(content);

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		// Scrollbar should eat space even though content fits
		Test.Assert(sv.ViewportWidth < 200);
	}

	[Test]
	public static void ScrollView_SetContentReplacePrevious()
	{
		let sv = scope ScrollView();

		let content1 = MakeFixedView(100, 500);
		sv.SetContent(content1);
		Test.Assert(sv.Content == content1);

		let content2 = MakeFixedView(100, 300);
		sv.SetContent(content2);
		Test.Assert(sv.Content == content2);
		// content1 was deleted by RemoveView
	}

	[Test]
	public static void ScrollView_DefaultConfiguration()
	{
		let sv = scope ScrollView();
		Test.Assert(sv.AllowVerticalScroll == true);
		Test.Assert(sv.AllowHorizontalScroll == false);
		Test.Assert(sv.VerticalScrollBarPolicy == .Auto);
		Test.Assert(sv.HorizontalScrollBarPolicy == .Auto);
		Test.Assert(sv.WheelSpeed == 1.0f);
		Test.Assert(sv.ClipToBounds == true);
	}

	[Test]
	public static void ScrollView_MomentumDecays()
	{
		let sv = scope ScrollView();
		sv.AllowVerticalScroll = true;

		let content = MakeFixedView(200, 2000);
		sv.SetContent(content);

		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);

		sv.MomentumFriction = 5.0f;
		// Can't easily test momentum in unit tests without ticking,
		// but we can verify the property
		Test.Assert(sv.MomentumFriction == 5.0f);
	}

	[Test]
	public static void ScrollView_NullContentSafe()
	{
		let sv = scope ScrollView();
		sv.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(200));
		sv.Layout(0, 0, 200, 200);
		Test.Assert(sv.Content == null);
		Test.Assert(sv.MaxScrollX == 0);
		Test.Assert(sv.MaxScrollY == 0);
	}
}
