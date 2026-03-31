using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class SliderTests
{
	private static RootView SetupContext(UIContext ctx, View root, float w, float h)
	{
		return TestHelper.SetupContext(ctx, root, w, h);
	}

	[Test]
	public static void Slider_DefaultValues()
	{
		let s = scope Slider();
		Test.Assert(s.Value == 0);
		Test.Assert(s.Min == 0);
		Test.Assert(s.Max == 1);
		Test.Assert(s.Step == 0);
	}

	[Test]
	public static void Slider_SetValue_ClampsToRange()
	{
		let s = scope Slider();
		s.Min = 0;
		s.Max = 10;

		s.Value = 15;
		Test.Assert(s.Value == 10);

		s.Value = -5;
		Test.Assert(s.Value == 0);
	}

	[Test]
	public static void Slider_Step_SnapsToNearest()
	{
		let s = scope Slider();
		s.Min = 0;
		s.Max = 1;
		s.Step = 0.25f;

		s.Value = 0.3f;
		Test.Assert(s.Value == 0.25f);

		s.Value = 0.4f;
		Test.Assert(Math.Abs(s.Value - 0.5f) < 0.001f);
	}

	[Test]
	public static void Slider_FiresOnValueChanged()
	{
		let s = scope Slider();
		s.Min = 0;
		s.Max = 100;

		bool eventFired = false;
		float lastValue = -1;
		s.OnValueChanged.Subscribe(new [&eventFired, &lastValue] (sl, v) => { eventFired = true; lastValue = v; });

		s.Value = 50;
		Test.Assert(eventFired);
		Test.Assert(lastValue == 50);
	}

	[Test]
	public static void Slider_SameValue_NoEvent()
	{
		let s = scope Slider();
		s.Value = 0;

		bool eventFired = false;
		s.OnValueChanged.Subscribe(new [&eventFired] (sl, v) => { eventFired = true; });

		s.Value = 0; // same value
		Test.Assert(!eventFired);
	}

	[Test]
	public static void Slider_ChangeMax_ReclampsValue()
	{
		let s = scope Slider();
		s.Max = 100;
		s.Value = 80;

		s.Max = 50;
		Test.Assert(s.Value == 50);
	}

	[Test]
	public static void Slider_ChangeMin_ReclampsValue()
	{
		let s = scope Slider();
		s.Min = 0;
		s.Max = 100;
		s.Value = 10;

		s.Min = 20;
		Test.Assert(s.Value == 20);
	}

	[Test]
	public static void Slider_IsFocusable()
	{
		let s = scope Slider();
		Test.Assert(s.Focusable);
	}

	[Test]
	public static void Slider_Drag_UpdatesValue()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let slider = new Slider();
		slider.Min = 0;
		slider.Max = 1;
		root.AddView(slider, new LayoutParams(200, 24));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Click at midpoint (thumb half = 7, track range 7..193)
		float midX = 100;
		ctx.ProcessMouseDown(midX, 12, .Left);

		// Value should be approximately 0.5
		Test.Assert(Math.Abs(slider.Value - 0.5f) < 0.1f);

		ctx.ProcessMouseUp(midX, 12, .Left);
	}
}
