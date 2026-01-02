using System;
using Sedulous.Framework.Core;

namespace Sedulous.Framework.Core.Tests;

class EntityIdTests
{
	[Test]
	public static void TestInvalid()
	{
		let invalid = EntityId.Invalid;
		Test.Assert(!invalid.IsValid);
		Test.Assert(invalid.Index == 0);
		Test.Assert(invalid.Generation == 0);
	}

	[Test]
	public static void TestValidId()
	{
		let id = EntityId(1, 0);
		Test.Assert(id.IsValid);
		Test.Assert(id.Index == 1);
		Test.Assert(id.Generation == 0);
	}

	[Test]
	public static void TestEquality()
	{
		let id1 = EntityId(5, 3);
		let id2 = EntityId(5, 3);
		let id3 = EntityId(5, 4);
		let id4 = EntityId(6, 3);

		Test.Assert(id1 == id2);
		Test.Assert(id1 != id3);
		Test.Assert(id1 != id4);
		Test.Assert(id1.Equals(id2));
	}

	[Test]
	public static void TestHashCode()
	{
		let id1 = EntityId(5, 3);
		let id2 = EntityId(5, 3);
		let id3 = EntityId(5, 4);

		Test.Assert(id1.GetHashCode() == id2.GetHashCode());
		Test.Assert(id1.GetHashCode() != id3.GetHashCode());
	}

	[Test]
	public static void TestToString()
	{
		let id = EntityId(42, 7);
		let str = scope String();
		id.ToString(str);
		Test.Assert(str == "Entity(42, 7)");
	}

	[Test]
	public static void TestZeroIndexWithNonZeroGeneration()
	{
		// Index 0 with non-zero generation should be valid
		let id = EntityId(0, 1);
		Test.Assert(id.IsValid);
	}
}
