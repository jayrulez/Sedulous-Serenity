namespace Sedulous.Framework.Core.Tests;

using System;
using Sedulous.Framework.Core.Scenes;

/// Test module that tracks lifecycle calls.
class TestModule : SceneModule
{
	public int BeginFrameCount = 0;
	public int UpdateCount = 0;
	public int EndFrameCount = 0;
	public int DestroyedEntityCount = 0;
	public int SceneCreateCount = 0;
	public int SceneDestroyCount = 0;
	public SceneState LastOldState = .Unloaded;
	public SceneState LastNewState = .Unloaded;
	public float LastDeltaTime = 0;

	public override void OnSceneCreate(Scene scene)
	{
		SceneCreateCount++;
	}

	public override void OnSceneDestroy(Scene scene)
	{
		SceneDestroyCount++;
	}

	public override void OnBeginFrame(Scene scene, float deltaTime)
	{
		BeginFrameCount++;
		LastDeltaTime = deltaTime;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		UpdateCount++;
	}

	public override void OnEndFrame(Scene scene)
	{
		EndFrameCount++;
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		DestroyedEntityCount++;
	}

	public override void OnSceneStateChanged(Scene scene, SceneState oldState, SceneState newState)
	{
		LastOldState = oldState;
		LastNewState = newState;
	}
}

class SceneModuleTests
{
	[Test]
	public static void TestModuleOnSceneCreate()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new TestModule();
		scene.AddModule(module);

		Test.Assert(module.SceneCreateCount == 1);
	}

	[Test]
	public static void TestModuleOnSceneDestroy()
	{
		let scene = new Scene("Test");
		let module = new TestModule();
		scene.AddModule(module);

		scene.Dispose();
		// Check before delete - module is deleted when scene is deleted
		Test.Assert(module.SceneDestroyCount == 1);
		delete scene;
	}

	[Test]
	public static void TestModuleLifecycleDuringUpdate()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new TestModule();
		scene.AddModule(module);
		scene.SetState(.Active);

		scene.Update(0.016f);

		Test.Assert(module.BeginFrameCount == 1);
		Test.Assert(module.UpdateCount == 1);
		Test.Assert(module.EndFrameCount == 1);
		Test.Assert(Math.Abs(module.LastDeltaTime - 0.016f) < 0.0001f);
	}

	[Test]
	public static void TestModuleMultipleFrames()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new TestModule();
		scene.AddModule(module);
		scene.SetState(.Active);

		scene.Update(0.016f);
		scene.Update(0.016f);
		scene.Update(0.016f);

		Test.Assert(module.BeginFrameCount == 3);
		Test.Assert(module.UpdateCount == 3);
		Test.Assert(module.EndFrameCount == 3);
	}

	[Test]
	public static void TestModuleNotUpdatedWhenPaused()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new TestModule();
		scene.AddModule(module);
		scene.SetState(.Paused);

		scene.Update(0.016f);

		Test.Assert(module.UpdateCount == 0);
	}

	[Test]
	public static void TestModuleNotifiedOnEntityDestruction()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new TestModule();
		scene.AddModule(module);

		let entity = scene.CreateEntity();
		scene.DestroyEntity(entity);

		Test.Assert(module.DestroyedEntityCount == 1);
	}

	[Test]
	public static void TestModuleStateChange()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new TestModule();
		scene.AddModule(module);

		scene.SetState(.Active);

		Test.Assert(module.LastOldState == .Unloaded);
		Test.Assert(module.LastNewState == .Active);
	}

	[Test]
	public static void TestGetModule()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new TestModule();
		scene.AddModule(module);

		let retrieved = scene.GetModule<TestModule>();
		Test.Assert(retrieved == module);
	}

	[Test]
	public static void TestRemoveModule()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new TestModule();
		scene.AddModule(module);

		let result = scene.RemoveModule<TestModule>();
		Test.Assert(result);

		let retrieved = scene.GetModule<TestModule>();
		Test.Assert(retrieved == null);
	}

	[Test]
	public static void TestMultipleModulesUpdateOrder()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		// Track update order
		int[2] updateOrder = .(0, 0);
		int orderCounter = 0;

		let module1 = new OrderTrackingModule(0, &updateOrder, &orderCounter);
		let module2 = new OrderTrackingModule(1, &updateOrder, &orderCounter);

		scene.AddModule(module1);
		scene.AddModule(module2);
		scene.SetState(.Active);

		scene.Update(0.016f);

		// Modules should update in order they were added
		Test.Assert(updateOrder[0] == 1); // module1 updated first
		Test.Assert(updateOrder[1] == 2); // module2 updated second
	}
}

/// Helper module for tracking update order.
class OrderTrackingModule : SceneModule
{
	private int mIndex;
	private int[2]* mOrderArray;
	private int* mCounter;

	public this(int index, int[2]* orderArray, int* counter)
	{
		mIndex = index;
		mOrderArray = orderArray;
		mCounter = counter;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		(*mCounter)++;
		(*mOrderArray)[mIndex] = *mCounter;
	}
}
