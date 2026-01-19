namespace Sedulous.Framework.UI;

using System;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;

/// UI subsystem for managing user interface.
/// Implements ISceneAware to automatically create UISceneModule for each scene.
public class UISubsystem : Subsystem, ISceneAware
{
	/// UI updates after game logic but before rendering.
	public override int32 UpdateOrder => 400;

	/// Called during the main update phase for UI updates.
	public override void Update(float deltaTime)
	{
		// Per-scene UI updates are handled by UISceneModule
	}

	/// Override to perform UI subsystem initialization.
	protected override void OnInit()
	{
		// TODO: Initialize UI context (Sedulous.UI integration later)
	}

	/// Override to perform UI subsystem shutdown.
	protected override void OnShutdown()
	{
		// TODO: Cleanup UI resources
	}

	// ==================== ISceneAware ====================

	public void OnSceneCreated(Scene scene)
	{
		let module = new UISceneModule(this);
		scene.AddModule(module);
	}

	public void OnSceneDestroyed(Scene scene)
	{
		// Scene will clean up its modules
	}
}
