namespace Sedulous.Scenes.Tests;

using System;
using Sedulous.Scenes;
using Sedulous.Mathematics;

// Example components for testing (pure data structs)
struct HealthComponent
{
	public float Current;
	public float Max;
}

struct VelocityComponent
{
	public Vector3 Value;
}

struct TagComponent
{
	public int32 Tag;
}

class SceneTests
{
	[Test]
	public static void TestCreateEntity()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();

		Test.Assert(entity.IsValid);
		Test.Assert(scene.IsValid(entity));
		Test.Assert(scene.EntityCount == 1);
	}

	[Test]
	public static void TestCreateMultipleEntities()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let e1 = scene.CreateEntity();
		let e2 = scene.CreateEntity();
		let e3 = scene.CreateEntity();

		Test.Assert(scene.EntityCount == 3);
		Test.Assert(e1 != e2);
		Test.Assert(e2 != e3);
		Test.Assert(scene.IsValid(e1));
		Test.Assert(scene.IsValid(e2));
		Test.Assert(scene.IsValid(e3));
	}

	[Test]
	public static void TestDestroyEntity()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		scene.DestroyEntity(entity);

		Test.Assert(!scene.IsValid(entity));
		Test.Assert(scene.EntityCount == 0);
	}

	[Test]
	public static void TestEntityIdReuse()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity1 = scene.CreateEntity();
		let index = entity1.Index;
		scene.DestroyEntity(entity1);

		let entity2 = scene.CreateEntity();

		// Same index, different generation
		Test.Assert(entity2.Index == index);
		Test.Assert(entity2.Generation > entity1.Generation);
		Test.Assert(!scene.IsValid(entity1)); // Old ID is stale
		Test.Assert(scene.IsValid(entity2));
	}

	[Test]
	public static void TestDefaultTransform()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		let transform = scene.GetTransform(entity);

		// Should be identity transform
		Test.Assert(transform.Position == .Zero);
		Test.Assert(transform.Scale == .(1, 1, 1));
	}

	[Test]
	public static void TestSetAndGetTransform()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();

		scene.SetPosition(entity, .(1, 2, 3));
		scene.SetScale(entity, .(2, 2, 2));

		let transform = scene.GetTransform(entity);
		Test.Assert(transform.Position.X == 1);
		Test.Assert(transform.Position.Y == 2);
		Test.Assert(transform.Position.Z == 3);
		Test.Assert(transform.Scale.X == 2);
	}

	[Test]
	public static void TestSetFullTransform()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		let newTransform = Transform(.(5, 6, 7), .Identity, .(3, 3, 3));

		scene.SetTransform(entity, newTransform);

		let result = scene.GetTransform(entity);
		Test.Assert(result.Position.X == 5);
		Test.Assert(result.Scale.X == 3);
	}

	[Test]
	public static void TestAddComponent()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		scene.SetComponent<HealthComponent>(entity, .() { Current = 100, Max = 100 });

		Test.Assert(scene.HasComponent<HealthComponent>(entity));
		Test.Assert(!scene.HasComponent<VelocityComponent>(entity));
	}

	[Test]
	public static void TestGetComponent()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		scene.SetComponent<HealthComponent>(entity, .() { Current = 75, Max = 100 });

		let health = scene.GetComponent<HealthComponent>(entity);
		Test.Assert(health != null);
		Test.Assert(health.Current == 75);
		Test.Assert(health.Max == 100);
	}

	[Test]
	public static void TestModifyComponent()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		scene.SetComponent<HealthComponent>(entity, .() { Current = 100, Max = 100 });

		// Modify via pointer
		let health = scene.GetComponent<HealthComponent>(entity);
		health.Current = 50;

		// Verify change persisted
		let health2 = scene.GetComponent<HealthComponent>(entity);
		Test.Assert(health2.Current == 50);
	}

	[Test]
	public static void TestRemoveComponent()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		scene.SetComponent<HealthComponent>(entity, .() { Current = 100, Max = 100 });

		Test.Assert(scene.HasComponent<HealthComponent>(entity));

		scene.RemoveComponent<HealthComponent>(entity);

		Test.Assert(!scene.HasComponent<HealthComponent>(entity));
		Test.Assert(scene.GetComponent<HealthComponent>(entity) == null);
	}

	[Test]
	public static void TestComponentQuery()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let e1 = scene.CreateEntity();
		scene.CreateEntity(); // e2 - intentionally has no component
		let e3 = scene.CreateEntity();

		scene.SetComponent<HealthComponent>(e1, .() { Current = 100, Max = 100 });
		scene.SetComponent<HealthComponent>(e3, .() { Current = 50, Max = 100 });

		int count = 0;
		for (let (id, component) in scene.Query<HealthComponent>())
		{
			count++;
			Test.Assert(id == e1 || id == e3);
		}
		Test.Assert(count == 2);
	}

	[Test]
	public static void TestMultipleComponentTypes()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		scene.SetComponent<HealthComponent>(entity, .() { Current = 100, Max = 100 });
		scene.SetComponent<VelocityComponent>(entity, .() { Value = .(1, 0, 0) });
		scene.SetComponent<TagComponent>(entity, .() { Tag = 42 });

		Test.Assert(scene.HasComponent<HealthComponent>(entity));
		Test.Assert(scene.HasComponent<VelocityComponent>(entity));
		Test.Assert(scene.HasComponent<TagComponent>(entity));

		let tag = scene.GetComponent<TagComponent>(entity);
		Test.Assert(tag.Tag == 42);
	}

	[Test]
	public static void TestComponentsRemovedOnEntityDestroy()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		scene.SetComponent<HealthComponent>(entity, .() { Current = 100, Max = 100 });

		scene.DestroyEntity(entity);

		// Component should be removed when entity is destroyed
		Test.Assert(!scene.HasComponent<HealthComponent>(entity));
	}

	[Test]
	public static void TestSceneName()
	{
		let scene = scope Scene("MyTestScene");
		defer scene.Dispose();

		Test.Assert(scene.Name == "MyTestScene");
	}

	[Test]
	public static void TestSceneState()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		Test.Assert(scene.State == .Unloaded);

		scene.SetState(.Active);
		Test.Assert(scene.State == .Active);

		scene.SetState(.Paused);
		Test.Assert(scene.State == .Paused);
	}

	[Test]
	public static void TestForEachEntity()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let e1 = scene.CreateEntity();
		let e2 = scene.CreateEntity();
		let e3 = scene.CreateEntity();

		int count = 0;
		scene.ForEachEntity(scope [&] (entity) => {
			count++;
			Test.Assert(entity == e1 || entity == e2 || entity == e3);
		});

		Test.Assert(count == 3);
	}
}
