namespace Sedulous.Framework.Animation;

using System;
using System.Collections;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
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

	// Resource managers
	private SkeletonResourceManager mSkeletonManager;
	private AnimationClipResourceManager mAnimationClipManager;

	// ==================== Construction ====================

	public this()
	{
		mAnimationSystem = new AnimationSystem();
	}

	// ==================== Properties ====================

	/// Gets the underlying animation system.
	public AnimationSystem AnimationSystem => mAnimationSystem;

	/// Gets the skeleton resource manager.
	public SkeletonResourceManager SkeletonManager => mSkeletonManager;

	/// Gets the animation clip resource manager.
	public AnimationClipResourceManager AnimationClipManager => mAnimationClipManager;

	// ==================== Subsystem Lifecycle ====================

	protected override void OnInit()
	{
		// Create and register resource managers with the resource system
		mSkeletonManager = new SkeletonResourceManager();
		mAnimationClipManager = new AnimationClipResourceManager();

		Context.Resources.AddResourceManager(mSkeletonManager);
		Context.Resources.AddResourceManager(mAnimationClipManager);
	}

	protected override void OnShutdown()
	{
		// Unregister and clean up resource managers
		if (mSkeletonManager != null)
		{
			Context.Resources.RemoveResourceManager(mSkeletonManager);
			delete mSkeletonManager;
			mSkeletonManager = null;
		}
		if (mAnimationClipManager != null)
		{
			Context.Resources.RemoveResourceManager(mAnimationClipManager);
			delete mAnimationClipManager;
			mAnimationClipManager = null;
		}
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
