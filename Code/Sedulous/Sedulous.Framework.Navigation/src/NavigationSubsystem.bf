namespace Sedulous.Framework.Navigation;

using System;
using System.Collections;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;

/// Navigation subsystem that manages per-scene navigation worlds.
/// Implements ISceneAware to automatically create NavigationSceneModule for each scene.
/// UpdateOrder = 50 ensures navigation runs after physics (UpdateOrder = 0).
public class NavigationSubsystem : Subsystem, ISceneAware
{
	/// Navigation runs after physics so agent positions respect physical constraints.
	public override int32 UpdateOrder => 50;

	private int32 mMaxAgents;
	private Dictionary<Scene, NavWorld> mSceneWorlds = new .() ~ delete _;

	/// Creates a NavigationSubsystem with default settings.
	public this(int32 maxAgents = 128)
	{
		mMaxAgents = maxAgents;
	}

	/// Gets or sets the max agents per scene world.
	public int32 MaxAgents
	{
		get => mMaxAgents;
		set => mMaxAgents = value;
	}

	/// Gets the NavWorld for a specific scene.
	public NavWorld GetNavWorld(Scene scene)
	{
		if (mSceneWorlds.TryGetValue(scene, let world))
			return world;
		return null;
	}

	// ==================== Subsystem Lifecycle ====================

	protected override void OnInit()
	{
	}

	protected override void OnShutdown()
	{
		for (let (scene, world) in mSceneWorlds)
			delete world;
		mSceneWorlds.Clear();
	}

	public override void Update(float deltaTime)
	{
		// Per-scene simulation is handled by NavigationSceneModule
	}

	// ==================== ISceneAware ====================

	public void OnSceneCreated(Scene scene)
	{
		let navWorld = new NavWorld(mMaxAgents);
		mSceneWorlds[scene] = navWorld;

		let module = new NavigationSceneModule(this, navWorld);
		scene.AddModule(module);
	}

	public void OnSceneDestroyed(Scene scene)
	{
		if (mSceneWorlds.TryGetValue(scene, let world))
		{
			mSceneWorlds.Remove(scene);
			delete world;
		}
	}
}
