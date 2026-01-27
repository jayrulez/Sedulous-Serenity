namespace Sedulous.Framework.Render;

using System;
using System.Collections;
using Sedulous.Framework.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.RHI;
using Sedulous.Materials;

/// Component for entities with a static mesh.
/// Set the Mesh field and the framework handles GPU upload automatically.
/// Note: ResourceHandle uses manual ref counting. Call AddRef() when copying,
/// Release() when removing/replacing.
struct MeshRendererComponent
{
	/// The mesh resource handle. Set this to change the mesh.
	/// Create with ResourceHandle<StaticMeshResource>(resource) which calls AddRef().
	/// Call Release() when removing or replacing the mesh.
	public ResourceHandle<StaticMeshResource> Mesh;
	/// The material to use for rendering. Can be set before or after the mesh.
	public MaterialInstance Material;
	/// Whether this renderer is enabled.
	public bool Enabled;

	public static MeshRendererComponent Default => .() {
		Mesh = default,
		Material = null,
		Enabled = true
	};
}

/// Component for entities with a skinned mesh.
/// Set the Mesh field and the framework handles GPU upload automatically.
/// Note: ResourceHandle uses manual ref counting. Call AddRef() when copying,
/// Release() when removing/replacing.
struct SkinnedMeshRendererComponent
{
	/// The skinned mesh resource handle. Set this to change the mesh.
	/// Create with ResourceHandle<SkinnedMeshResource>(resource) which calls AddRef().
	/// Call Release() when removing or replacing the mesh.
	public ResourceHandle<SkinnedMeshResource> Mesh;
	/// The material to use for rendering. Can be set before or after the mesh.
	public MaterialInstance Material;
	/// Whether this renderer is enabled.
	public bool Enabled;

	public static SkinnedMeshRendererComponent Default => .() {
		Mesh = default,
		Material = null,
		Enabled = true
	};
}

/// Component for camera entities.
struct CameraComponent
{
	/// Handle to the camera proxy in the render world.
	public CameraProxyHandle ProxyHandle;
	/// Whether this camera is active.
	public bool Active;
	/// Whether this is the main camera.
	public bool IsMainCamera;

	public static CameraComponent Default => .() {
		ProxyHandle = .Invalid,
		Active = true,
		IsMainCamera = false
	};
}

/// Component for light entities.
struct LightComponent
{
	/// Handle to the light proxy in the render world.
	public LightProxyHandle ProxyHandle;
	/// Whether this light is enabled.
	public bool Enabled;

	public static LightComponent Default => .() {
		ProxyHandle = .Invalid,
		Enabled = true
	};
}

/// Component for particle emitter entities.
struct ParticleEmitterComponent
{
	/// Handle to the particle emitter proxy in the render world.
	public ParticleEmitterProxyHandle ProxyHandle;
	/// Whether this emitter is enabled.
	public bool Enabled;

	public static ParticleEmitterComponent Default => .() {
		ProxyHandle = .Invalid,
		Enabled = true
	};
}


/// Component for sprite entities.
struct SpriteComponent
{
	/// Handle to the sprite proxy in the render world.
	public SpriteProxyHandle ProxyHandle;
	/// Whether this sprite is enabled.
	public bool Enabled;

	public static SpriteComponent Default => .() {
		ProxyHandle = .Invalid,
		Enabled = true
	};
}

/// Component for trail emitter entities.
struct TrailEmitterComponent
{
	/// Handle to the trail emitter proxy in the render world.
	public TrailEmitterProxyHandle ProxyHandle;
	/// Whether this trail emitter is enabled.
	public bool Enabled;

	public static TrailEmitterComponent Default => .() {
		ProxyHandle = .Invalid,
		Enabled = true
	};
}

/// Scene module that manages render proxies and syncs entity transforms to the render world.
/// Created automatically by RenderSubsystem for each scene.
class RenderSceneModule : SceneModule
{
	private RenderSubsystem mSubsystem;
	private RenderWorld mWorld;
	private Scene mScene;

