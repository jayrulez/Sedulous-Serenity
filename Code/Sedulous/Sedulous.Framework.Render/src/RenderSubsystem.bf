namespace Sedulous.Framework.Render;

using System;
using System.Collections;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Render;
using Sedulous.Textures.Resources;

/// Render subsystem that manages rendering and integrates with Sedulous.Render.
/// RenderSystem is injected via constructor.
/// Implements ISceneAware to automatically create RenderSceneModule for each scene.
public class RenderSubsystem : Subsystem, ISceneAware
{
	/// Render runs late in the frame.
	public override int32 UpdateOrder => 500;

	private RenderSystem mRenderSystem;
	private bool mOwnsRenderSystem;

	// Track render worlds per scene
	private Dictionary<Scene, RenderWorld> mSceneWorlds = new .() ~ delete _;

	// Resource managers
	private StaticMeshResourceManager mStaticMeshManager;
	private SkinnedMeshResourceManager mSkinnedMeshManager;
	private TextureResourceManager mTextureManager;

	// ==================== Construction ====================

	/// Creates a RenderSubsystem with the given render system.
	/// @param renderSystem The render system (should already be initialized).
	/// @param takeOwnership If true, the subsystem will dispose the render system on shutdown.
	public this(RenderSystem renderSystem, bool takeOwnership = true)
	{
		mRenderSystem = renderSystem;
		mOwnsRenderSystem = takeOwnership;
	}

	// ==================== Properties ====================

	/// Gets the underlying render system.
	public RenderSystem RenderSystem => mRenderSystem;

	/// Gets the static mesh resource manager.
	public StaticMeshResourceManager StaticMeshManager => mStaticMeshManager;

	/// Gets the skinned mesh resource manager.
	public SkinnedMeshResourceManager SkinnedMeshManager => mSkinnedMeshManager;

	/// Gets the texture resource manager.
	public TextureResourceManager TextureManager => mTextureManager;

	// ==================== World Access ====================

	/// Gets the render world for a specific scene.
	public RenderWorld GetWorld(Scene scene)
	{
		if (mSceneWorlds.TryGetValue(scene, let world))
			return world;
		return null;
	}

	// ==================== Subsystem Lifecycle ====================

	protected override void OnInit()
	{
		// Create and register resource managers with the resource system
		mStaticMeshManager = new StaticMeshResourceManager();
		mSkinnedMeshManager = new SkinnedMeshResourceManager();
		mTextureManager = new TextureResourceManager();

		Context.Resources.AddResourceManager(mStaticMeshManager);
		Context.Resources.AddResourceManager(mSkinnedMeshManager);
		Context.Resources.AddResourceManager(mTextureManager);
	}

	protected override void OnShutdown()
	{
		// Clean up all render worlds
		for (let (scene, world) in mSceneWorlds)
		{
			world.Dispose();
			delete world;
		}
		mSceneWorlds.Clear();

		// Unregister and clean up resource managers
		if (mStaticMeshManager != null)
		{
			Context.Resources.RemoveResourceManager(mStaticMeshManager);
			delete mStaticMeshManager;
			mStaticMeshManager = null;
		}
		if (mSkinnedMeshManager != null)
		{
			Context.Resources.RemoveResourceManager(mSkinnedMeshManager);
			delete mSkinnedMeshManager;
			mSkinnedMeshManager = null;
		}
		if (mTextureManager != null)
		{
			Context.Resources.RemoveResourceManager(mTextureManager);
			delete mTextureManager;
			mTextureManager = null;
		}

		if (mOwnsRenderSystem && mRenderSystem != null)
		{
			mRenderSystem.Dispose();
			delete mRenderSystem;
		}
		mRenderSystem = null;
	}

	public override void EndFrame()
	{
		// Per-scene rendering is handled by RenderSceneModule
	}

	// ==================== ISceneAware ====================

	public void OnSceneCreated(Scene scene)
	{
		if (mRenderSystem == null)
			return;

		// Create render world for this scene
		let world = new RenderWorld();
		mSceneWorlds[scene] = world;

		// Create and add scene module
		let module = new RenderSceneModule(this, world);
		scene.AddModule(module);
	}

	public void OnSceneDestroyed(Scene scene)
	{
		// Clean up render world for this scene
		if (mSceneWorlds.TryGetValue(scene, let world))
		{
			mSceneWorlds.Remove(scene);
			world.Dispose();
			delete world;
		}
	}
}
