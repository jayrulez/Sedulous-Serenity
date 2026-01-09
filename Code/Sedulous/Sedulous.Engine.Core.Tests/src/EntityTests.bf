using System;
using Sedulous.Engine.Core;
using Sedulous.Serialization;
using Sedulous.Mathematics;

namespace Sedulous.Engine.Core.Tests;

/// Test component for entity tests.
class TestComponent : IEntityComponent
{
	public int32 Value = 0;
	public bool WasAttached = false;
	public bool WasDetached = false;
	public float TotalDeltaTime = 0;

	public int32 SerializationVersion => 1;

	public void OnAttach(Entity entity)
	{
		WasAttached = true;
	}

	public void OnDetach()
	{
		WasDetached = true;
	}

	public void OnUpdate(float deltaTime)
	{
		TotalDeltaTime += deltaTime;
	}

	public SerializationResult Serialize(Serializer serializer)
	{
		return serializer.Int32("value", ref Value);
	}
}

/// Another test component for type differentiation.
class OtherTestComponent : IEntityComponent
{
	public String Name = new .() ~ delete _;

	public int32 SerializationVersion => 1;

	public void OnAttach(Entity entity) { }
	public void OnDetach() { }
	public void OnUpdate(float deltaTime) { }

	public SerializationResult Serialize(Serializer serializer)
	{
		return serializer.String("name", Name);
	}
}

class EntityTests
{
	[Test]
	public static void TestEntityCreation()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");
		let entity = scene.CreateEntity("TestEntity");

		Test.Assert(entity != null);
		Test.Assert(entity.Name == "TestEntity");
		Test.Assert(entity.Id.IsValid);
		Test.Assert(entity.Scene == scene);
	}

	[Test]
	public static void TestAddComponent()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");
		let entity = scene.CreateEntity("TestEntity");

		let component = new TestComponent();
		component.Value = 42;
		entity.AddComponent(component);

		Test.Assert(component.WasAttached);
		Test.Assert(entity.HasComponent<TestComponent>());
	}

	[Test]
	public static void TestGetComponent()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");
		let entity = scene.CreateEntity("TestEntity");

		let component = new TestComponent();
		component.Value = 123;
		entity.AddComponent(component);

		let retrieved = entity.GetComponent<TestComponent>();
		Test.Assert(retrieved != null);
		Test.Assert(retrieved.Value == 123);
	}

	[Test]
	public static void TestGetComponentNotFound()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");
		let entity = scene.CreateEntity("TestEntity");

		let retrieved = entity.GetComponent<TestComponent>();
		Test.Assert(retrieved == null);
	}

	[Test]
	public static void TestRemoveComponent()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");
		let entity = scene.CreateEntity("TestEntity");

		let component = new TestComponent();
		entity.AddComponent(component);

		Test.Assert(entity.HasComponent<TestComponent>());

		let removed = entity.RemoveComponent<TestComponent>();
		Test.Assert(removed);
		Test.Assert(!entity.HasComponent<TestComponent>());
	}

	[Test]
	public static void TestMultipleComponents()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");
		let entity = scene.CreateEntity("TestEntity");

		entity.AddComponent(new TestComponent());
		entity.AddComponent(new OtherTestComponent());

		Test.Assert(entity.HasComponent<TestComponent>());
		Test.Assert(entity.HasComponent<OtherTestComponent>());
		Test.Assert(entity.Components.Count == 2);
	}

	[Test]
	public static void TestEntityTransform()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");
		let entity = scene.CreateEntity("TestEntity");

		entity.Transform.SetPosition(.(10, 20, 30));

		Test.Assert(entity.Transform.Position.X == 10);
		Test.Assert(entity.Transform.Position.Y == 20);
		Test.Assert(entity.Transform.Position.Z == 30);
	}

	[Test]
	public static void TestComponentUpdate()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");
		let entity = scene.CreateEntity("TestEntity");

		let component = new TestComponent();
		entity.AddComponent(component);

		entity.Update(0.016f);

		Test.Assert(Math.Abs(component.TotalDeltaTime - 0.016f) < 0.0001f);
	}
}

/// Helper context for tests that doesn't require full initialization.
class TestContext : Context
{
	public this() : base(null, 1)
	{
	}
}
