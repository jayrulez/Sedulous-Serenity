namespace Sedulous.Framework.Scenes;

using System;
using System.Collections;
using Sedulous.Framework.Core;
using Sedulous.Profiler;

/// Subsystem that manages scenes and notifies other subsystems of scene lifecycle events.
/// Register this with Context to enable scene support.
public class SceneSubsystem : Subsystem
{
	private SceneManager mSceneManager ~ delete _;

	/// Gets the scene manager.
	public SceneManager SceneManager => mSceneManager;

	/// Gets the currently active scene.
	public Scene ActiveScene => mSceneManager?.ActiveScene;

	/// Update order - scenes update early in the frame.
	public override int32 UpdateOrder => -500;

	/// Creates a new SceneSubsystem.
	public this()
	{
		mSceneManager = new SceneManager();
	}

	protected override void OnInit()
	{
		// Subscribe to scene events to notify other subsystems
		mSceneManager.OnSceneLoaded(new => HandleSceneLoaded);
		mSceneManager.OnSceneUnloaded(new => HandleSceneUnloaded);
	}

	protected override void OnShutdown()
	{
		// Unload all scenes before shutdown
		mSceneManager.UnloadAllScenes();
	}

	public override void FixedUpdate(float fixedDeltaTime)
	{
		using (SProfiler.Begin("Scene.FixedUpdate"))
			mSceneManager.FixedUpdate(fixedDeltaTime);
	}

	public override void Update(float deltaTime)
	{
		using (SProfiler.Begin("Scene.Update"))
			mSceneManager.Update(deltaTime);
	}

	/// Creates a new scene and notifies ISceneAware subsystems.
	public Scene CreateScene(StringView name)
	{
		return mSceneManager.CreateScene(name);
	}

	/// Gets a scene by name.
	public Scene GetScene(StringView name)
	{
		return mSceneManager.GetScene(name);
	}

	/// Sets the active scene.
	public void SetActiveScene(Scene scene)
	{
		mSceneManager.SetActiveScene(scene);
	}

	/// Sets the active scene by name.
	public bool SetActiveScene(StringView name)
	{
		return mSceneManager.SetActiveScene(name);
	}

	/// Unloads a scene.
	public void UnloadScene(Scene scene)
	{
		mSceneManager.UnloadScene(scene);
	}

	/// Unloads a scene by name.
	public bool UnloadScene(StringView name)
	{
		return mSceneManager.UnloadScene(name);
	}

	/// Handles scene loaded event - notifies ISceneAware subsystems.
	private void HandleSceneLoaded(Scene scene)
	{
		if (Context == null)
			return;

		for (let subsystem in Context.Subsystems)
		{
			if (let sceneAware = subsystem as ISceneAware)
				sceneAware.OnSceneCreated(scene);
		}
	}

	/// Handles scene unloaded event - notifies ISceneAware subsystems.
	private void HandleSceneUnloaded(Scene scene)
	{
		if (Context == null)
			return;

		for (let subsystem in Context.Subsystems)
		{
			if (let sceneAware = subsystem as ISceneAware)
				sceneAware.OnSceneDestroyed(scene);
		}
	}

	public override void Dispose()
	{
		// Unsubscribe from events
		if (mSceneManager != null)
		{
			mSceneManager.OffSceneLoaded(scope => HandleSceneLoaded);
			mSceneManager.OffSceneUnloaded(scope => HandleSceneUnloaded);
		}

		base.Dispose();
	}
}