	// Cache: resource -> GPU handle (shared across entities using same resource)
	private Dictionary<StaticMeshResource, GPUMeshHandle> mStaticMeshCache = new .() ~ delete _;
	private Dictionary<SkinnedMeshResource, GPUMeshHandle> mSkinnedMeshCache = new .() ~ delete _;

	// Track which mesh resource is currently bound to each entity's proxy
	// Used to detect when the mesh changes and needs re-upload
	private Dictionary<EntityId, StaticMeshResource> mEntityMeshBinding = new .() ~ delete _;
	private Dictionary<EntityId, SkinnedMeshResource> mEntitySkinnedMeshBinding = new .() ~ delete _;

	// Track which material is currently bound to each entity's proxy
	// Used to detect when the material changes and needs to be updated
	private Dictionary<EntityId, MaterialInstance> mEntityMaterialBinding = new .() ~ delete _;
	private Dictionary<EntityId, MaterialInstance> mEntitySkinnedMaterialBinding = new .() ~ delete _;

	// Track proxy handles per entity (internal, not exposed on components)
	private Dictionary<EntityId, MeshProxyHandle> mMeshProxies = new .() ~ delete _;
	private Dictionary<EntityId, SkinnedMeshProxyHandle> mSkinnedMeshProxies = new .() ~ delete _;

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

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// Release mesh resource handles on all components
		for (let (entity, meshComp) in scene.Query<MeshRendererComponent>())
		{
			meshComp.Mesh.Release();
		}

		for (let (entity, skinnedComp) in scene.Query<SkinnedMeshRendererComponent>())
		{
			skinnedComp.Mesh.Release();
		}

		// Release cached GPU meshes
		let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
		let frameNumber = mSubsystem.RenderSystem?.FrameNumber ?? 0;

		if (gpuManager != null)
		{
			for (let handle in mStaticMeshCache.Values)
				gpuManager.ReleaseMesh(handle, frameNumber);

			for (let handle in mSkinnedMeshCache.Values)
				gpuManager.ReleaseMesh(handle, frameNumber);
		}

		mStaticMeshCache.Clear();
		mSkinnedMeshCache.Clear();
		mEntityMeshBinding.Clear();
		mEntitySkinnedMeshBinding.Clear();
		mEntityMaterialBinding.Clear();
		mEntitySkinnedMaterialBinding.Clear();
		mMeshProxies.Clear();
		mSkinnedMeshProxies.Clear();

