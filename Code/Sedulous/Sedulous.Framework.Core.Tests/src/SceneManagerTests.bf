using System;
using Sedulous.Framework.Core;

namespace Sedulous.Framework.Core.Tests;

class SceneManagerTests
{
	[Test]
	public static void TestCreateScene()
	{
		let context = scope TestContext();

		let scene = context.SceneManager.CreateScene("TestScene");
		Test.Assert(scene != null);
		Test.Assert(scene.Name == "TestScene");
		Test.Assert(context.SceneManager.SceneCount == 1);
	}

	[Test]
	public static void TestGetScene()
	{
		let context = scope TestContext();

		let scene = context.SceneManager.CreateScene("TestScene");
		let retrieved = context.SceneManager.GetScene("TestScene");

		Test.Assert(retrieved == scene);
	}

	[Test]
	public static void TestGetSceneNotFound()
	{
		let context = scope TestContext();

		let retrieved = context.SceneManager.GetScene("NonExistent");
		Test.Assert(retrieved == null);
	}

	[Test]
	public static void TestSetActiveScene()
	{
		let context = scope TestContext();

		let scene1 = context.SceneManager.CreateScene("Scene1");
		let scene2 = context.SceneManager.CreateScene("Scene2");

		context.SceneManager.SetActiveScene(scene1);
		Test.Assert(context.SceneManager.ActiveScene == scene1);
		Test.Assert(scene1.State == .Active);

		context.SceneManager.SetActiveScene(scene2);
		Test.Assert(context.SceneManager.ActiveScene == scene2);
		Test.Assert(scene1.State == .Paused);
		Test.Assert(scene2.State == .Active);
	}

	[Test]
	public static void TestUnloadScene()
	{
		let context = scope TestContext();

		let scene = context.SceneManager.CreateScene("TestScene");
		Test.Assert(context.SceneManager.SceneCount == 1);

		context.SceneManager.UnloadScene(scene);
		Test.Assert(context.SceneManager.SceneCount == 0);
	}

	[Test]
	public static void TestUnloadActiveScene()
	{
		let context = scope TestContext();

		let scene = context.SceneManager.CreateScene("TestScene");
		context.SceneManager.SetActiveScene(scene);

		context.SceneManager.UnloadScene(scene);
		Test.Assert(context.SceneManager.ActiveScene == null);
	}

	[Test]
	public static void TestUnloadAllScenes()
	{
		let context = scope TestContext();

		context.SceneManager.CreateScene("Scene1");
		context.SceneManager.CreateScene("Scene2");
		context.SceneManager.CreateScene("Scene3");

		Test.Assert(context.SceneManager.SceneCount == 3);

		context.SceneManager.UnloadAllScenes();
		Test.Assert(context.SceneManager.SceneCount == 0);
	}

	[Test]
	public static void TestSceneLoadedEvent()
	{
		let context = scope TestContext();

		Scene loadedScene = null;
		context.SceneManager.OnSceneLoaded.Subscribe(new [&](scene) => {
			loadedScene = scene;
		});

		let scene = context.SceneManager.CreateScene("TestScene");
		Test.Assert(loadedScene == scene);
	}

	[Test]
	public static void TestSceneUnloadedEvent()
	{
		let context = scope TestContext();

		String unloadedSceneName = scope .();
		bool eventFired = false;
		context.SceneManager.OnSceneUnloaded.Subscribe(new [&](scene) => {
			unloadedSceneName.Set(scene.Name);
			eventFired = true;
		});

		let scene = context.SceneManager.CreateScene("TestScene");
		context.SceneManager.UnloadScene(scene);

		// Scene is deleted after UnloadScene, so we capture the name in the event
		Test.Assert(eventFired);
		Test.Assert(unloadedSceneName == "TestScene");
	}

	[Test]
	public static void TestMultipleScenes()
	{
		let context = scope TestContext();

		let scene1 = context.SceneManager.CreateScene("Scene1");
		let scene2 = context.SceneManager.CreateScene("Scene2");

		Test.Assert(context.SceneManager.SceneCount == 2);

		let retrieved1 = context.SceneManager.GetScene("Scene1");
		let retrieved2 = context.SceneManager.GetScene("Scene2");

		Test.Assert(retrieved1 == scene1);
		Test.Assert(retrieved2 == scene2);
	}

	[Test]
	public static void TestEnumerator()
	{
		let context = scope TestContext();

		context.SceneManager.CreateScene("Scene1");
		context.SceneManager.CreateScene("Scene2");
		context.SceneManager.CreateScene("Scene3");

		int count = 0;
		for (let scene in context.SceneManager)
		{
			Test.Assert(scene != null);
			count++;
		}

		Test.Assert(count == 3);
	}
}
