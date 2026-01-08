using System;

namespace Sedulous.UI.Tests;

class UIElementIdTests
{
	[Test]
	public static void EmptyIdHasZeroHash()
	{
		let id = UIElementId.Empty;
		Test.Assert(id.Hash == 0);
		Test.Assert(id.IsEmpty);
	}

	[Test]
	public static void EmptyStringProducesZeroHash()
	{
		let id = UIElementId("");
		Test.Assert(id.Hash == 0);
		Test.Assert(id.IsEmpty);
	}

	[Test]
	public static void SameStringProducesSameHash()
	{
		let id1 = UIElementId("button1");
		let id2 = UIElementId("button1");
		Test.Assert(id1 == id2);
		Test.Assert(id1.Hash == id2.Hash);
	}

	[Test]
	public static void DifferentStringsProduceDifferentHashes()
	{
		let id1 = UIElementId("button1");
		let id2 = UIElementId("button2");
		Test.Assert(id1 != id2);
		Test.Assert(id1.Hash != id2.Hash);
	}

	[Test]
	public static void CaseSensitiveHashing()
	{
		let id1 = UIElementId("Button");
		let id2 = UIElementId("button");
		Test.Assert(id1 != id2);
	}

	[Test]
	public static void ImplicitConversionFromString()
	{
		UIElementId id = "myElement";
		Test.Assert(!id.IsEmpty);
		Test.Assert(id == UIElementId("myElement"));
	}

	[Test]
	public static void HashCodeConsistentWithEquality()
	{
		let id1 = UIElementId("testId");
		let id2 = UIElementId("testId");
		Test.Assert(id1.GetHashCode() == id2.GetHashCode());
	}

	[Test]
	public static void NonEmptyIdIsNotEmpty()
	{
		let id = UIElementId("x");
		Test.Assert(!id.IsEmpty);
	}
}
