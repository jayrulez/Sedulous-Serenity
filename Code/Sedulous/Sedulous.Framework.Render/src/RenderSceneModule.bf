namespace Sedulous.Framework.Render;

using System;
using System.Collections;
using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.RHI;
using Sedulous.Materials;

/// Component for entities with a static mesh.
/// The proxy handle is managed by RenderSceneModule.
struct MeshRendererComponent
{
	/// Handle to the mesh proxy in the render world.
	public MeshProxyHandle ProxyHandle;
	/// Whether this renderer is enabled.
	public bool Enabled;

	public static MeshRendererComponent Default => .() {
		ProxyHandle = .Invalid,
		Enabled = true
	};
}

/// Component for entities with a skinned mesh.
struct SkinnedMeshRendererComponent
{
	/// Handle to the skinned mesh proxy in the render world.
	public SkinnedMeshProxyHandle ProxyHandle;
	/// Whether this renderer is enabled.
	public bool Enabled;

	public static SkinnedMeshRendererComponent Default => .() {
		ProxyHandle = .Invalid,
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


/// Scene module that manages render proxies and syncs entity transforms to the render world.
/// Created automatically by RenderSubsystem for each scene.
class RenderSceneModule : SceneModule
{
	private RenderSubsystem mSubsystem;
	private RenderWorld mWorld;
	private Scene mScene;

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
		// Proxies are cleaned up when entities are destroyed or when RenderWorld is deleted
		mScene = null;
	}

	public override void PostUpdate(Scene scene, float deltaTime)
	{
		if (mScene == null || mWorld == null)
			return;

		// Sync mesh transforms
		for (let (entity, mesh) in scene.Query<MeshRendererComponent>())
		{
			if (!mesh.ProxyHandle.IsValid || !mesh.Enabled)
				continue;

			let worldMatrix = scene.GetWorldMatrix(entity);
			mWorld.SetMeshTransform(mesh.ProxyHandle, worldMatrix);
		}

		// Sync skinned mesh transforms
		for (let (entity, mesh) in scene.Query<SkinnedMeshRendererComponent>())
		{
			if (!mesh.ProxyHandle.IsValid || !mesh.Enabled)
				continue;

			let worldMatrix = scene.GetWorldMatrix(entity);
			mWorld.SetSkinnedMeshTransform(mesh.ProxyHandle, worldMatrix);
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
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		if (mWorld == null)
			return;

		// Clean up mesh proxy
		if (let mesh = scene.GetComponent<MeshRendererComponent>(entity))
		{
			if (mesh.ProxyHandle.IsValid)
				mWorld.DestroyMesh(mesh.ProxyHandle);
		}

		// Clean up skinned mesh proxy
		if (let skinned = scene.GetComponent<SkinnedMeshRendererComponent>(entity))
		{
			if (skinned.ProxyHandle.IsValid)
				mWorld.DestroySkinnedMesh(skinned.ProxyHandle);
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
	}

	// ==================== Mesh API ====================

	/// Creates a mesh renderer for an entity.
	/// Returns the proxy handle for further configuration.
	public MeshProxyHandle CreateMeshRenderer(EntityId entity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateMesh();

		var comp = mScene.GetComponent<MeshRendererComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<MeshRendererComponent>(entity, .Default);
			comp = mScene.GetComponent<MeshRendererComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Enabled = true;

		// Set initial transform
		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetMeshTransform(handle, worldMatrix);

		return handle;
	}

	/// Sets the mesh data for a mesh renderer.
	public void SetMeshData(EntityId entity, GPUMeshHandle meshHandle, BoundingBox localBounds)
	{
		if (let comp = mScene?.GetComponent<MeshRendererComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld?.SetMeshData(comp.ProxyHandle, meshHandle, localBounds);
		}
	}

	/// Sets the material for a mesh renderer.
	public void SetMeshMaterial(EntityId entity, MaterialInstance material)
	{
		if (let comp = mScene?.GetComponent<MeshRendererComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld?.SetMeshMaterial(comp.ProxyHandle, material);
		}
	}

	/// Sets the render flags for a mesh renderer.
	public void SetMeshFlags(EntityId entity, MeshFlags flags)
	{
		if (let comp = mScene?.GetComponent<MeshRendererComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld?.SetMeshFlags(comp.ProxyHandle, flags);
		}
	}

	/// Enables or disables a mesh renderer.
	public void SetMeshEnabled(EntityId entity, bool enabled)
	{
		if (let comp = mScene?.GetComponent<MeshRendererComponent>(entity))
		{
			comp.Enabled = enabled;
			if (comp.ProxyHandle.IsValid)
			{
				if (let proxy = mWorld?.GetMesh(comp.ProxyHandle))
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

	/// Creates a skinned mesh renderer for an entity.
	public SkinnedMeshProxyHandle CreateSkinnedMeshRenderer(EntityId entity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateSkinnedMesh();

		var comp = mScene.GetComponent<SkinnedMeshRendererComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<SkinnedMeshRendererComponent>(entity, .Default);
			comp = mScene.GetComponent<SkinnedMeshRendererComponent>(entity);
		}

		comp.ProxyHandle = handle;
		comp.Enabled = true;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetSkinnedMeshTransform(handle, worldMatrix);

		return handle;
	}

	/// Sets the skinned mesh data.
	public void SetSkinnedMeshData(EntityId entity, GPUMeshHandle meshHandle, GPUBoneBufferHandle boneBufferHandle, BoundingBox localBounds, uint16 boneCount)
	{
		if (let comp = mScene?.GetComponent<SkinnedMeshRendererComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld?.SetSkinnedMeshData(comp.ProxyHandle, meshHandle, boneBufferHandle, localBounds, boneCount);
		}
	}

	/// Marks skinned mesh bones as dirty (need GPU upload).
	public void MarkSkinnedMeshBonesDirty(EntityId entity)
	{
		if (let comp = mScene?.GetComponent<SkinnedMeshRendererComponent>(entity))
		{
			if (comp.ProxyHandle.IsValid)
				mWorld?.MarkSkinnedMeshBonesDirty(comp.ProxyHandle);
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
}
