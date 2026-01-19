namespace Sedulous.Framework.Scenes;

using System;
using System.Collections;
using Sedulous.Foundation.Core;

/// Delegate for scene lifecycle events.
public delegate void SceneEventDelegate(Scene scene);

/// Manages multiple scenes and scene transitions.
/// Provides a central point for creating, loading, unloading, and updating scenes.
public class SceneManager : IDisposable
{
	private List<Scene> mScenes = new .() ~ DeleteContainerAndItems!(_);
	private Scene mActiveScene = null;

	// Events
	private EventAccessor<SceneEventDelegate> mOnSceneLoaded = new .() ~ delete _;
	private EventAccessor<SceneEventDelegate> mOnSceneUnloaded = new .() ~ delete _;

	/// Gets the currently active scene.
	public Scene ActiveScene => mActiveScene;

	/// Gets the number of loaded scenes.
	public int SceneCount => mScenes.Count;

	/// Subscribe to scene loaded event.
	public void OnSceneLoaded(SceneEventDelegate handler)
	{
		mOnSceneLoaded.Subscribe(handler);
	}

	/// Unsubscribe from scene loaded event.
	public void OffSceneLoaded(SceneEventDelegate handler)
	{
		mOnSceneLoaded.Unsubscribe(handler);
	}

	/// Subscribe to scene unloaded event.
	public void OnSceneUnloaded(SceneEventDelegate handler)
	{
		mOnSceneUnloaded.Subscribe(handler);
	}

	/// Unsubscribe from scene unloaded event.
	public void OffSceneUnloaded(SceneEventDelegate handler)
	{
		mOnSceneUnloaded.Unsubscribe(handler);
	}

	/// Creates a new empty scene and adds it to the manager.
	/// The scene is set to Active state automatically.
	public Scene CreateScene(StringView name)
	{
		let scene = new Scene(name);
		mScenes.Add(scene);
		scene.SetState(.Loading);
		scene.SetState(.Active);
		mOnSceneLoaded.[Friend]Invoke(scene);
		return scene;
	}

	/// Gets a scene by name.
	public Scene GetScene(StringView name)
	{
		for (let scene in mScenes)
		{
			if (scene.Name == name)
				return scene;
		}
		return null;
	}

	/// Gets a scene by index.
	public Scene GetSceneAt(int index)
	{
		if (index < 0 || index >= mScenes.Count)
			return null;
		return mScenes[index];
	}

	/// Sets the active scene.
	/// The previous active scene is paused, and the new scene is set to Active.
	public void SetActiveScene(Scene scene)
	{
		if (mActiveScene == scene)
			return;

		// Pause old active scene
		if (mActiveScene != null && mActiveScene.State == .Active)
			mActiveScene.SetState(.Paused);

		mActiveScene = scene;

		// Activate new scene
		if (mActiveScene != null && mActiveScene.State != .Active)
			mActiveScene.SetState(.Active);
	}

	/// Sets the active scene by name.
	public bool SetActiveScene(StringView name)
	{
		let scene = GetScene(name);
		if (scene == null)
			return false;
		SetActiveScene(scene);
		return true;
	}

	/// Unloads a scene and removes it from the manager.
	public void UnloadScene(Scene scene)
	{
		if (!mScenes.Contains(scene))
			return;

		// Clear active scene reference if needed
		if (scene == mActiveScene)
			mActiveScene = null;

		// Transition states
		scene.SetState(.Unloading);
		scene.SetState(.Unloaded);

		// Fire event
		mOnSceneUnloaded.[Friend]Invoke(scene);

		// Remove and dispose
		mScenes.Remove(scene);
		scene.Dispose();
		delete scene;
	}

	/// Unloads a scene by name.
	public bool UnloadScene(StringView name)
	{
		let scene = GetScene(name);
		if (scene == null)
			return false;
		UnloadScene(scene);
		return true;
	}

	/// Unloads all scenes.
	public void UnloadAllScenes()
	{
		// Copy list since we're modifying it
		let scenesToUnload = scope List<Scene>();
		scenesToUnload.AddRange(mScenes);

		for (let scene in scenesToUnload)
			UnloadScene(scene);
	}

	/// Updates the active scene.
	public void Update(float deltaTime)
	{
		if (mActiveScene != null && mActiveScene.State == .Active)
			mActiveScene.Update(deltaTime);
	}

	/// Updates all active and non-paused scenes.
	/// Useful for additive scene setups.
	public void UpdateAll(float deltaTime)
	{
		for (let scene in mScenes)
		{
			if (scene.State == .Active)
				scene.Update(deltaTime);
		}
	}

	/// Checks if a scene with the given name exists.
	public bool HasScene(StringView name)
	{
		return GetScene(name) != null;
	}

	/// Gets an enumerator over all loaded scenes.
	public List<Scene>.Enumerator GetEnumerator()
	{
		return mScenes.GetEnumerator();
	}

	/// Disposes the scene manager and all scenes.
	public void Dispose()
	{
		UnloadAllScenes();
	}
}
