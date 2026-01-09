using System;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;

namespace Sedulous.Engine.Core.Tests;

class EntityManagerTests
{
	[Test]
	public static void TestCreateEntity()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let entity = scene.EntityManager.CreateEntity("Entity1");
		Test.Assert(entity != null);
		Test.Assert(entity.Name == "Entity1");
		Test.Assert(entity.Id.IsValid);
	}

	[Test]
	public static void TestEntityCount()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		Test.Assert(scene.EntityManager.EntityCount == 0);

		scene.EntityManager.CreateEntity("Entity1");
		Test.Assert(scene.EntityManager.EntityCount == 1);

		scene.EntityManager.CreateEntity("Entity2");
		Test.Assert(scene.EntityManager.EntityCount == 2);
	}

	[Test]
	public static void TestDestroyEntity()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let entity = scene.EntityManager.CreateEntity("Entity1");
		let id = entity.Id;

		Test.Assert(scene.EntityManager.EntityCount == 1);

		let destroyed = scene.EntityManager.DestroyEntity(id);
		Test.Assert(destroyed);
		Test.Assert(scene.EntityManager.EntityCount == 0);
	}

	[Test]
	public static void TestGetEntity()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let entity = scene.EntityManager.CreateEntity("Entity1");
		let id = entity.Id;

		let retrieved = scene.EntityManager.GetEntity(id);
		Test.Assert(retrieved == entity);
	}

	[Test]
	public static void TestGetEntityInvalid()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let retrieved = scene.EntityManager.GetEntity(.Invalid);
		Test.Assert(retrieved == null);
	}

	[Test]
	public static void TestStaleIdDetection()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let entity = scene.EntityManager.CreateEntity("Entity1");
		let staleId = entity.Id;

		// Destroy and recreate
		scene.EntityManager.DestroyEntity(staleId);
		let newEntity = scene.EntityManager.CreateEntity("Entity2");

		// Stale ID should not retrieve the new entity
		let retrieved = scene.EntityManager.GetEntity(staleId);
		Test.Assert(retrieved == null);

		// New entity should have incremented generation
		Test.Assert(newEntity.Id.Generation > staleId.Generation);
	}

	[Test]
	public static void TestIsValid()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let entity = scene.EntityManager.CreateEntity("Entity1");
		let id = entity.Id;

		Test.Assert(scene.EntityManager.IsValid(id));

		scene.EntityManager.DestroyEntity(id);
		Test.Assert(!scene.EntityManager.IsValid(id));
	}

	[Test]
	public static void TestParentChildRelationship()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let parent = scene.EntityManager.CreateEntity("Parent");
		let child = scene.EntityManager.CreateEntity("Child");

		scene.EntityManager.SetParent(child.Id, parent.Id);

		Test.Assert(child.ParentId == parent.Id);
		Test.Assert(parent.ChildIds.Count == 1);
		Test.Assert(parent.ChildIds[0] == child.Id);
	}

	[Test]
	public static void TestChangeParent()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let parent1 = scene.EntityManager.CreateEntity("Parent1");
		let parent2 = scene.EntityManager.CreateEntity("Parent2");
		let child = scene.EntityManager.CreateEntity("Child");

		scene.EntityManager.SetParent(child.Id, parent1.Id);
		Test.Assert(parent1.ChildIds.Count == 1);

		scene.EntityManager.SetParent(child.Id, parent2.Id);
		Test.Assert(parent1.ChildIds.Count == 0);
		Test.Assert(parent2.ChildIds.Count == 1);
		Test.Assert(child.ParentId == parent2.Id);
	}

	[Test]
	public static void TestDestroyParentDestroysChildren()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let parent = scene.EntityManager.CreateEntity("Parent");
		let child = scene.EntityManager.CreateEntity("Child");
		let parentId = parent.Id;
		let childId = child.Id;

		scene.EntityManager.SetParent(childId, parentId);

		Test.Assert(scene.EntityManager.IsValid(parentId));
		Test.Assert(scene.EntityManager.IsValid(childId));

		let destroyed = scene.EntityManager.DestroyEntity(parentId);
		Test.Assert(destroyed);

		Test.Assert(!scene.EntityManager.IsValid(parentId));
		Test.Assert(!scene.EntityManager.IsValid(childId));
	}

	[Test]
	public static void TestTransformHierarchyPropagation()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let parent = scene.EntityManager.CreateEntity("Parent");
		let child = scene.EntityManager.CreateEntity("Child");

		parent.Transform.SetPosition(.(10, 0, 0));
		child.Transform.SetPosition(.(5, 0, 0));

		scene.EntityManager.SetParent(child.Id, parent.Id);
		scene.EntityManager.UpdateTransforms();

		// Child world position should be parent position + child local position
		let childWorldPos = child.Transform.WorldPosition;
		Test.Assert(Math.Abs(childWorldPos.X - 15) < 0.0001f);
	}

	[Test]
	public static void TestEnumerator()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		scene.EntityManager.CreateEntity("Entity1");
		scene.EntityManager.CreateEntity("Entity2");
		scene.EntityManager.CreateEntity("Entity3");

		int count = 0;
		for (let entity in scene.EntityManager)
		{
			Test.Assert(entity != null);
			count++;
		}

		Test.Assert(count == 3);
	}
}
