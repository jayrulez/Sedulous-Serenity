using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class MomentumTests
{
	[Test]
	public static void MomentumHelper_DefaultIsInactive()
	{
		var m = MomentumHelper();
		Test.Assert(!m.IsActive);
	}

	[Test]
	public static void MomentumHelper_ImpulseActivates()
	{
		var m = MomentumHelper();
		m.ApplyImpulse(100, 0);
		Test.Assert(m.IsActive);
	}

	[Test]
	public static void MomentumHelper_DecayReducesVelocity()
	{
		var m = MomentumHelper();
		m.ApplyImpulse(100, 0);
		float initialVx = m.VelocityX;
		m.Update(0.1f);
		Test.Assert(m.VelocityX < initialVx);
		Test.Assert(m.VelocityX > 0);
	}

	[Test]
	public static void MomentumHelper_EventuallyStops()
	{
		var m = MomentumHelper();
		m.ApplyImpulse(50, 50);
		for (int i = 0; i < 100; i++)
			m.Update(0.05f);
		Test.Assert(!m.IsActive);
		Test.Assert(m.VelocityX == 0);
		Test.Assert(m.VelocityY == 0);
	}

	[Test]
	public static void MomentumHelper_StopImmediate()
	{
		var m = MomentumHelper();
		m.ApplyImpulse(200, 200);
		Test.Assert(m.IsActive);
		m.Stop();
		Test.Assert(!m.IsActive);
	}

	[Test]
	public static void MomentumHelper_UpdateReturnsDelta()
	{
		var m = MomentumHelper();
		m.ApplyImpulse(100, 200);
		let (dx, dy) = m.Update(0.016f);
		Test.Assert(dx != 0);
		Test.Assert(dy != 0);
	}

	[Test]
	public static void MomentumHelper_InactiveDeltaIsZero()
	{
		var m = MomentumHelper();
		let (dx, dy) = m.Update(0.016f);
		Test.Assert(dx == 0);
		Test.Assert(dy == 0);
	}
}
