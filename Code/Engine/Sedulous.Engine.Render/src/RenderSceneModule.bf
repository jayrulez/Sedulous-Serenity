namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Core.Mathematics;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.RHI;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Textures.Resources;
using Sedulous.Imaging;

/// Scene module that manages render proxies and syncs entity transforms to the render world.
/// Created automatically by RenderSubsystem for each scene.
///
/// Component-specific storage and API are split into extension files:
///   RenderSceneModule.Mesh.bf, RenderSceneModule.Light.bf, RenderSceneModule.Camera.bf,
///   RenderSceneModule.Sprite.bf, RenderSceneModule.Decal.bf, RenderSceneModule.TrailEmitter.bf,
///   RenderSceneModule.ParticleEmitter.bf, RenderSceneModule.SkinnedMesh.bf
class RenderSceneModule : SceneModule
{
	private RenderSubsystem mSubsystem;
	private RenderWorld mWorld;
	private Scene mScene;

	// ==================== Data Providers ====================
	private List<IComponentDataProvider> mDataProviders ~ DeleteContainerAndItems!(_);

	public override void GetDataProviders(List<IComponentDataProvider> outProviders)
	{
		if (mDataProviders == null)
		{
			mDataProviders = new .();
			InitDataProviders();
		}
		outProviders.AddRange(mDataProviders);
	}

	// ==================== Shared Caches ====================

	// Cache: resource -> GPU handle (shared across entities using same resource)
	private Dictionary<TextureResource, GPUTextureHandle> mTextureCache = new .() ~ delete _;

	// Track loaded texture resource refs per entity (for releasing on destroy)
	private Dictionary<EntityId, List<TextureResource>> mEntityTextureRefs = new .() ~ { for (var kv in _) delete kv.value; delete _; };

	/// Creates a RenderSceneModule linked to the given subsystem and render world.
	public this(RenderSubsystem subsystem, RenderWorld world)
	{
		mSubsystem = subsystem;
		mWorld = world;
	}

	/// Gets the render subsystem.
	public RenderSubsystem Subsystem => mSubsystem;

	/// Gets the render world for this scene.
	public RenderWorld World => mWorld;

	// ==================== Scene Lifecycle ====================

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;

		// Register custom serializers for module-owned components
		scene.RegisterComponentSerializer(new MeshComponentSerializer());
		scene.RegisterComponentSerializer(new LightComponentSerializer());
		scene.RegisterComponentSerializer(new CameraComponentSerializer());
		scene.RegisterComponentSerializer(new SpriteComponentSerializer());
		scene.RegisterComponentSerializer(new DecalComponentSerializer());
		scene.RegisterComponentSerializer(new TrailEmitterComponentSerializer());
		scene.RegisterComponentSerializer(new ParticleEmitterComponentSerializer());
		scene.RegisterComponentSerializer(new SkinnedMeshComponentSerializer());

		// Apply render settings from scene (populated during deserialization, or defaults for new scenes)
		if (let settings = scene.GetModuleSettings<RenderModuleSettings>())
		{
			mWorld.AmbientColor = settings.AmbientColor;
			mWorld.AmbientIntensity = settings.AmbientIntensity;
			mWorld.Exposure = settings.Exposure;

			// Apply sky settings
			if (let skyFeature = mSubsystem.RenderSystem?.GetFeature<SkyFeature>())
			{
				skyFeature.Mode = settings.SkyMode;
				var skyParams = ref skyFeature.SkyParams;
				skyParams.SunDirection = settings.SunDirection;
				skyParams.SunIntensity = settings.SunIntensity;
				skyParams.SunColor = settings.SunColor;
				skyParams.AtmosphereDensity = settings.AtmosphereDensity;
				skyParams.ZenithColor = settings.ZenithColor;
				skyParams.HorizonColor = settings.HorizonColor;
				skyParams.GroundColor = settings.GroundColor;
				skyParams.SolidColor = settings.SolidSkyColor;
			}
		}
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// mWorld may be null if RenderSubsystem.OnShutdown() already ran
		// (subsystems shut down in reverse UpdateOrder: Render before Scenes).
		// When mWorld is valid, destroy proxies properly. Otherwise just release module-side data.

		DestroyAllMeshes();
		DestroyAllLights();
		DestroyAllCameras();
		DestroyAllSprites();
		DestroyAllDecals();
		DestroyAllTrailEmitters();
		DestroyAllParticleEmitters();
		DestroyAllSkinnedMeshes();

