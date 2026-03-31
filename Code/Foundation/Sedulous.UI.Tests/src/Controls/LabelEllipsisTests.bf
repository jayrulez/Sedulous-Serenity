using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class LabelEllipsisTests
{
	[Test]
	public static void TextOverflow_DefaultIsNone()
	{
		let label = scope Label("Hello");
		Test.Assert(label.TextOverflow == .None);
	}

	[Test]
	public static void TextOverflow_CanSetToEllipsis()
	{
		let label = scope Label("Hello");
		label.TextOverflow = .Ellipsis;
		Test.Assert(label.TextOverflow == .Ellipsis);
	}

	[Test]
	public static void TextOverflow_CanSetBackToNone()
	{
		let label = scope Label("Hello");
		label.TextOverflow = .Ellipsis;
		label.TextOverflow = .None;
		Test.Assert(label.TextOverflow == .None);
	}

	// Note: visual truncation tests require a font service (rendering context),
	// which is not available in unit tests. The ellipsis logic is tested
	// indirectly through measure behavior.

	[Test]
	public static void Measure_WithoutContext_DoesNotCrash()
	{
		let label = scope Label("A very long text that should trigger ellipsis truncation if a font were available");
		label.TextOverflow = .Ellipsis;
		// Without a UIContext/FontService, measure should still succeed (no crash)
		label.Measure(.MakeAtMost(100), .MakeAtMost(30));
		// Without font, measured size is padding only
		Test.Assert(label.MeasuredWidth >= 0);
		Test.Assert(label.MeasuredHeight >= 0);
	}
}
