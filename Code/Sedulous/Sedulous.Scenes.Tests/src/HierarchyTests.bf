namespace Sedulous.Scenes.Tests;

using System;
using System.Collections;
using Sedulous.Scenes;
using Sedulous.Mathematics;

class HierarchyTests
{
	[Test]
	public static void TestSetParent()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let parent = scene.CreateEntity();
		let child = scene.CreateEntity();

		scene.SetParent(child, parent);

		Test.Assert(scene.GetParent(child) == parent);
		Test.Assert(scene.GetParent(parent) == .Invalid);
	}

	[Test]
	public static void TestGetChildren()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let parent = scene.CreateEntity();
		let child1 = scene.CreateEntity();
		let child2 = scene.CreateEntity();

		scene.SetParent(child1, parent);
		scene.SetParent(child2, parent);

		let children = scope List<EntityId>();
		scene.GetChildren(parent, children);

		Test.Assert(children.Count == 2);
		Test.Assert(children.Contains(child1));
		Test.Assert(children.Contains(child2));
	}

	[Test]
	public static void TestHasChildren()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let parent = scene.CreateEntity();
		let child = scene.CreateEntity();
		let lonely = scene.CreateEntity();

		Test.Assert(!scene.HasChildren(parent));
		Test.Assert(!scene.HasChildren(lonely));

		scene.SetParent(child, parent);

		Test.Assert(scene.HasChildren(parent));
		Test.Assert(!scene.HasChildren(lonely));
	}

	[Test]
	public static void TestUnparent()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let parent = scene.CreateEntity();
		let child = scene.CreateEntity();

		scene.SetParent(child, parent);
		Test.Assert(scene.GetParent(child) == parent);

		// Set parent to Invalid to unparent
		scene.SetParent(child, .Invalid);
		Test.Assert(scene.GetParent(child) == .Invalid);
		Test.Assert(!scene.HasChildren(parent));
	}

	[Test]
	public static void TestReparent()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let parent1 = scene.CreateEntity();
		let parent2 = scene.CreateEntity();
		let child = scene.CreateEntity();

		scene.SetParent(child, parent1);
		Test.Assert(scene.HasChildren(parent1));
		Test.Assert(!scene.HasChildren(parent2));

		scene.SetParent(child, parent2);
		Test.Assert(!scene.HasChildren(parent1));
		Test.Assert(scene.HasChildren(parent2));
		Test.Assert(scene.GetParent(child) == parent2);
	}

	[Test]
	public static void TestWorldTransformInheritance()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let parent = scene.CreateEntity();
		let child = scene.CreateEntity();

		scene.SetPosition(parent, .(10, 0, 0));
		scene.SetPosition(child, .(5, 0, 0));
		scene.SetParent(child, parent);

		// Force transform update by running scene update
		scene.SetState(.Active);
		scene.Update(0.016f);

		let childWorld = scene.GetWorldMatrix(child);
		// Child world position should be parent + local = (15, 0, 0)
		// Translation is in M41, M42, M43 (row-major)
		Test.Assert(Math.Abs(childWorld.M41 - 15) < 0.001f);
		Test.Assert(Math.Abs(childWorld.M42) < 0.001f);
		Test.Assert(Math.Abs(childWorld.M43) < 0.001f);
	}

	[Test]
	public static void TestDeepHierarchy()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let root = scene.CreateEntity();
		let level1 = scene.CreateEntity();
		let level2 = scene.CreateEntity();
		let level3 = scene.CreateEntity();

		scene.SetParent(level1, root);
		scene.SetParent(level2, level1);
		scene.SetParent(level3, level2);

		scene.SetPosition(root, .(10, 0, 0));
		scene.SetPosition(level1, .(10, 0, 0));
		scene.SetPosition(level2, .(10, 0, 0));
		scene.SetPosition(level3, .(10, 0, 0));

		scene.SetState(.Active);
		scene.Update(0.016f);

		// Each level adds 10, so level3 should be at 40
		let level3World = scene.GetWorldMatrix(level3);
		Test.Assert(Math.Abs(level3World.M41 - 40) < 0.001f);
	}

	[Test]
	public static void TestDestroyParentDestroysChildren()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let parent = scene.CreateEntity();
		let child1 = scene.CreateEntity();
		let child2 = scene.CreateEntity();

		scene.SetParent(child1, parent);
		scene.SetParent(child2, parent);

		Test.Assert(scene.EntityCount == 3);

		scene.DestroyEntity(parent);

		Test.Assert(!scene.IsValid(parent));
		Test.Assert(!scene.IsValid(child1));
		Test.Assert(!scene.IsValid(child2));
		Test.Assert(scene.EntityCount == 0);
	}

	[Test]
	public static void TestDestroyChildDoesNotAffectParent()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let parent = scene.CreateEntity();
		let child = scene.CreateEntity();

		scene.SetParent(child, parent);
		scene.DestroyEntity(child);

		Test.Assert(scene.IsValid(parent));
		Test.Assert(!scene.IsValid(child));
		Test.Assert(!scene.HasChildren(parent));
	}

	[Test]
	public static void TestCantParentToSelf()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();

		scene.SetParent(entity, entity);

		// Should still have no parent
		Test.Assert(scene.GetParent(entity) == .Invalid);
	}

	[Test]
	public static void TestScaleInheritance()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let parent = scene.CreateEntity();
		let child = scene.CreateEntity();

		scene.SetScale(parent, .(2, 2, 2));
		scene.SetScale(child, .(3, 3, 3));
		scene.SetParent(child, parent);

		scene.SetState(.Active);
		scene.Update(0.016f);

		let childWorld = scene.GetWorldMatrix(child);
		// Scale combines: 2 * 3 = 6
		// M11, M22, M33 are the scale components
		Test.Assert(Math.Abs(childWorld.M11 - 6) < 0.001f);
		Test.Assert(Math.Abs(childWorld.M22 - 6) < 0.001f);
		Test.Assert(Math.Abs(childWorld.M33 - 6) < 0.001f);
	}
}