		// Release cached GPU textures
		let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
		let frameNumber = mSubsystem.RenderSystem?.FrameNumber ?? 0;

		if (gpuManager != null)
		{
			for (let handle in mTextureCache.Values)
				gpuManager.ReleaseTexture(handle, frameNumber);
		}

		// Release texture resource refs for all entities
		for (var kv in mEntityTextureRefs)
		{
			for (let texRes in kv.value)
				texRes.ReleaseRef();
			delete kv.value;
		}
		mEntityTextureRefs.Clear();
		mTextureCache.Clear();

		mWorld = null;
		mScene = null;
	}

	public override void PostUpdate(Scene scene, float deltaTime)
	{
		if (mScene == null || mWorld == null)
			return;

		// Process module-owned skinned mesh instances — resolve pending resources, sync materials, bones
		ResolveSkinnedMeshInstanceRefs();

		// Process module-owned mesh instances — resolve pending resources and sync to proxies
		ResolveMeshInstanceRefs();

		// Process module-owned sprite instances — resolve pending texture refs
		ResolveSpriteInstanceRefs();

		// Process module-owned decal instances — resolve pending texture refs
		ResolveDecalInstanceRefs();
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		if (mWorld == null)
			return;

		DestroyMesh(entity);
		DestroyLight(entity);
		DestroyCamera(entity);
		DestroySprite(entity);
		DestroyDecal(entity);
		DestroyTrailEmitter(entity);
		DestroyParticleEmitter(entity);
		DestroySkinnedMesh(entity);

		// Release texture resource refs loaded for this entity
		if (mEntityTextureRefs.TryGetValue(entity, let texList))
		{
			for (let texRes in texList)
				texRes.ReleaseRef();
			delete texList;
			mEntityTextureRefs.Remove(entity);
		}
	}

	public override void OnEntityTransformChanged(Scene scene, EntityId entity, in Matrix worldMatrix)
	{
		SyncMeshTransform(entity, worldMatrix);
		SyncLightTransform(entity, worldMatrix);
		SyncCameraTransform(entity, worldMatrix);
		SyncSpriteTransform(entity, worldMatrix);
		SyncDecalTransform(entity, worldMatrix);
		SyncTrailEmitterTransform(entity, worldMatrix);
		SyncParticleEmitterTransform(entity, worldMatrix);
		SyncSkinnedMeshTransform(entity, worldMatrix);
	}

	// ==================== Shared Helpers ====================

	/// Resolves texture references from a MaterialResource and sets them on a MaterialInstance.
	/// Loads each TextureResource via the ResourceSystem, uploads to GPU, and binds to the material.
	/// Tracks loaded texture refs per entity for cleanup on entity destroy.
	private void ResolveTextureRefs(EntityId entity, ResourceSystem resourceSystem, MaterialResource matResource, MaterialInstance matInstance)
	{
		let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
		if (gpuManager == null)
			return;

		for (var kv in matResource.TextureRefs)
		{
			let slotName = kv.key;
			let texRef = kv.value;

			if (!texRef.IsValid)
				continue;

			// Load the TextureResource via ResourceSystem (uses GUID → registry → file)
			// The returned handle has already called AddRef on the resource.
			if (resourceSystem.LoadByRef<TextureResource>(texRef) case .Ok(let texHandle))
			{
				let texResource = texHandle.Resource;
				if (texResource?.Image == null)
					continue;

				// Track the loaded resource ref for this entity (released on entity destroy)
				if (!mEntityTextureRefs.ContainsKey(entity))
					mEntityTextureRefs[entity] = new List<TextureResource>();
				mEntityTextureRefs[entity].Add(texResource);

				// Check texture cache first
				ITextureView view = null;
				if (mTextureCache.TryGetValue(texResource, var gpuHandle))
				{
					view = gpuManager.GetTextureView(gpuHandle);
				}
				else
				{
					// Upload image to GPU
					let image = texResource.Image;
					let texData = TextureData.FromImage(image);

					if (gpuManager.UploadTexture(texData) case .Ok(let newHandle))
					{
						mTextureCache[texResource] = newHandle;
						view = gpuManager.GetTextureView(newHandle);
					}
				}

				if (view != null)
					matInstance.SetTexture(slotName, view);
			}
		}
	}
}
