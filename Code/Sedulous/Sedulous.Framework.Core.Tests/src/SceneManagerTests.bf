namespace Sedulous.Framework.Core.Tests;

using System;
using Sedulous.Framework.Core.Scenes;

class SceneManagerTests
{
	[Test]
	public static void TestCreateScene()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene = manager.CreateScene("TestScene");

		Test.Assert(scene != null);
		Test.Assert(scene.Name == "TestScene");
		Test.Assert(scene.State == .Active);
		Test.Assert(manager.SceneCount == 1);
	}

	[Test]
	public static void TestCreateMultipleScenes()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene1 = manager.CreateScene("Scene1");
		let scene2 = manager.CreateScene("Scene2");
		let scene3 = manager.CreateScene("Scene3");

		Test.Assert(manager.SceneCount == 3);
		Test.Assert(scene1.Name == "Scene1");
		Test.Assert(scene2.Name == "Scene2");
		Test.Assert(scene3.Name == "Scene3");
	}

	[Test]
	public static void TestGetSceneByName()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene = manager.CreateScene("MyScene");
		let retrieved = manager.GetScene("MyScene");

		Test.Assert(retrieved == scene);
	}

	[Test]
	public static void TestGetSceneByNameNotFound()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let retrieved = manager.GetScene("NonExistent");

		Test.Assert(retrieved == null);
	}

	[Test]
	public static void TestGetSceneByIndex()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene1 = manager.CreateScene("Scene1");
		let scene2 = manager.CreateScene("Scene2");

		Test.Assert(manager.GetSceneAt(0) == scene1);
		Test.Assert(manager.GetSceneAt(1) == scene2);
		Test.Assert(manager.GetSceneAt(2) == null);
		Test.Assert(manager.GetSceneAt(-1) == null);
	}

	[Test]
	public static void TestSetActiveScene()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene1 = manager.CreateScene("Scene1");
		let scene2 = manager.CreateScene("Scene2");

		manager.SetActiveScene(scene1);
		Test.Assert(manager.ActiveScene == scene1);

		manager.SetActiveScene(scene2);
		Test.Assert(manager.ActiveScene == scene2);
		Test.Assert(scene1.State == .Paused);
		Test.Assert(scene2.State == .Active);
	}

	[Test]
	public static void TestSetActiveSceneByName()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene1 = manager.CreateScene("Scene1");
		let scene2 = manager.CreateScene("Scene2");

		manager.SetActiveScene("Scene1");
		Test.Assert(manager.ActiveScene == scene1);

		manager.SetActiveScene("Scene2");
		Test.Assert(manager.ActiveScene == scene2);
	}

	[Test]
	public static void TestUnloadScene()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene = manager.CreateScene("TestScene");
		Test.Assert(manager.SceneCount == 1);

		manager.UnloadScene(scene);

		Test.Assert(manager.SceneCount == 0);
		Test.Assert(manager.GetScene("TestScene") == null);
	}

	[Test]
	public static void TestUnloadSceneByName()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		manager.CreateScene("TestScene");
		Test.Assert(manager.SceneCount == 1);

		let result = manager.UnloadScene("TestScene");

		Test.Assert(result);
		Test.Assert(manager.SceneCount == 0);
	}

	[Test]
	public static void TestUnloadActiveScene()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene = manager.CreateScene("TestScene");
		manager.SetActiveScene(scene);

		manager.UnloadScene(scene);

		Test.Assert(manager.ActiveScene == null);
		Test.Assert(manager.SceneCount == 0);
	}

	[Test]
	public static void TestUnloadAllScenes()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		manager.CreateScene("Scene1");
		manager.CreateScene("Scene2");
		manager.CreateScene("Scene3");

		Test.Assert(manager.SceneCount == 3);

		manager.UnloadAllScenes();

		Test.Assert(manager.SceneCount == 0);
		Test.Assert(manager.ActiveScene == null);
	}

	[Test]
	public static void TestHasScene()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		manager.CreateScene("TestScene");

		Test.Assert(manager.HasScene("TestScene"));
		Test.Assert(!manager.HasScene("OtherScene"));
	}

	[Test]
	public static void TestUpdateActiveScene()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene = manager.CreateScene("TestScene");
		let module = new TestModule();
		scene.AddModule(module);

		manager.SetActiveScene(scene);
		manager.Update(0.016f);

		Test.Assert(module.UpdateCount == 1);
	}

	[Test]
	public static void TestUpdateNoActiveScene()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		// Create scene but don't set it as the manager's active scene
		let scene = manager.CreateScene("TestScene");
		let module = new TestModule();
		scene.AddModule(module);

		// Manager.Update only updates mActiveScene, which is null here
		// So this should not crash and module should NOT be updated
		manager.Update(0.016f);

		Test.Assert(module.UpdateCount == 0);
	}

	[Test]
	public static void TestUpdateAll()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		let scene1 = manager.CreateScene("Scene1");
		let scene2 = manager.CreateScene("Scene2");

		let module1 = new TestModule();
		let module2 = new TestModule();

		scene1.AddModule(module1);
		scene2.AddModule(module2);

		// Both scenes are Active (created that way)
		manager.UpdateAll(0.016f);

		Test.Assert(module1.UpdateCount == 1);
		Test.Assert(module2.UpdateCount == 1);
	}

	[Test]
	public static void TestSceneLoadedEvent()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		Scene loadedScene = null;
		manager.OnSceneLoaded(new [&] (scene) => {
			loadedScene = scene;
		});

		let scene = manager.CreateScene("TestScene");

		Test.Assert(loadedScene == scene);
	}

	[Test]
	public static void TestSceneUnloadedEvent()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		Scene unloadedScene = null;
		manager.OnSceneUnloaded(new [&] (scene) => {
			unloadedScene = scene;
		});

		let scene = manager.CreateScene("TestScene");
		manager.UnloadScene(scene);

		// Can't compare directly since scene is deleted, but we can check it was called
		Test.Assert(unloadedScene != null);
	}

	[Test]
	public static void TestIterateScenes()
	{
		let manager = scope SceneManager();
		defer manager.Dispose();

		manager.CreateScene("Scene1");
		manager.CreateScene("Scene2");
		manager.CreateScene("Scene3");

		int count = 0;
		for (let scene in manager)
		{
			count++;
			Test.Assert(scene != null);
		}

		Test.Assert(count == 3);
	}
}
