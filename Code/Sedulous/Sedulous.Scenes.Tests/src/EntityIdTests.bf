namespace Sedulous.Scenes.Tests;

using System;
using Sedulous.Scenes;

class EntityIdTests
{
	[Test]
	public static void TestInvalid()
	{
		let invalid = EntityId.Invalid;
		Test.Assert(!invalid.IsValid);
		Test.Assert(invalid.Index == uint32.MaxValue);
		Test.Assert(invalid.Generation == 0);
	}

	[Test]
	public static void TestValidId()
	{
		let id = EntityId(0, 1);
		Test.Assert(id.IsValid);
		Test.Assert(id.Index == 0);
		Test.Assert(id.Generation == 1);
	}

	[Test]
	public static void TestIndexZeroIsValid()
	{
		// Index 0 should be valid (unlike some systems that treat 0 as invalid)
		let id = EntityId(0, 1);
		Test.Assert(id.IsValid);
	}

	[Test]
	public static void TestEquality()
	{
		let id1 = EntityId(5, 3);
		let id2 = EntityId(5, 3);
		let id3 = EntityId(5, 4); // Different generation
		let id4 = EntityId(6, 3); // Different index

		Test.Assert(id1 == id2);
		Test.Assert(id1 != id3);
		Test.Assert(id1 != id4);
	}

	[Test]
	public static void TestHashCode()
	{
		let id1 = EntityId(5, 3);
		let id2 = EntityId(5, 3);
		let id3 = EntityId(5, 4);

		// Same IDs should have same hash
		Test.Assert(id1.GetHashCode() == id2.GetHashCode());

		// Different IDs should (usually) have different hashes
		Test.Assert(id1.GetHashCode() != id3.GetHashCode());
	}

	[Test]
	public static void TestToString()
	{
		let id = EntityId(42, 7);
		let str = scope String();
		id.ToString(str);
		Test.Assert(str.Contains("42"));
		Test.Assert(str.Contains("7"));
	}
}
