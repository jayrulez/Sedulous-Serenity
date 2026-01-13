using System;
using System.Collections;
using Sedulous.Foundation.Core;

namespace Sedulous.Engine.Core;

/// Delegate for scene lifecycle events.
delegate void SceneEventDelegate(Scene scene);

/// Manages scene lifecycle and transitions.
class SceneManager
{
	private ComponentRegistry mComponentRegistry;
	private Context mContext;
	private Scene mActiveScene;
	private List<Scene> mScenes = new .() ~ DeleteContainerAndItems!(_);
	private EventAccessor<SceneEventDelegate> mOnSceneLoaded = new .() ~ delete _;
	private EventAccessor<SceneEventDelegate> mOnSceneUnloaded = new .() ~ delete _;

	/// Gets the currently active scene.
	public Scene ActiveScene => mActiveScene;

	/// Gets the number of loaded scenes.
	public int SceneCount => mScenes.Count;

	/// Event fired when a scene finishes loading.
	public EventAccessor<SceneEventDelegate> OnSceneLoaded => mOnSceneLoaded;

	/// Event fired when a scene is unloaded.
	public EventAccessor<SceneEventDelegate> OnSceneUnloaded => mOnSceneUnloaded;

	/// Creates a new SceneManager.
	public this(ComponentRegistry componentRegistry, Context context = null)
	{
		mComponentRegistry = componentRegistry;
		mContext = context;
	}

	/// Creates a new empty scene.
	/// Services will be notified via OnSceneCreated after the scene is in Loading state.
	public Scene CreateScene(StringView name)
	{
		let scene = new Scene(name, mComponentRegistry);
		scene.[Friend]mContext = mContext;
		mScenes.Add(scene);
		scene.SetState(.Loading);

		// Notify services to add their scene components
		if (mContext != null && mContext.IsRunning)
			mContext.[Friend]NotifyServicesSceneCreated(scene);

		scene.SetState(.Active);
		mOnSceneLoaded.[Friend]Invoke(scene);
		return scene;
	}

	/// Adds an existing scene to the manager.
	public void AddScene(Scene scene)
	{
		mScenes.Add(scene);
		mOnSceneLoaded.[Friend]Invoke(scene);
	}

	/// Gets a scene by name.
	/// Returns null if not found.
	public Scene GetScene(StringView name)
	{
		for (let scene in mScenes)
		{
			if (scene.Name == name)
				return scene;
		}
		return null;
	}

	/// Sets the active scene.
	/// The active scene is updated each frame.
	public void SetActiveScene(Scene scene)
	{
		if (mActiveScene == scene)
			return;

		if (mActiveScene != null)
			mActiveScene.SetState(.Paused);

		mActiveScene = scene;

		if (mActiveScene != null)
			mActiveScene.SetState(.Active);
	}

	/// Unloads a specific scene.
	/// Services will be notified via OnSceneDestroyed before the scene is deleted.
	///
	/// TODO: The current lifecycle has a design issue:
	///   - OnSceneDestroyed is called BEFORE the scene is deleted
	///   - Services may delete resources (e.g., physics world) in OnSceneDestroyed
	///   - But entity components are cleaned up DURING scene deletion (after OnSceneDestroyed)
	///   - Entity components may try to access already-deleted service resources
	///
	/// A proper lifecycle should have distinct phases:
	///   1. OnSceneWillUnload - Services prepare, can still access scene
	///   2. Scene.Cleanup() - Entities and components are cleaned up
	///   3. OnSceneDidUnload - Services delete resources safely
	///
	/// For now, services must handle this by invalidating references before deletion.
	public void UnloadScene(Scene scene)
	{
		if (!mScenes.Contains(scene))
			return;

		if (scene == mActiveScene)
			mActiveScene = null;

		scene.SetState(.Unloading);

		// Notify services before destruction
		// WARNING: Services should NOT delete resources here that entity components may still need.
		// See TODO above for proper lifecycle design.
		if (mContext != null)
			mContext.[Friend]NotifyServicesSceneDestroyed(scene);

		scene.SetState(.Unloaded);

		mOnSceneUnloaded.[Friend]Invoke(scene);

		mScenes.Remove(scene);
		delete scene;
	}

	/// Unloads all scenes.
	public void UnloadAllScenes()
	{
		// Make a copy since we're modifying the list
		List<Scene> scenesToUnload = scope .();
		scenesToUnload.AddRange(mScenes);

		for (let scene in scenesToUnload)
		{
			UnloadScene(scene);
		}
	}

	/// Updates the active scene.
	public void Update(float deltaTime)
	{
		if (mActiveScene != null && mActiveScene.State == .Active)
		{
			mActiveScene.Update(deltaTime);
		}
	}

	/// Gets an enumerator over all loaded scenes.
	public List<Scene>.Enumerator GetEnumerator()
	{
		return mScenes.GetEnumerator();
	}
}
