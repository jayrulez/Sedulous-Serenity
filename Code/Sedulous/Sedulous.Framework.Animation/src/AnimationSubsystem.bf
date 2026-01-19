namespace Sedulous.Framework.Animation;

using System;
using System.Collections;
using Sedulous.Animation;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;

/// Animation subsystem that manages skeletal and property animations.
/// Integrates with Sedulous.Animation.
/// Implements ISceneAware to automatically create AnimationSceneModule for each scene.
public class AnimationSubsystem : Subsystem, ISceneAware
{
	/// Animation updates after physics, before rendering.
	public override int32 UpdateOrder => 100;

	private AnimationSystem mAnimationSystem ~ delete _;

	// ==================== Construction ====================

	public this()
	{
		mAnimationSystem = new AnimationSystem();
	}

	// ==================== Properties ====================

	/// Gets the underlying animation system.
	public AnimationSystem AnimationSystem => mAnimationSystem;

	// ==================== Subsystem Lifecycle ====================

	protected override void OnInit()
	{
	}

	protected override void OnShutdown()
	{
	}

	public override void Update(float deltaTime)
	{
		// Per-scene animation updates are handled by AnimationSceneModule
	}

	// ==================== ISceneAware ====================

	public void OnSceneCreated(Scene scene)
	{
		let module = new AnimationSceneModule(this);
		scene.AddModule(module);
	}

	public void OnSceneDestroyed(Scene scene)
	{
		// Scene will clean up its modules
	}
}