		// Proxies are cleaned up when entities are destroyed or when RenderWorld is deleted
		mScene = null;
	}

	public override void PostUpdate(Scene scene, float deltaTime)
	{
		if (mScene == null || mWorld == null)
			return;

		// Process static mesh components - detect changes and handle GPU upload
		for (let (entity, mesh) in scene.Query<MeshRendererComponent>())
		{
			if (!mesh.Enabled)
				continue;

			// Get the actual resource from the handle
			let resource = mesh.Mesh.Resource;

			// Get or create proxy handle
			MeshProxyHandle proxyHandle = .Invalid;
			if (mMeshProxies.TryGetValue(entity, var existingProxy))
				proxyHandle = existingProxy;

			// Check if mesh resource has changed
			StaticMeshResource currentBinding = null;
			mEntityMeshBinding.TryGetValue(entity, out currentBinding);

			if (resource != currentBinding)
			{
				// Mesh changed - update binding and handle GPU upload
				if (resource != null && resource.Mesh != null)
				{
					// Create proxy if needed
					if (!proxyHandle.IsValid)
					{
						proxyHandle = mWorld.CreateMesh();
						mMeshProxies[entity] = proxyHandle;
					}

					// Upload to GPU and set mesh data
					UploadAndSetMeshData(entity, proxyHandle, resource);
					mEntityMeshBinding[entity] = resource;
				}
				else if (resource == null && currentBinding != null)
				{
					// Mesh cleared - remove binding (proxy stays for potential reuse)
					mEntityMeshBinding.Remove(entity);
				}
			}

			// Check if material has changed
			if (proxyHandle.IsValid)
			{
				MaterialInstance currentMaterial = null;
				mEntityMaterialBinding.TryGetValue(entity, out currentMaterial);

				if (mesh.Material != currentMaterial)
				{
					// Material changed - update binding and apply to proxy
					if (mesh.Material != null)
					{
						mWorld.SetMeshMaterial(proxyHandle, mesh.Material);
						mEntityMaterialBinding[entity] = mesh.Material;
					}
					else
					{
						mEntityMaterialBinding.Remove(entity);
					}
				}
			}

			// Sync transform
			if (proxyHandle.IsValid)
			{
				let worldMatrix = scene.GetWorldMatrix(entity);
				mWorld.SetMeshTransform(proxyHandle, worldMatrix);
			}
		}

		// Process skinned mesh components - detect changes and handle GPU upload
		for (let (entity, mesh) in scene.Query<SkinnedMeshRendererComponent>())
		{
			if (!mesh.Enabled)
				continue;

			// Get the actual resource from the handle
			let resource = mesh.Mesh.Resource;

			// Get or create proxy handle
			SkinnedMeshProxyHandle proxyHandle = .Invalid;
			if (mSkinnedMeshProxies.TryGetValue(entity, var existingProxy))
				proxyHandle = existingProxy;

			// Check if mesh resource has changed
			SkinnedMeshResource currentBinding = null;
			mEntitySkinnedMeshBinding.TryGetValue(entity, out currentBinding);

			if (resource != currentBinding)
			{
				// Mesh changed - update binding and handle GPU upload
				if (resource != null && resource.Mesh != null)
				{
					// Create proxy if needed
					if (!proxyHandle.IsValid)
					{
						proxyHandle = mWorld.CreateSkinnedMesh();
						mSkinnedMeshProxies[entity] = proxyHandle;
					}

					// Upload to GPU and set mesh data
					UploadAndSetSkinnedMeshData(entity, proxyHandle, resource);
					mEntitySkinnedMeshBinding[entity] = resource;
				}
				else if (resource == null && currentBinding != null)
				{
					// Mesh cleared - remove binding (proxy stays for potential reuse)
					mEntitySkinnedMeshBinding.Remove(entity);
				}
			}

			// Check if material has changed
			if (proxyHandle.IsValid)
			{
				MaterialInstance currentMaterial = null;
				mEntitySkinnedMaterialBinding.TryGetValue(entity, out currentMaterial);

				if (mesh.Material != currentMaterial)
				{
					// Material changed - update binding and apply to proxy
					if (mesh.Material != null)
					{
						mWorld.SetSkinnedMeshMaterial(proxyHandle, mesh.Material);
						mEntitySkinnedMaterialBinding[entity] = mesh.Material;
					}
					else
					{
						mEntitySkinnedMaterialBinding.Remove(entity);
					}
				}
			}

			// Sync transform
			if (proxyHandle.IsValid)
			{
				let worldMatrix = scene.GetWorldMatrix(entity);
				mWorld.SetSkinnedMeshTransform(proxyHandle, worldMatrix);
			}
		}

		// Sync camera transforms
		for (let (entity, camera) in scene.Query<CameraComponent>())
		{
			if (!camera.ProxyHandle.IsValid || !camera.Active)
				continue;

			let worldMatrix = scene.GetWorldMatrix(entity);
			if (let proxy = mWorld.GetCamera(camera.ProxyHandle))
			{
				// Extract position and orientation from world matrix
				let position = worldMatrix.Translation;
				let forward = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
				let up = Vector3.Normalize(.(worldMatrix.M21, worldMatrix.M22, worldMatrix.M23));
				proxy.SetPositionDirection(position, forward, up);
			}
		}

		// Sync light transforms
		for (let (entity, light) in scene.Query<LightComponent>())
		{
			if (!light.ProxyHandle.IsValid || !light.Enabled)
				continue;

			let worldMatrix = scene.GetWorldMatrix(entity);
			if (let proxy = mWorld.GetLight(light.ProxyHandle))
			{
				proxy.Position = worldMatrix.Translation;
				// Extract forward direction for directional/spot lights
				proxy.Direction = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
			}
		}

		// Sync particle emitter transforms
		for (let (entity, emitter) in scene.Query<ParticleEmitterComponent>())
		{
			if (!emitter.ProxyHandle.IsValid || !emitter.Enabled)
				continue;

			let worldMatrix = scene.GetWorldMatrix(entity);
			mWorld.SetParticleEmitterPosition(emitter.ProxyHandle, worldMatrix.Translation);
		}

		// Sync sprite transforms
		for (let (entity, sprite) in scene.Query<SpriteComponent>())
		{
			if (!sprite.ProxyHandle.IsValid || !sprite.Enabled)
				continue;

			let worldMatrix = scene.GetWorldMatrix(entity);
			mWorld.SetSpritePosition(sprite.ProxyHandle, worldMatrix.Translation);
		}
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		if (mWorld == null)
			return;

		// Clean up mesh component - release resource handle
		if (let meshComp = scene.GetComponent<MeshRendererComponent>(entity))
		{
			meshComp.Mesh.Release();
		}

		// Clean up mesh proxy (from internal tracking)
		if (mMeshProxies.TryGetValue(entity, let meshProxy))
		{
			if (meshProxy.IsValid)
				mWorld.DestroyMesh(meshProxy);
			mMeshProxies.Remove(entity);
		}

		// Clean up skinned mesh component - release resource handle
		if (let skinnedComp = scene.GetComponent<SkinnedMeshRendererComponent>(entity))
		{
			skinnedComp.Mesh.Release();
		}

		// Clean up skinned mesh proxy (from internal tracking)
		if (mSkinnedMeshProxies.TryGetValue(entity, let skinnedProxy))
		{
			if (skinnedProxy.IsValid)
				mWorld.DestroySkinnedMesh(skinnedProxy);
			mSkinnedMeshProxies.Remove(entity);
		}

		// Clean up camera proxy
		if (let camera = scene.GetComponent<CameraComponent>(entity))
		{
			if (camera.ProxyHandle.IsValid)
				mWorld.DestroyCamera(camera.ProxyHandle);
		}

		// Clean up light proxy
		if (let light = scene.GetComponent<LightComponent>(entity))
		{
			if (light.ProxyHandle.IsValid)
				mWorld.DestroyLight(light.ProxyHandle);
		}

		// Clean up particle emitter proxy
		if (let emitter = scene.GetComponent<ParticleEmitterComponent>(entity))
		{
			if (emitter.ProxyHandle.IsValid)
				mWorld.DestroyParticleEmitter(emitter.ProxyHandle);
		}

		// Clean up sprite proxy
		if (let sprite = scene.GetComponent<SpriteComponent>(entity))
		{
			if (sprite.ProxyHandle.IsValid)
				mWorld.DestroySprite(sprite.ProxyHandle);
		}

		// Clean up trail emitter proxy
		if (let trail = scene.GetComponent<TrailEmitterComponent>(entity))
		{
			if (trail.ProxyHandle.IsValid)
				mWorld.DestroyTrailEmitter(trail.ProxyHandle);
		}

		// Clean up entity mesh and material bindings
		mEntityMeshBinding.Remove(entity);
		mEntitySkinnedMeshBinding.Remove(entity);
		mEntityMaterialBinding.Remove(entity);
		mEntitySkinnedMaterialBinding.Remove(entity);
	}

	// ==================== Mesh API ====================

	/// Internal: Uploads mesh resource to GPU (if not cached) and sets mesh data on proxy.
	private void UploadAndSetMeshData(EntityId entity, MeshProxyHandle proxyHandle, StaticMeshResource resource)
	{
		if (resource == null || resource.Mesh == null || !proxyHandle.IsValid)
			return;

		// Check cache first
		GPUMeshHandle gpuHandle;
		if (mStaticMeshCache.TryGetValue(resource, out gpuHandle))
		{
			// Already uploaded, just set the data
			mWorld?.SetMeshData(proxyHandle, gpuHandle, resource.Mesh.GetBounds());
			return;
		}

		// Upload to GPU
		let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
		if (gpuManager == null)
			return;

		if (gpuManager.UploadMesh(resource.Mesh) case .Ok(let handle))
		{
			// Cache the mapping
			mStaticMeshCache[resource] = handle;

			// Set mesh data on proxy
			mWorld?.SetMeshData(proxyHandle, handle, resource.Mesh.GetBounds());
		}
	}

	/// Internal: Uploads skinned mesh resource to GPU (if not cached) and sets mesh data on proxy.
	private void UploadAndSetSkinnedMeshData(EntityId entity, SkinnedMeshProxyHandle proxyHandle, SkinnedMeshResource resource)
	{
		if (resource == null || resource.Mesh == null || !proxyHandle.IsValid)
			return;

		// Check cache first for mesh
		GPUMeshHandle gpuMeshHandle;
		if (!mSkinnedMeshCache.TryGetValue(resource, out gpuMeshHandle))
		{
			// Upload mesh to GPU
			let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
			if (gpuManager == null)
				return;

			if (gpuManager.UploadMesh(resource.Mesh) case .Ok(let handle))
			{
				mSkinnedMeshCache[resource] = handle;
				gpuMeshHandle = handle;
			}
			else
				return;
		}

		// Create bone buffer for this instance
		let skeleton = resource.Skeleton;
		if (skeleton == null)
			return;

		let boneCount = (uint16)skeleton.BoneCount;
		let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
		if (gpuManager.CreateBoneBuffer(boneCount) case .Ok(let boneHandle))
		{
			mWorld?.SetSkinnedMeshData(proxyHandle, gpuMeshHandle, boneHandle, resource.Mesh.Bounds, boneCount);
		}
	}

	/// Sets the render flags for a mesh renderer.
	public void SetMeshFlags(EntityId entity, MeshFlags flags)
	{
		if (mMeshProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				mWorld?.SetMeshFlags(proxyHandle, flags);
		}
	}

	/// Enables or disables a mesh renderer.
	public void SetMeshEnabled(EntityId entity, bool enabled)
	{
		if (let comp = mScene?.GetComponent<MeshRendererComponent>(entity))
			comp.Enabled = enabled;

		if (mMeshProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
			{
				if (let proxy = mWorld?.GetMesh(proxyHandle))
				{
					if (enabled)
						proxy.Flags |= .Visible;
					else
						proxy.Flags &= ~.Visible;
				}
			}
		}
	}

	// ==================== Skinned Mesh API ====================

	/// Marks skinned mesh bones as dirty (need GPU upload).
	public void MarkSkinnedMeshBonesDirty(EntityId entity)
	{
		if (mSkinnedMeshProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				mWorld?.MarkSkinnedMeshBonesDirty(proxyHandle);
		}
	}

	// ==================== Camera API ====================

	/// Creates a perspective camera for an entity.
	public CameraProxyHandle CreatePerspectiveCamera(EntityId entity, float fov, float aspectRatio, float nearPlane, float farPlane)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let position = worldMatrix.Translation;
		let forward = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
		let up = Vector3.Normalize(.(worldMatrix.M21, worldMatrix.M22, worldMatrix.M23));
		let target = position + forward;

		let handle = mWorld.CreatePerspectiveCamera(position, target, up, fov, aspectRatio, nearPlane, farPlane);

		var comp = mScene.GetComponent<CameraComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<CameraComponent>(entity, .Default);
			comp = mScene.GetComponent<CameraComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Active = true;

		return handle;
	}

	/// Creates an orthographic camera for an entity.
	public CameraProxyHandle CreateOrthographicCamera(EntityId entity, float width, float height, float nearPlane, float farPlane)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let position = worldMatrix.Translation;
		let forward = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
		let up = Vector3.Normalize(.(worldMatrix.M21, worldMatrix.M22, worldMatrix.M23));
		let target = position + forward;

		let handle = mWorld.CreateOrthographicCamera(position, target, up, width, height, nearPlane, farPlane);

		var comp = mScene.GetComponent<CameraComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<CameraComponent>(entity, .Default);
			comp = mScene.GetComponent<CameraComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Active = true;

		return handle;
	}

	/// Sets this camera as the main camera.
	public void SetMainCamera(EntityId entity)
	{
		if (let comp = mScene?.GetComponent<CameraComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
			{
				comp.IsMainCamera = true;
				mWorld?.SetMainCamera(comp.ProxyHandle);
			}
		}
	}

	/// Updates camera matrices. Call after changing projection parameters.
	public void UpdateCameraMatrices(EntityId entity, bool flipY = false)
	{
		if (let comp = mScene?.GetComponent<CameraComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld?.UpdateCameraMatrices(comp.ProxyHandle, flipY);
		}
	}

	/// Gets the camera proxy for direct access.
	public CameraProxy* GetCameraProxy(EntityId entity)
	{
		if (let comp = mScene?.GetComponent<CameraComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				return mWorld?.GetCamera(comp.ProxyHandle);
		}
		return null;
	}

	// ==================== Light API ====================

	/// Creates a directional light for an entity.
	public LightProxyHandle CreateDirectionalLight(EntityId entity, Vector3 color, float intensity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let direction = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));

		let handle = mWorld.CreateDirectionalLight(direction, color, intensity);

		var comp = mScene.GetComponent<LightComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<LightComponent>(entity, .Default);
			comp = mScene.GetComponent<LightComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Enabled = true;

		return handle;
	}

	/// Creates a point light for an entity.
	public LightProxyHandle CreatePointLight(EntityId entity, Vector3 color, float intensity, float range)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let position = worldMatrix.Translation;

		let handle = mWorld.CreatePointLight(position, color, intensity, range);

		var comp = mScene.GetComponent<LightComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<LightComponent>(entity, .Default);
			comp = mScene.GetComponent<LightComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Enabled = true;

		return handle;
	}

	/// Creates a spot light for an entity.
	public LightProxyHandle CreateSpotLight(EntityId entity, Vector3 color, float intensity, float range, float innerAngle, float outerAngle)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let position = worldMatrix.Translation;
		let direction = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));

		let handle = mWorld.CreateSpotLight(position, direction, color, intensity, range, innerAngle, outerAngle);

		var comp = mScene.GetComponent<LightComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<LightComponent>(entity, .Default);
			comp = mScene.GetComponent<LightComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Enabled = true;

		return handle;
	}

	/// Sets light color and intensity.
	public void SetLightColor(EntityId entity, Vector3 color, float intensity)
	{
		if (let comp = mScene?.GetComponent<LightComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld?.SetLightColor(comp.ProxyHandle, color, intensity);
		}
	}

	/// Enables or disables a light.
	public void SetLightEnabled(EntityId entity, bool enabled)
	{
		if (let comp = mScene?.GetComponent<LightComponent>(entity))
		{
			comp.Enabled = enabled;
			if (comp.ProxyHandle.IsValid)
				mWorld?.SetLightEnabled(comp.ProxyHandle, enabled);
		}
	}

	/// Gets the light proxy for direct access.
	public LightProxy* GetLightProxy(EntityId entity)
	{
		if (let comp = mScene?.GetComponent<LightComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				return mWorld?.GetLight(comp.ProxyHandle);
		}
		return null;
	}

	// ==================== Particle Emitter API ====================

	/// Creates a particle emitter for an entity.
	public ParticleEmitterProxyHandle CreateParticleEmitter(EntityId entity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateParticleEmitter();

		var comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<ParticleEmitterComponent>(entity, .Default);
			comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Enabled = true;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetParticleEmitterPosition(handle, worldMatrix.Translation);

		return handle;
	}

	/// Gets the particle emitter proxy for direct access.
	public ParticleEmitterProxy* GetParticleEmitterProxy(EntityId entity)
	{
		if (let comp = mScene?.GetComponent<ParticleEmitterComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				return mWorld?.GetParticleEmitter(comp.ProxyHandle);
		}
		return null;
	}

	/// Creates a CPU-simulated particle emitter for an entity.
	/// The CPUParticleEmitter is created and assigned to the proxy.
	public ParticleEmitterProxyHandle CreateCPUParticleEmitter(EntityId entity, int32 maxParticles = 1000)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let device = mSubsystem.RenderSystem?.Device;
		if (device == null)
			return .Invalid;

		let handle = mWorld.CreateParticleEmitter();

		var comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<ParticleEmitterComponent>(entity, .Default);
			comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Enabled = true;

		// Configure for CPU backend
		if (let proxy = mWorld.GetParticleEmitter(handle))
		{
			proxy.Backend = .CPU;
			proxy.MaxParticles = (uint32)maxParticles;
			proxy.CPUEmitter = new CPUParticleEmitter(device, maxParticles);
		}

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetParticleEmitterPosition(handle, worldMatrix.Translation);

		return handle;
	}

	// ==================== Sprite API ====================

	/// Creates a sprite for an entity.
	public SpriteProxyHandle CreateSprite(EntityId entity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateSprite();

		var comp = mScene.GetComponent<SpriteComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<SpriteComponent>(entity, .Default);
			comp = mScene.GetComponent<SpriteComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Enabled = true;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetSpritePosition(handle, worldMatrix.Translation);

		return handle;
	}

	/// Gets the sprite proxy for direct access.
	public SpriteProxy* GetSpriteProxy(EntityId entity)
	{
		if (let comp = mScene?.GetComponent<SpriteComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				return mWorld?.GetSprite(comp.ProxyHandle);
		}
		return null;
	}

	/// Sets sprite size.
	public void SetSpriteSize(EntityId entity, Vector2 size)
	{
		if (let comp = mScene?.GetComponent<SpriteComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld.SetSpriteSize(comp.ProxyHandle, size);
		}
	}

	/// Sets sprite color.
	public void SetSpriteColor(EntityId entity, Color color)
	{
		if (let comp = mScene?.GetComponent<SpriteComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld.SetSpriteColor(comp.ProxyHandle, color);
		}
	}

	/// Sets sprite texture.
	public void SetSpriteTexture(EntityId entity, ITextureView texture)
	{
		if (let comp = mScene?.GetComponent<SpriteComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld.SetSpriteTexture(comp.ProxyHandle, texture);
		}
	}

	// ==================== Trail Emitter API ====================

	/// Creates a trail emitter for an entity.
	public TrailEmitterProxyHandle CreateTrailEmitter(EntityId entity, int32 maxPoints = 32)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let device = mSubsystem.RenderSystem?.Device;
		if (device == null)
			return .Invalid;

		let handle = mWorld.CreateTrailEmitter();

		var comp = mScene.GetComponent<TrailEmitterComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<TrailEmitterComponent>(entity, .Default);
			comp = mScene.GetComponent<TrailEmitterComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Enabled = true;

		// Configure proxy and create the emitter
		if (let proxy = mWorld.GetTrailEmitter(handle))
		{
			proxy.MaxPoints = maxPoints;
			proxy.IsActive = true;
			proxy.Emitter = new TrailEmitter(device, maxPoints);
		}

		return handle;
	}

	/// Gets the trail emitter proxy for direct access.
	public TrailEmitterProxy* GetTrailEmitterProxy(EntityId entity)
	{
		if (let comp = mScene?.GetComponent<TrailEmitterComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				return mWorld?.GetTrailEmitter(comp.ProxyHandle);
		}
		return null;
	}
}
