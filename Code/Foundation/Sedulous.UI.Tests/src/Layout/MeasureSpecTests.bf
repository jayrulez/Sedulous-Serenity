using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class MeasureSpecTests
{
	[Test]
	public static void Exactly_ReturnsExactSize()
	{
		let spec = MeasureSpec.MakeExactly(100);
		Test.Assert(spec.Resolve(50) == 100);
		Test.Assert(spec.Resolve(200) == 100);
		Test.Assert(spec.Resolve(0) == 100);
	}

	[Test]
	public static void AtMost_ClampsToMax()
	{
		let spec = MeasureSpec.MakeAtMost(100);
		Test.Assert(spec.Resolve(50) == 50);
		Test.Assert(spec.Resolve(200) == 100);
		Test.Assert(spec.Resolve(100) == 100);
	}

	[Test]
	public static void Unspecified_ReturnsDesired()
	{
		let spec = MeasureSpec.MakeUnspecified();
		Test.Assert(spec.Resolve(50) == 50);
		Test.Assert(spec.Resolve(200) == 200);
		Test.Assert(spec.Resolve(0) == 0);
	}

	[Test]
	public static void Resolve_WithMinMax_AppliesConstraints()
	{
		let spec = MeasureSpec.MakeAtMost(200);

		// Min constraint
		Test.Assert(spec.Resolve(10, 50, 0) == 50);
		// Max constraint
		Test.Assert(spec.Resolve(300, 0, 150) == 150);
		// Both: min wins over spec result, then max clamps
		Test.Assert(spec.Resolve(10, 50, 80) == 50);
		// No constraints active
		Test.Assert(spec.Resolve(100, 0, 0) == 100);
	}

	[Test]
	public static void Exactly_WithMinMax_StillAppliesConstraints()
	{
		let spec = MeasureSpec.MakeExactly(100);
		// Min larger than exact
		Test.Assert(spec.Resolve(0, 150, 0) == 150);
		// Max smaller than exact
		Test.Assert(spec.Resolve(0, 0, 50) == 50);
	}
}
