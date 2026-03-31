using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class StateListDrawableTests
{
	[Test]
	public static void GetDrawable_Unset_ReturnsNull()
	{
		let sld = scope StateListDrawable();
		Test.Assert(sld.GetDrawable(.Normal) == null);
	}

	[Test]
	public static void GetDrawable_WithDefault_ReturnsDefault()
	{
		let sld = scope StateListDrawable();
		let defaultDrawable = new ColorDrawable(.(1.0f, 0, 0, 1.0f));
		sld.SetDefault(defaultDrawable);

		Test.Assert(sld.GetDrawable(.Normal) === defaultDrawable);
		Test.Assert(sld.GetDrawable(.Hover) === defaultDrawable);
		Test.Assert(sld.GetDrawable(.Pressed) === defaultDrawable);
	}

	[Test]
	public static void GetDrawable_SpecificState_ReturnsStateDrawable()
	{
		let sld = scope StateListDrawable();
		let normalDrawable = new ColorDrawable(.(1.0f, 0, 0, 1.0f));
		let hoverDrawable = new ColorDrawable(.(0, 1.0f, 0, 1.0f));
		sld.SetDrawable(.Normal, normalDrawable);
		sld.SetDrawable(.Hover, hoverDrawable);

		Test.Assert(sld.GetDrawable(.Normal) === normalDrawable);
		Test.Assert(sld.GetDrawable(.Hover) === hoverDrawable);
	}

	[Test]
	public static void GetDrawable_UnsetState_FallsBackToDefault()
	{
		let sld = scope StateListDrawable();
		let defaultDrawable = new ColorDrawable(.(1.0f, 0, 0, 1.0f));
		let hoverDrawable = new ColorDrawable(.(0, 1.0f, 0, 1.0f));
		sld.SetDefault(defaultDrawable);
		sld.SetDrawable(.Hover, hoverDrawable);

		// Normal falls back to default
		Test.Assert(sld.GetDrawable(.Normal) === defaultDrawable);
		// Hover returns specific
		Test.Assert(sld.GetDrawable(.Hover) === hoverDrawable);
		// Pressed falls back to default
		Test.Assert(sld.GetDrawable(.Pressed) === defaultDrawable);
	}

	[Test]
	public static void SetDrawable_Overwrite_DeletesOld()
	{
		let sld = scope StateListDrawable();
		sld.SetDrawable(.Normal, new ColorDrawable(.(1.0f, 0, 0, 1.0f)));
		let newDrawable = new ColorDrawable(.(0, 1.0f, 0, 1.0f));
		sld.SetDrawable(.Normal, newDrawable);

		Test.Assert(sld.GetDrawable(.Normal) === newDrawable);
	}
}
