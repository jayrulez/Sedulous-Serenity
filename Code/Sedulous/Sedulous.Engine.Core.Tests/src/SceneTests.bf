using System;
using Sedulous.Engine.Core;
using Sedulous.Serialization;

namespace Sedulous.Engine.Core.Tests;

/// Test scene component.
class TestSceneComponent : ISceneComponent
{
	public bool WasAttached = false;
	public bool WasDetached = false;
	public float TotalDeltaTime = 0;
	public SceneState LastOldState = .Unloaded;
	public SceneState LastNewState = .Unloaded;
	public int StateChangeCount = 0;

	public int32 SerializationVersion => 1;

	public void OnAttach(Scene scene)
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

	public void OnSceneStateChanged(SceneState oldState, SceneState newState)
	{
		LastOldState = oldState;
		LastNewState = newState;
		StateChangeCount++;
	}

	public SerializationResult Serialize(Serializer serializer)
	{
		return .Ok;
	}
}

class SceneTests
{
	[Test]
	public static void TestSceneCreation()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		Test.Assert(scene != null);
		Test.Assert(scene.Name == "TestScene");
		Test.Assert(scene.State == .Active);
	}

	[Test]
	public static void TestAddSceneComponent()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let component = new TestSceneComponent();
		scene.AddSceneComponent(component);

		Test.Assert(component.WasAttached);
		Test.Assert(scene.HasSceneComponent<TestSceneComponent>());
	}

	[Test]
	public static void TestGetSceneComponent()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let component = new TestSceneComponent();
		scene.AddSceneComponent(component);

		let retrieved = scene.GetSceneComponent<TestSceneComponent>();
		Test.Assert(retrieved == component);
	}

	[Test]
	public static void TestRemoveSceneComponent()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let component = new TestSceneComponent();
		scene.AddSceneComponent(component);

		let removed = scene.RemoveSceneComponent<TestSceneComponent>();
		Test.Assert(removed);
		Test.Assert(!scene.HasSceneComponent<TestSceneComponent>());
	}

	[Test]
	public static void TestSceneComponentSingleton()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let component1 = new TestSceneComponent();
		let component2 = new TestSceneComponent();

		scene.AddSceneComponent(component1);
		scene.AddSceneComponent(component2);

		// Should only have one - second replaces first
		// Note: component1 is deleted when replaced, so we can't check WasDetached on it
		let retrieved = scene.GetSceneComponent<TestSceneComponent>();
		Test.Assert(retrieved == component2);
	}

	[Test]
	public static void TestSceneStateChange()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let component = new TestSceneComponent();
		scene.AddSceneComponent(component);

		scene.SetState(.Paused);

		Test.Assert(scene.State == .Paused);
		Test.Assert(component.LastOldState == .Active);
		Test.Assert(component.LastNewState == .Paused);
	}

	[Test]
	public static void TestSceneUpdate()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let component = new TestSceneComponent();
		scene.AddSceneComponent(component);

		scene.Update(0.016f);

		Test.Assert(Math.Abs(component.TotalDeltaTime - 0.016f) < 0.0001f);
	}

	[Test]
	public static void TestSceneUpdateWhenPaused()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let component = new TestSceneComponent();
		scene.AddSceneComponent(component);

		scene.SetState(.Paused);
		scene.Update(0.016f);

		// Should not update when paused
		Test.Assert(component.TotalDeltaTime == 0);
	}

	[Test]
	public static void TestCreateEntity()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let entity = scene.CreateEntity("TestEntity");

		Test.Assert(entity != null);
		Test.Assert(entity.Scene == scene);
	}

	[Test]
	public static void TestDestroyEntity()
	{
		let context = scope TestContext();
		let scene = context.SceneManager.CreateScene("TestScene");

		let entity = scene.CreateEntity("TestEntity");
		let id = entity.Id;

		let destroyed = scene.DestroyEntity(id);
		Test.Assert(destroyed);
		Test.Assert(scene.GetEntity(id) == null);
	}
}
