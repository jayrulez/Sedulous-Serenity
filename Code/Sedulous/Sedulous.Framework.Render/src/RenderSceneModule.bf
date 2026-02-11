namespace Sedulous.Framework.Render;

using System;
using System.Collections;
using Sedulous.Animation.Resources;
using Sedulous.Framework.Animation;
using Sedulous.Framework.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.RHI;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Textures.Resources;
using Sedulous.Imaging;
using Sedulous.Serialization;

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
	private Dictionary<TextureResource, GPUTextureHandle> mTextureCache = new .() ~ delete _;

	// Track which mesh resource is currently bound to each entity's proxy
	// Used to detect when the mesh changes and needs re-upload
	private Dictionary<EntityId, StaticMeshResource> mEntityMeshBinding = new .() ~ delete _;
	private Dictionary<EntityId, SkinnedMeshResource> mEntitySkinnedMeshBinding = new .() ~ delete _;

	// (Material binding is tracked directly on proxies — no per-entity dictionary needed)

	// Track which texture resource is currently bound to each sprite entity's proxy
	private Dictionary<EntityId, TextureResource> mEntitySpriteTextureBinding = new .() ~ delete _;

	// Track loaded texture resource refs per entity (for releasing on destroy)
	private Dictionary<EntityId, List<TextureResource>> mEntityTextureRefs = new .() ~ { for (var kv in _) delete kv.value; delete _; };

	// Track proxy handles per entity (internal, not exposed on components)
	private Dictionary<EntityId, MeshProxyHandle> mMeshProxies = new .() ~ delete _;
	private Dictionary<EntityId, SkinnedMeshProxyHandle> mSkinnedMeshProxies = new .() ~ delete _;
	private Dictionary<EntityId, CameraProxyHandle> mCameraProxies = new .() ~ delete _;
	private Dictionary<EntityId, LightProxyHandle> mLightProxies = new .() ~ delete _;
	private Dictionary<EntityId, ParticleEmitterProxyHandle> mParticleEmitterProxies = new .() ~ delete _;
	private Dictionary<EntityId, SpriteProxyHandle> mSpriteProxies = new .() ~ delete _;
	private Dictionary<EntityId, TrailEmitterProxyHandle> mTrailEmitterProxies = new .() ~ delete _;

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
		scene.RegisterComponentSerializer<MeshRendererComponent>();
		scene.RegisterComponentSerializer<SkinnedMeshRendererComponent>();
		scene.RegisterComponentSerializer<CameraComponent>();
		scene.RegisterComponentSerializer<LightComponent>();
		scene.RegisterComponentSerializer<ParticleEmitterComponent>();
		scene.RegisterComponentSerializer<SpriteComponent>();
		scene.RegisterComponentSerializer<TrailEmitterComponent>();
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// Release mesh resource handles and refs on all components
		for (let (entity, meshComp) in scene.Query<MeshRendererComponent>())
		{
			meshComp.Mesh.Release();
			meshComp.MeshRef.Dispose();
			for (int32 i = 0; i < meshComp.MaterialCount; i++)
			{
				meshComp.Materials[i].Release();
				meshComp.MaterialRefs[i].Dispose();
				if (meshComp.MaterialInstances[i] != null)
				{
					meshComp.MaterialInstances[i].ReleaseRef();
					meshComp.MaterialInstances[i] = null;
				}
			}
		}

		for (let (entity, skinnedComp) in scene.Query<SkinnedMeshRendererComponent>())
		{
			skinnedComp.Mesh.Release();
			skinnedComp.MeshRef.Dispose();
			for (int32 i = 0; i < skinnedComp.MaterialCount; i++)
			{
				skinnedComp.Materials[i].Release();
				skinnedComp.MaterialRefs[i].Dispose();
				if (skinnedComp.MaterialInstances[i] != null)
				{
					skinnedComp.MaterialInstances[i].ReleaseRef();
					skinnedComp.MaterialInstances[i] = null;
				}
			}
		}

		for (let (entity, sprite) in scene.Query<SpriteComponent>())
		{
			sprite.Texture.Release();
			sprite.TextureRef.Dispose();
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

		mStaticMeshCache.Clear();
		mSkinnedMeshCache.Clear();
		mTextureCache.Clear();
		mEntityMeshBinding.Clear();
		mEntitySkinnedMeshBinding.Clear();
		mEntitySpriteTextureBinding.Clear();
		mMeshProxies.Clear();
		mSkinnedMeshProxies.Clear();
		mCameraProxies.Clear();
		mLightProxies.Clear();
		mParticleEmitterProxies.Clear();
		mSpriteProxies.Clear();
		mTrailEmitterProxies.Clear();

		// Proxies are cleaned up when entities are destroyed or when RenderWorld is deleted
		mScene = null;
	}

	public override void PostUpdate(Scene scene, float deltaTime)
	{
		if (mScene == null || mWorld == null)
			return;

		// Resolve deserialized resource references
		ResolveResourceRefs(scene);

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

			// Sync materials to proxy (compare against proxy to avoid unnecessary dirty marking)
			if (proxyHandle.IsValid)
			{
				if (let proxy = mWorld.GetMesh(proxyHandle))
				{
					for (int32 i = 0; i < mesh.MaterialCount; i++)
					{
						if (mesh.MaterialInstances[i] != proxy.Materials[i])
							mWorld.SetMeshMaterial(proxyHandle, i, mesh.MaterialInstances[i]);
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

			// Sync materials to proxy (compare against proxy to avoid unnecessary dirty marking)
			if (proxyHandle.IsValid)
			{
				if (let proxy = mWorld.GetSkinnedMesh(proxyHandle))
				{
					for (int32 i = 0; i < mesh.MaterialCount; i++)
					{
						if (mesh.MaterialInstances[i] != proxy.Materials[i])
							mWorld.SetSkinnedMeshMaterial(proxyHandle, i, mesh.MaterialInstances[i]);
					}
				}
			}

			// Sync transform and handle bone buffer
			if (proxyHandle.IsValid)
			{
				let worldMatrix = scene.GetWorldMatrix(entity);
				mWorld.SetSkinnedMeshTransform(proxyHandle, worldMatrix);

				// Ensure bone buffer and upload bone matrices from animation component
				if (let animComp = scene.GetComponent<SkeletalAnimationComponent>(entity))
				{
					let skeleton = animComp.SkeletonRes.Resource?.Skeleton;
					if (skeleton != null)
					{
						if (let proxy = mWorld.GetSkinnedMesh(proxyHandle))
						{
							let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
							if (gpuManager != null)
							{
								// Create or recreate bone buffer if needed (skeleton changed or not yet created)
								let newBoneCount = (uint16)skeleton.BoneCount;
								if (!proxy.BoneBufferHandle.IsValid || proxy.BoneCount != newBoneCount)
								{
									// Release old bone buffer if bone count changed
									if (proxy.BoneBufferHandle.IsValid)
									{
										let frameNumber = mSubsystem.RenderSystem?.FrameNumber ?? 0;
										gpuManager.ReleaseBoneBuffer(proxy.BoneBufferHandle, frameNumber);
										proxy.BoneBufferHandle = .Invalid;
										proxy.BoneCount = 0;
									}

									if (gpuManager.CreateBoneBuffer(newBoneCount) case .Ok(let boneHandle))
									{
										proxy.BoneBufferHandle = boneHandle;
										proxy.BoneCount = newBoneCount;
									}
								}

								// Upload bone matrices if playing
								if (animComp.Player != null && proxy.BoneBufferHandle.IsValid)
								{
									let currentMatrices = animComp.Player.GetSkinningMatrices();
									let prevMatrices = animComp.Player.GetPrevSkinningMatrices();
									if (currentMatrices.Length > 0)
									{
										gpuManager.UpdateBoneBuffer(
											proxy.BoneBufferHandle,
											currentMatrices.Ptr,
											prevMatrices.Ptr,
											proxy.BoneCount
										);
									}
								}
							}
						}
					}
				}
			}
		}

		// Sync cameras (auto-create proxy from component data if missing)
		for (let (entity, camera) in scene.Query<CameraComponent>())
		{
			if (!camera.Active)
				continue;

			CameraProxyHandle proxyHandle = .Invalid;
			if (mCameraProxies.TryGetValue(entity, var existingProxy))
				proxyHandle = existingProxy;

			if (!proxyHandle.IsValid)
			{
				// Auto-create proxy from component data (e.g., loaded from file)
				let wm = scene.GetWorldMatrix(entity);
				let pos = wm.Translation;
				let fwd = Vector3.Normalize(.(wm.M31, wm.M32, wm.M33));
				let up = Vector3.Normalize(.(wm.M21, wm.M22, wm.M23));
				let target = pos + fwd;

				switch (camera.Projection)
				{
				case .Perspective:
					proxyHandle = mWorld.CreatePerspectiveCamera(pos, target, up, camera.FieldOfView, camera.AspectRatio, camera.NearPlane, camera.FarPlane);
				case .Orthographic:
					proxyHandle = mWorld.CreateOrthographicCamera(pos, target, up, camera.OrthoWidth, camera.OrthoHeight, camera.NearPlane, camera.FarPlane);
				}
				mCameraProxies[entity] = proxyHandle;

				if (camera.IsMainCamera)
					mWorld.SetMainCamera(proxyHandle);
			}

			let worldMatrix = scene.GetWorldMatrix(entity);
			if (let proxy = mWorld.GetCamera(proxyHandle))
			{
				// Extract position and orientation from world matrix
				let position = worldMatrix.Translation;
				let forward = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
				let up = Vector3.Normalize(.(worldMatrix.M21, worldMatrix.M22, worldMatrix.M23));
				proxy.SetPositionDirection(position, forward, up);
			}
		}

		// Sync lights (auto-create proxy from component data if missing)
		for (let (entity, light) in scene.Query<LightComponent>())
		{
			if (!light.Enabled)
				continue;

			LightProxyHandle proxyHandle = .Invalid;
			if (mLightProxies.TryGetValue(entity, var existingProxy))
				proxyHandle = existingProxy;

			if (!proxyHandle.IsValid)
			{
				// Auto-create proxy from component data (e.g., loaded from file)
				let wm = scene.GetWorldMatrix(entity);
				let pos = wm.Translation;
				let dir = Vector3.Normalize(.(wm.M31, wm.M32, wm.M33));

				switch (light.Type)
				{
				case .Directional:
					proxyHandle = mWorld.CreateDirectionalLight(dir, light.Color, light.Intensity);
				case .Point:
					proxyHandle = mWorld.CreatePointLight(pos, light.Color, light.Intensity, light.Range);
				case .Spot:
					proxyHandle = mWorld.CreateSpotLight(pos, dir, light.Color, light.Intensity, light.Range, light.InnerConeAngle, light.OuterConeAngle);
				default:
					continue;
				}
				mLightProxies[entity] = proxyHandle;
			}

			// Sync all properties from component to proxy
			let worldMatrix = scene.GetWorldMatrix(entity);
			if (let proxy = mWorld.GetLight(proxyHandle))
			{
				proxy.Position = worldMatrix.Translation;
				proxy.Direction = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
				proxy.Color = light.Color;
				proxy.Intensity = light.Intensity;
				proxy.Range = light.Range;
				proxy.InnerConeAngle = light.InnerConeAngle;
				proxy.OuterConeAngle = light.OuterConeAngle;
				proxy.CastsShadows = light.CastsShadows;
				proxy.ShadowBias = light.ShadowBias;
				proxy.ShadowNormalBias = light.ShadowNormalBias;
				proxy.LayerMask = light.LayerMask;
			}
		}

		// Sync particle emitters (auto-create proxy from component data if missing)
		for (let (entity, emitter) in scene.Query<ParticleEmitterComponent>())
		{
			if (!emitter.Enabled)
				continue;

			ParticleEmitterProxyHandle proxyHandle = .Invalid;
			if (mParticleEmitterProxies.TryGetValue(entity, var existingProxy))
				proxyHandle = existingProxy;

			if (!proxyHandle.IsValid)
			{
				let device = mSubsystem.RenderSystem?.Device;
				proxyHandle = mWorld.CreateParticleEmitter(device, emitter.Backend, (int32)emitter.MaxParticles);
				mParticleEmitterProxies[entity] = proxyHandle;
			}

			let worldMatrix = scene.GetWorldMatrix(entity);
			if (let proxy = mWorld.GetParticleEmitter(proxyHandle))
			{
				proxy.Position = worldMatrix.Translation;
				proxy.Backend = emitter.Backend;
				proxy.SimulationSpace = emitter.SimulationSpace;
				proxy.BlendMode = emitter.BlendMode;
				proxy.RenderMode = emitter.RenderMode;
				proxy.MaxParticles = emitter.MaxParticles;
				proxy.SpawnRate = emitter.SpawnRate;
				proxy.ParticleLifetime = emitter.ParticleLifetime;
				proxy.BurstCount = emitter.BurstCount;
				proxy.BurstInterval = emitter.BurstInterval;
				proxy.BurstCycles = emitter.BurstCycles;
				proxy.StartSize = emitter.StartSize;
				proxy.EndSize = emitter.EndSize;
				proxy.StartColor = emitter.StartColor;
				proxy.EndColor = emitter.EndColor;
				proxy.InitialVelocity = emitter.InitialVelocity;
				proxy.VelocityRandomness = emitter.VelocityRandomness;
				proxy.GravityMultiplier = emitter.GravityMultiplier;
				proxy.Drag = emitter.Drag;
				proxy.VelocityInheritance = emitter.VelocityInheritance;
				proxy.SoftParticleDistance = emitter.SoftParticleDistance;
				proxy.StretchFactor = emitter.StretchFactor;
				proxy.SortParticles = emitter.SortParticles;
				proxy.Lit = emitter.Lit;
				proxy.AtlasColumns = emitter.AtlasColumns;
				proxy.AtlasRows = emitter.AtlasRows;
				proxy.AtlasFPS = emitter.AtlasFPS;
				proxy.AtlasLoop = emitter.AtlasLoop;
				// Curves
				proxy.SizeOverLifetime = emitter.SizeOverLifetime;
				proxy.ColorOverLifetime = emitter.ColorOverLifetime;
				proxy.SpeedOverLifetime = emitter.SpeedOverLifetime;
				proxy.AlphaOverLifetime = emitter.AlphaOverLifetime;
				proxy.RotationSpeedOverLifetime = emitter.RotationSpeedOverLifetime;
				// Force modules
				proxy.ForceModules = emitter.ForceModules;
				// LOD
				proxy.LODStartDistance = emitter.LODStartDistance;
				proxy.LODCullDistance = emitter.LODCullDistance;
				proxy.LODMinRateMultiplier = emitter.LODMinRateMultiplier;
				// Lifetime variance
				proxy.LifetimeVarianceMin = emitter.LifetimeVarianceMin;
				proxy.LifetimeVarianceMax = emitter.LifetimeVarianceMax;
				// Trail
				proxy.Trail = emitter.Trail;
				// Emission shape (synced to CPUEmitter if present)
				if (proxy.CPUEmitter != null)
					proxy.CPUEmitter.Shape = emitter.Shape;
				// Sub-emitter
				proxy.SubEmitterOnly = emitter.SubEmitterOnly;
				proxy.LayerMask = emitter.LayerMask;
				proxy.IsEnabled = true;
			}
		}

		// Sync sprites (auto-create proxy from component data if missing)
		for (let (entity, sprite) in scene.Query<SpriteComponent>())
		{
			if (!sprite.Enabled)
				continue;

			SpriteProxyHandle proxyHandle = .Invalid;
			if (mSpriteProxies.TryGetValue(entity, var existingProxy))
				proxyHandle = existingProxy;

			if (!proxyHandle.IsValid)
			{
				proxyHandle = mWorld.CreateSprite();
				mSpriteProxies[entity] = proxyHandle;
			}

			let worldMatrix = scene.GetWorldMatrix(entity);
			if (let proxy = mWorld.GetSprite(proxyHandle))
			{
				proxy.Position = worldMatrix.Translation;
				proxy.Size = sprite.Size;
				proxy.Color = .(sprite.Color.X, sprite.Color.Y, sprite.Color.Z, sprite.Color.W);
				proxy.UVRect = sprite.UVRect;
				proxy.LayerMask = sprite.LayerMask;
			}

			// Check if texture resource has changed
			let texResource = sprite.Texture.Resource;
			TextureResource currentTexBinding = null;
			mEntitySpriteTextureBinding.TryGetValue(entity, out currentTexBinding);

			if (texResource != currentTexBinding)
			{
				if (texResource != null && texResource.Image != null)
				{
					// Upload texture to GPU (using shared cache)
					ITextureView view = null;
					let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
					if (gpuManager != null)
					{
						if (mTextureCache.TryGetValue(texResource, var gpuHandle))
						{
							view = gpuManager.GetTextureView(gpuHandle);
						}
						else
						{
							let image = texResource.Image;
							let texData = TextureData.FromImage(image);
							if (gpuManager.UploadTexture(texData) case .Ok(let newHandle))
							{
								mTextureCache[texResource] = newHandle;
								view = gpuManager.GetTextureView(newHandle);
							}
						}
					}
					if (view != null && proxyHandle.IsValid)
						mWorld.SetSpriteTexture(proxyHandle, view);
					mEntitySpriteTextureBinding[entity] = texResource;
				}
				else if (texResource == null && currentTexBinding != null)
				{
					mEntitySpriteTextureBinding.Remove(entity);
				}
			}
		}

		// Sync trail emitters (auto-create proxy from component data if missing)
		for (let (entity, trail) in scene.Query<TrailEmitterComponent>())
		{
			if (!trail.Enabled)
				continue;

			TrailEmitterProxyHandle proxyHandle = .Invalid;
			if (mTrailEmitterProxies.TryGetValue(entity, var existingProxy))
				proxyHandle = existingProxy;

			if (!proxyHandle.IsValid)
			{
				proxyHandle = mWorld.CreateTrailEmitter();
				mTrailEmitterProxies[entity] = proxyHandle;

				// Create trail emitter object
				let device = mSubsystem.RenderSystem?.Device;
				if (device != null)
				{
					if (let proxy = mWorld.GetTrailEmitter(proxyHandle))
						proxy.Emitter = new TrailEmitter(device, trail.MaxPoints);
				}
			}

			if (let proxy = mWorld.GetTrailEmitter(proxyHandle))
			{
				proxy.BlendMode = trail.BlendMode;
				proxy.MaxPoints = trail.MaxPoints;
				proxy.Lifetime = trail.Lifetime;
				proxy.WidthStart = trail.WidthStart;
				proxy.WidthEnd = trail.WidthEnd;
				proxy.MinVertexDistance = trail.MinVertexDistance;
				proxy.Color = trail.Color;
				proxy.SoftParticleDistance = trail.SoftParticleDistance;
				proxy.LayerMask = trail.LayerMask;
				proxy.IsEnabled = true;
			}
		}
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		if (mWorld == null)
			return;

		// Clean up mesh component - release resource handles and refs
		if (let meshComp = scene.GetComponent<MeshRendererComponent>(entity))
		{
			meshComp.Mesh.Release();
			meshComp.MeshRef.Dispose();
			for (int32 i = 0; i < meshComp.MaterialCount; i++)
			{
				meshComp.Materials[i].Release();
				meshComp.MaterialRefs[i].Dispose();
				if (meshComp.MaterialInstances[i] != null)
				{
					meshComp.MaterialInstances[i].ReleaseRef();
					meshComp.MaterialInstances[i] = null;
				}
			}
		}

		// Clean up mesh proxy (from internal tracking)
		if (mMeshProxies.TryGetValue(entity, let meshProxy))
		{
			if (meshProxy.IsValid)
				mWorld.DestroyMesh(meshProxy);
			mMeshProxies.Remove(entity);
		}

		// Clean up skinned mesh component - release resource handles and refs
		if (let skinnedComp = scene.GetComponent<SkinnedMeshRendererComponent>(entity))
		{
			skinnedComp.Mesh.Release();
			skinnedComp.MeshRef.Dispose();
			for (int32 i = 0; i < skinnedComp.MaterialCount; i++)
			{
				skinnedComp.Materials[i].Release();
				skinnedComp.MaterialRefs[i].Dispose();
				if (skinnedComp.MaterialInstances[i] != null)
				{
					skinnedComp.MaterialInstances[i].ReleaseRef();
					skinnedComp.MaterialInstances[i] = null;
				}
			}
		}

		// Clean up skinned mesh proxy (from internal tracking)
		if (mSkinnedMeshProxies.TryGetValue(entity, let skinnedProxy))
		{
			if (skinnedProxy.IsValid)
				mWorld.DestroySkinnedMesh(skinnedProxy);
			mSkinnedMeshProxies.Remove(entity);
		}

		// Clean up camera proxy (from internal tracking)
		if (mCameraProxies.TryGetValue(entity, let cameraProxy))
		{
			if (cameraProxy.IsValid)
				mWorld.DestroyCamera(cameraProxy);
			mCameraProxies.Remove(entity);
		}

		// Clean up light proxy (from internal tracking)
		if (mLightProxies.TryGetValue(entity, let lightProxy))
		{
			if (lightProxy.IsValid)
				mWorld.DestroyLight(lightProxy);
			mLightProxies.Remove(entity);
		}

		// Clean up particle emitter proxy (from internal tracking)
		if (mParticleEmitterProxies.TryGetValue(entity, let emitterProxy))
		{
			if (emitterProxy.IsValid)
				mWorld.DestroyParticleEmitter(emitterProxy);
			mParticleEmitterProxies.Remove(entity);
		}

		// Clean up sprite component - release resource handles and refs
		if (let spriteComp = scene.GetComponent<SpriteComponent>(entity))
		{
			spriteComp.Texture.Release();
			spriteComp.TextureRef.Dispose();
		}

		// Clean up sprite proxy (from internal tracking)
		if (mSpriteProxies.TryGetValue(entity, let spriteProxy))
		{
			if (spriteProxy.IsValid)
				mWorld.DestroySprite(spriteProxy);
			mSpriteProxies.Remove(entity);
		}

		// Clean up trail emitter proxy (from internal tracking)
		if (mTrailEmitterProxies.TryGetValue(entity, let trailProxy))
		{
			if (trailProxy.IsValid)
				mWorld.DestroyTrailEmitter(trailProxy);
			mTrailEmitterProxies.Remove(entity);
		}

		// Clean up entity mesh, material, and texture bindings
		mEntityMeshBinding.Remove(entity);
		mEntitySkinnedMeshBinding.Remove(entity);
		mEntitySpriteTextureBinding.Remove(entity);

		// Release texture resource refs loaded for this entity
		if (mEntityTextureRefs.TryGetValue(entity, let texList))
		{
			for (let texRes in texList)
				texRes.ReleaseRef();
			delete texList;
			mEntityTextureRefs.Remove(entity);
		}
	}

	// ==================== Resource Resolution ====================

	/// Resolves deserialized ResourceRef fields to loaded ResourceHandles.
	/// Called once per frame in PostUpdate; only resolves refs that haven't been loaded yet.
	private void ResolveResourceRefs(Scene scene)
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		// Resolve static mesh components
		for (let (entity, mesh) in scene.Query<MeshRendererComponent>())
		{
			// Resolve mesh ref
			if (mesh.MeshRef.IsValid && !mesh.Mesh.IsValid)
			{
				let result = resourceSystem.LoadByRef<StaticMeshResource>(mesh.MeshRef);
				if (result case .Ok(let handle))
					mesh.Mesh = handle;
			}

			// Resolve material refs (per slot)
			for (int32 i = 0; i < mesh.MaterialCount; i++)
			{
				if (mesh.MaterialRefs[i].IsValid && !mesh.Materials[i].IsValid)
				{
					let result = resourceSystem.LoadByRef<MaterialResource>(mesh.MaterialRefs[i]);
					if (result case .Ok(let handle))
					{
						mesh.Materials[i] = handle;
						// Create MaterialInstance and resolve texture refs
						if (handle.Resource?.Material != null && mesh.MaterialInstances[i] == null)
						{
							mesh.MaterialInstances[i] = new MaterialInstance(handle.Resource.Material);
							ResolveTextureRefs(entity, resourceSystem, handle.Resource, mesh.MaterialInstances[i]);
						}
					}
				}
			}
		}

		// Resolve skinned mesh components
		for (let (entity, mesh) in scene.Query<SkinnedMeshRendererComponent>())
		{
			// Resolve mesh ref
			if (mesh.MeshRef.IsValid && !mesh.Mesh.IsValid)
			{
				let result = resourceSystem.LoadByRef<SkinnedMeshResource>(mesh.MeshRef);
				if (result case .Ok(let handle))
					mesh.Mesh = handle;
			}

			// Resolve material refs (per slot)
			for (int32 i = 0; i < mesh.MaterialCount; i++)
			{
				if (mesh.MaterialRefs[i].IsValid && !mesh.Materials[i].IsValid)
				{
					let result = resourceSystem.LoadByRef<MaterialResource>(mesh.MaterialRefs[i]);
					if (result case .Ok(let handle))
					{
						mesh.Materials[i] = handle;
						// Create MaterialInstance and resolve texture refs
						if (handle.Resource?.Material != null && mesh.MaterialInstances[i] == null)
						{
							mesh.MaterialInstances[i] = new MaterialInstance(handle.Resource.Material);
							ResolveTextureRefs(entity, resourceSystem, handle.Resource, mesh.MaterialInstances[i]);
						}
					}
				}
			}
		}

		// Resolve sprite components
		for (let (entity, sprite) in scene.Query<SpriteComponent>())
		{
			if (sprite.TextureRef.IsValid && !sprite.Texture.IsValid)
			{
				let result = resourceSystem.LoadByRef<TextureResource>(sprite.TextureRef);
				if (result case .Ok(let handle))
					sprite.Texture = handle;
			}
		}
	}

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
	/// Bone buffer is created separately when the skeleton becomes available (from SkeletalAnimationComponent).
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

		// Set mesh data on proxy (bone buffer created later when skeleton is available)
		if (let proxy = mWorld?.GetSkinnedMesh(proxyHandle))
		{
			proxy.MeshHandle = gpuMeshHandle;
			proxy.SetLocalBounds(resource.Mesh.Bounds);
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

		// Store in internal tracking
		mCameraProxies[entity] = handle;

		// Ensure component exists and populate all fields
		var comp = mScene.GetComponent<CameraComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<CameraComponent>(entity, .Default);
			comp = mScene.GetComponent<CameraComponent>(entity);
		}
		comp.Projection = .Perspective;
		comp.FieldOfView = fov;
		comp.AspectRatio = aspectRatio;
		comp.NearPlane = nearPlane;
		comp.FarPlane = farPlane;
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

		// Store in internal tracking
		mCameraProxies[entity] = handle;

		// Ensure component exists and populate all fields
		var comp = mScene.GetComponent<CameraComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<CameraComponent>(entity, .Default);
			comp = mScene.GetComponent<CameraComponent>(entity);
		}
		comp.Projection = .Orthographic;
		comp.OrthoWidth = width;
		comp.OrthoHeight = height;
		comp.AspectRatio = width / height;
		comp.NearPlane = nearPlane;
		comp.FarPlane = farPlane;
		comp.Active = true;

		return handle;
	}

	/// Sets this camera as the main camera.
	public void SetMainCamera(EntityId entity)
	{
		if (let comp = mScene?.GetComponent<CameraComponent>(entity))
		{
			comp.IsMainCamera = true;
		}

		if (mCameraProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				mWorld?.SetMainCamera(proxyHandle);
		}
	}

	/// Updates camera matrices. Call after changing projection parameters.
	public void UpdateCameraMatrices(EntityId entity, bool flipY = false)
	{
		if (mCameraProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				mWorld?.UpdateCameraMatrices(proxyHandle, flipY);
		}
	}

	/// Gets the camera proxy for direct access.
	public CameraProxy* GetCameraProxy(EntityId entity)
	{
		if (mCameraProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				return mWorld?.GetCamera(proxyHandle);
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

		// Store in internal tracking
		mLightProxies[entity] = handle;

		// Ensure component exists and populate all fields
		var comp = mScene.GetComponent<LightComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<LightComponent>(entity, .Default);
			comp = mScene.GetComponent<LightComponent>(entity);
		}
		comp.Type = .Directional;
		comp.Color = color;
		comp.Intensity = intensity;
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

		// Store in internal tracking
		mLightProxies[entity] = handle;

		// Ensure component exists and populate all fields
		var comp = mScene.GetComponent<LightComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<LightComponent>(entity, .Default);
			comp = mScene.GetComponent<LightComponent>(entity);
		}
		comp.Type = .Point;
		comp.Color = color;
		comp.Intensity = intensity;
		comp.Range = range;
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

		// Store in internal tracking
		mLightProxies[entity] = handle;

		// Ensure component exists and populate all fields
		var comp = mScene.GetComponent<LightComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<LightComponent>(entity, .Default);
			comp = mScene.GetComponent<LightComponent>(entity);
		}
		comp.Type = .Spot;
		comp.Color = color;
		comp.Intensity = intensity;
		comp.Range = range;
		comp.InnerConeAngle = innerAngle;
		comp.OuterConeAngle = outerAngle;
		comp.Enabled = true;

		return handle;
	}

	/// Sets light color and intensity.
	public void SetLightColor(EntityId entity, Vector3 color, float intensity)
	{
		if (let comp = mScene?.GetComponent<LightComponent>(entity))
		{
			comp.Color = color;
			comp.Intensity = intensity;
		}

		if (mLightProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				mWorld?.SetLightColor(proxyHandle, color, intensity);
		}
	}

	/// Enables or disables a light.
	public void SetLightEnabled(EntityId entity, bool enabled)
	{
		if (let comp = mScene?.GetComponent<LightComponent>(entity))
		{
			comp.Enabled = enabled;
		}

		if (mLightProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				mWorld?.SetLightEnabled(proxyHandle, enabled);
		}
	}

	/// Gets the light proxy for direct access.
	public LightProxy* GetLightProxy(EntityId entity)
	{
		if (mLightProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				return mWorld?.GetLight(proxyHandle);
		}
		return null;
	}

	// ==================== Particle Emitter API ====================

	/// Creates a particle emitter for an entity (GPU backend).
	public ParticleEmitterProxyHandle CreateParticleEmitter(EntityId entity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateParticleEmitter(backend: .GPU);

		// Store in internal tracking
		mParticleEmitterProxies[entity] = handle;

		// Ensure component exists and populate fields
		var comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<ParticleEmitterComponent>(entity, .Default);
			comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		}
		comp.Backend = .GPU;
		comp.Enabled = true;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetParticleEmitterPosition(handle, worldMatrix.Translation);

		return handle;
	}

	/// Gets the particle emitter proxy for direct access.
	public ParticleEmitterProxy* GetParticleEmitterProxy(EntityId entity)
	{
		if (mParticleEmitterProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				return mWorld?.GetParticleEmitter(proxyHandle);
		}
		return null;
	}

	/// Gets the particle emitter proxy handle for an entity.
	public ParticleEmitterProxyHandle GetParticleEmitterProxyHandle(EntityId entity)
	{
		if (mParticleEmitterProxies.TryGetValue(entity, let proxyHandle))
			return proxyHandle;
		return .Invalid;
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

		let handle = mWorld.CreateParticleEmitter(device, .CPU, maxParticles);

		// Store in internal tracking
		mParticleEmitterProxies[entity] = handle;

		// Ensure component exists
		var comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<ParticleEmitterComponent>(entity, .Default);
			comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		}
		comp.Backend = .CPU;
		comp.MaxParticles = (uint32)maxParticles;
		comp.Enabled = true;

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

		// Store in internal tracking
		mSpriteProxies[entity] = handle;

		// Ensure component exists with defaults
		var comp = mScene.GetComponent<SpriteComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<SpriteComponent>(entity, .Default);
			comp = mScene.GetComponent<SpriteComponent>(entity);
		}
		comp.Enabled = true;

		// Sync defaults to proxy
		if (let proxy = mWorld.GetSprite(handle))
		{
			proxy.Size = comp.Size;
			proxy.Color = .(comp.Color.X, comp.Color.Y, comp.Color.Z, comp.Color.W);
			proxy.UVRect = comp.UVRect;
			proxy.LayerMask = comp.LayerMask;
		}

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetSpritePosition(handle, worldMatrix.Translation);

		return handle;
	}

	/// Gets the sprite proxy for direct access.
	public SpriteProxy* GetSpriteProxy(EntityId entity)
	{
		if (mSpriteProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				return mWorld?.GetSprite(proxyHandle);
		}
		return null;
	}

	/// Sets sprite size.
	public void SetSpriteSize(EntityId entity, Vector2 size)
	{
		if (mSpriteProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				mWorld.SetSpriteSize(proxyHandle, size);
		}
		// Sync to component
		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<SpriteComponent>(entity))
				comp.Size = size;
		}
	}

	/// Sets sprite color.
	public void SetSpriteColor(EntityId entity, Color color)
	{
		if (mSpriteProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				mWorld.SetSpriteColor(proxyHandle, color);
		}
		// Sync to component (convert uint8 0-255 to float 0-1)
		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<SpriteComponent>(entity))
				comp.Color = .((float)color.R / 255.0f, (float)color.G / 255.0f, (float)color.B / 255.0f, (float)color.A / 255.0f);
		}
	}

	/// Sets sprite texture.
	public void SetSpriteTexture(EntityId entity, ITextureView texture)
	{
		if (mSpriteProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				mWorld.SetSpriteTexture(proxyHandle, texture);
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

		// Store in internal tracking
		mTrailEmitterProxies[entity] = handle;

		// Ensure component exists with defaults
		var comp = mScene.GetComponent<TrailEmitterComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<TrailEmitterComponent>(entity, .Default);
			comp = mScene.GetComponent<TrailEmitterComponent>(entity);
		}
		comp.MaxPoints = maxPoints;
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
		if (mTrailEmitterProxies.TryGetValue(entity, let proxyHandle))
		{
			if (proxyHandle.IsValid)
				return mWorld?.GetTrailEmitter(proxyHandle);
		}
		return null;
	}
}
