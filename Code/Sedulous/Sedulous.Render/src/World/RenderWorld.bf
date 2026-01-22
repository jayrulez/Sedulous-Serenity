namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Materials;
using Sedulous.RHI;

/// Container for all renderable objects in a scene.
/// Manages proxy pools for meshes, lights, particles, etc.
public class RenderWorld : IDisposable
{
	// Proxy pools
	private ProxyPool<MeshProxy> mMeshProxies = new .() ~ delete _;
	private ProxyPool<SkinnedMeshProxy> mSkinnedMeshProxies = new .() ~ delete _;
	private ProxyPool<LightProxy> mLightProxies = new .() ~ delete _;
	private ProxyPool<CameraProxy> mCameraProxies = new .() ~ delete _;
	private ProxyPool<ParticleEmitterProxy> mParticleProxies = new .() ~ delete _;
	private ProxyPool<SpriteProxy> mSpriteProxies = new .() ~ delete _;

	// Main camera handle
	private CameraProxyHandle mMainCamera = .Invalid;

	// Environment lighting settings
	private Vector3 mAmbientColor = .(0.03f, 0.03f, 0.03f);
	private float mAmbientIntensity = 1.0f;
	private float mExposure = 1.0f;
	private bool mEnvironmentDirty = true;

	// Dirty tracking
	private bool mMeshesDirty = false;
	private bool mSkinnedMeshesDirty = false;
	private bool mLightsDirty = false;
	private bool mCamerasDirty = false;
	private bool mParticlesDirty = false;
	private bool mSpritesDirty = false;

	/// Gets the mesh proxy pool.
	public ProxyPool<MeshProxy> MeshProxies => mMeshProxies;

	/// Gets the skinned mesh proxy pool.
	public ProxyPool<SkinnedMeshProxy> SkinnedMeshProxies => mSkinnedMeshProxies;

	/// Gets the light proxy pool.
	public ProxyPool<LightProxy> LightProxies => mLightProxies;

	/// Gets the camera proxy pool.
	public ProxyPool<CameraProxy> CameraProxies => mCameraProxies;

	/// Gets the particle emitter proxy pool.
	public ProxyPool<ParticleEmitterProxy> ParticleProxies => mParticleProxies;

	/// Gets the sprite proxy pool.
	public ProxyPool<SpriteProxy> SpriteProxies => mSpriteProxies;

	/// Gets the main camera handle.
	public CameraProxyHandle MainCamera => mMainCamera;

	/// Gets the number of active meshes.
	public int32 MeshCount => mMeshProxies.ActiveCount;

	/// Gets the number of active skinned meshes.
	public int32 SkinnedMeshCount => mSkinnedMeshProxies.ActiveCount;

	/// Gets the number of active lights.
	public int32 LightCount => mLightProxies.ActiveCount;

	/// Gets the number of active cameras.
	public int32 CameraCount => mCameraProxies.ActiveCount;

	/// Gets the number of active particle emitters.
	public int32 ParticleEmitterCount => mParticleProxies.ActiveCount;

	/// Gets the number of active sprites.
	public int32 SpriteCount => mSpriteProxies.ActiveCount;

	/// Whether any meshes have changed.
	public bool MeshesDirty => mMeshesDirty;

	/// Whether any skinned meshes have changed.
	public bool SkinnedMeshesDirty => mSkinnedMeshesDirty;

	/// Whether any lights have changed.
	public bool LightsDirty => mLightsDirty;

	/// Whether any cameras have changed.
	public bool CamerasDirty => mCamerasDirty;

	/// Whether any particles have changed.
	public bool ParticlesDirty => mParticlesDirty;

	/// Whether any sprites have changed.
	public bool SpritesDirty => mSpritesDirty;

	/// Whether environment settings have changed.
	public bool EnvironmentDirty => mEnvironmentDirty;

	// ========================================================================
	// Environment Lighting API
	// ========================================================================

	/// Gets or sets the ambient light color.
	public Vector3 AmbientColor
	{
		get => mAmbientColor;
		set { mAmbientColor = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the ambient light intensity.
	public float AmbientIntensity
	{
		get => mAmbientIntensity;
		set { mAmbientIntensity = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the exposure value for tonemapping.
	public float Exposure
	{
		get => mExposure;
		set { mExposure = value; mEnvironmentDirty = true; }
	}

	/// Clears the environment dirty flag.
	public void ClearEnvironmentDirty() { mEnvironmentDirty = false; }

	// ========================================================================
	// Mesh API
	// ========================================================================

	/// Creates a new mesh proxy.
	public MeshProxyHandle CreateMesh()
	{
		let handle = mMeshProxies.Allocate();
		var proxy = mMeshProxies.Get(handle);
		proxy.Reset();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		proxy.Flags = .DefaultOpaque;
		mMeshesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a mesh proxy by handle.
	public MeshProxy* GetMesh(MeshProxyHandle handle)
	{
		return mMeshProxies.Get(handle.Handle);
	}

	/// Gets a reference to a mesh proxy.
	public ref MeshProxy GetMeshRef(MeshProxyHandle handle)
	{
		return ref mMeshProxies.GetRef(handle.Handle);
	}

	/// Destroys a mesh proxy.
	public void DestroyMesh(MeshProxyHandle handle)
	{
		if (mMeshProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mMeshProxies.Free(handle.Handle);
		mMeshesDirty = true;
	}

	/// Sets mesh transform.
	public void SetMeshTransform(MeshProxyHandle handle, Matrix worldMatrix)
	{
		if (let proxy = mMeshProxies.Get(handle.Handle))
		{
			proxy.SetTransform(worldMatrix);
			mMeshesDirty = true;
		}
	}

	/// Sets mesh GPU handle and bounds.
	public void SetMeshData(MeshProxyHandle handle, GPUMeshHandle meshHandle, BoundingBox localBounds)
	{
		if (let proxy = mMeshProxies.Get(handle.Handle))
		{
			proxy.MeshHandle = meshHandle;
			proxy.SetLocalBounds(localBounds);
			mMeshesDirty = true;
		}
	}

	/// Sets mesh material.
	public void SetMeshMaterial(MeshProxyHandle handle, MaterialInstance material)
	{
		if (let proxy = mMeshProxies.Get(handle.Handle))
		{
			proxy.Material = material;
			mMeshesDirty = true;
		}
	}

	/// Sets mesh flags.
	public void SetMeshFlags(MeshProxyHandle handle, MeshFlags flags)
	{
		if (let proxy = mMeshProxies.Get(handle.Handle))
		{
			proxy.Flags = flags;
			mMeshesDirty = true;
		}
	}

	/// Iterates over all active meshes.
	public void ForEachMesh(ProxyCallback<MeshProxy> callback)
	{
		mMeshProxies.ForEach(callback);
	}

	// ========================================================================
	// Skinned Mesh API
	// ========================================================================

	/// Creates a new skinned mesh proxy.
	public SkinnedMeshProxyHandle CreateSkinnedMesh()
	{
		let handle = mSkinnedMeshProxies.Allocate();
		var proxy = mSkinnedMeshProxies.Get(handle);
		proxy.Reset();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		proxy.Flags = .DefaultOpaque;
		mSkinnedMeshesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a skinned mesh proxy by handle.
	public SkinnedMeshProxy* GetSkinnedMesh(SkinnedMeshProxyHandle handle)
	{
		return mSkinnedMeshProxies.Get(handle.Handle);
	}

	/// Gets a reference to a skinned mesh proxy.
	public ref SkinnedMeshProxy GetSkinnedMeshRef(SkinnedMeshProxyHandle handle)
	{
		return ref mSkinnedMeshProxies.GetRef(handle.Handle);
	}

	/// Destroys a skinned mesh proxy.
	public void DestroySkinnedMesh(SkinnedMeshProxyHandle handle)
	{
		if (mSkinnedMeshProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mSkinnedMeshProxies.Free(handle.Handle);
		mSkinnedMeshesDirty = true;
	}

	/// Sets skinned mesh transform.
	public void SetSkinnedMeshTransform(SkinnedMeshProxyHandle handle, Matrix worldMatrix)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			proxy.SetTransform(worldMatrix);
			mSkinnedMeshesDirty = true;
		}
	}

	/// Sets skinned mesh GPU handles and bounds.
	public void SetSkinnedMeshData(SkinnedMeshProxyHandle handle, GPUMeshHandle meshHandle, GPUBoneBufferHandle boneBufferHandle, BoundingBox localBounds, uint16 boneCount)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			proxy.MeshHandle = meshHandle;
			proxy.BoneBufferHandle = boneBufferHandle;
			proxy.BoneCount = boneCount;
			proxy.SetLocalBounds(localBounds);
			mSkinnedMeshesDirty = true;
		}
	}

	/// Sets skinned mesh material.
	public void SetSkinnedMeshMaterial(SkinnedMeshProxyHandle handle, MaterialInstance material)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			proxy.Material = material;
			mSkinnedMeshesDirty = true;
		}
	}

	/// Sets skinned mesh flags.
	public void SetSkinnedMeshFlags(SkinnedMeshProxyHandle handle, MeshFlags flags)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			proxy.Flags = flags;
			mSkinnedMeshesDirty = true;
		}
	}

	/// Marks skinned mesh bones as dirty (need GPU upload).
	public void MarkSkinnedMeshBonesDirty(SkinnedMeshProxyHandle handle)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			proxy.MarkBonesDirty();
			mSkinnedMeshesDirty = true;
		}
	}

	/// Iterates over all active skinned meshes.
	public void ForEachSkinnedMesh(ProxyCallback<SkinnedMeshProxy> callback)
	{
		mSkinnedMeshProxies.ForEach(callback);
	}

	// ========================================================================
	// Light API
	// ========================================================================

	/// Creates a new light proxy.
	public LightProxyHandle CreateLight(LightType type = .Point)
	{
		let handle = mLightProxies.Allocate();
		var proxy = mLightProxies.Get(handle);
		proxy.Reset();
		proxy.Type = type;
		proxy.IsActive = true;
		proxy.IsEnabled = true;
		proxy.Generation = handle.Generation;
		mLightsDirty = true;
		return .() { Handle = handle };
	}

	/// Creates a directional light.
	public LightProxyHandle CreateDirectionalLight(Vector3 direction, Vector3 color, float intensity)
	{
		let handle = CreateLight(.Directional);
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			*proxy = LightProxy.CreateDirectional(direction, color, intensity);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Creates a point light.
	public LightProxyHandle CreatePointLight(Vector3 position, Vector3 color, float intensity, float range)
	{
		let handle = CreateLight(.Point);
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			*proxy = LightProxy.CreatePoint(position, color, intensity, range);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Creates a spot light.
	public LightProxyHandle CreateSpotLight(Vector3 position, Vector3 direction, Vector3 color, float intensity, float range, float innerAngle, float outerAngle)
	{
		let handle = CreateLight(.Spot);
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			*proxy = LightProxy.CreateSpot(position, direction, color, intensity, range, innerAngle, outerAngle);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Gets a light proxy by handle.
	public LightProxy* GetLight(LightProxyHandle handle)
	{
		return mLightProxies.Get(handle.Handle);
	}

	/// Gets a reference to a light proxy.
	public ref LightProxy GetLightRef(LightProxyHandle handle)
	{
		return ref mLightProxies.GetRef(handle.Handle);
	}

	/// Destroys a light proxy.
	public void DestroyLight(LightProxyHandle handle)
	{
		if (mLightProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mLightProxies.Free(handle.Handle);
		mLightsDirty = true;
	}

	/// Sets light position.
	public void SetLightPosition(LightProxyHandle handle, Vector3 position)
	{
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			proxy.Position = position;
			mLightsDirty = true;
		}
	}

	/// Sets light direction.
	public void SetLightDirection(LightProxyHandle handle, Vector3 direction)
	{
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			proxy.Direction = Vector3.Normalize(direction);
			mLightsDirty = true;
		}
	}

	/// Sets light color and intensity.
	public void SetLightColor(LightProxyHandle handle, Vector3 color, float intensity)
	{
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			proxy.Color = color;
			proxy.Intensity = intensity;
			mLightsDirty = true;
		}
	}

	/// Enables or disables a light.
	public void SetLightEnabled(LightProxyHandle handle, bool enabled)
	{
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			proxy.IsEnabled = enabled;
			mLightsDirty = true;
		}
	}

	/// Iterates over all active lights.
	public void ForEachLight(ProxyCallback<LightProxy> callback)
	{
		mLightProxies.ForEach(callback);
	}

	// ========================================================================
	// Camera API
	// ========================================================================

	/// Creates a new camera proxy.
	public CameraProxyHandle CreateCamera()
	{
		let handle = mCameraProxies.Allocate();
		var proxy = mCameraProxies.Get(handle);
		proxy.Reset();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mCamerasDirty = true;
		return .() { Handle = handle };
	}

	/// Creates a perspective camera.
	public CameraProxyHandle CreatePerspectiveCamera(Vector3 position, Vector3 target, Vector3 up, float fov, float aspectRatio, float nearPlane, float farPlane)
	{
		let handle = CreateCamera();
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			*proxy = CameraProxy.CreatePerspective(position, target, up, fov, aspectRatio, nearPlane, farPlane);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Creates an orthographic camera.
	public CameraProxyHandle CreateOrthographicCamera(Vector3 position, Vector3 target, Vector3 up, float width, float height, float nearPlane, float farPlane)
	{
		let handle = CreateCamera();
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			*proxy = CameraProxy.CreateOrthographic(position, target, up, width, height, nearPlane, farPlane);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Gets a camera proxy by handle.
	public CameraProxy* GetCamera(CameraProxyHandle handle)
	{
		return mCameraProxies.Get(handle.Handle);
	}

	/// Gets a reference to a camera proxy.
	public ref CameraProxy GetCameraRef(CameraProxyHandle handle)
	{
		return ref mCameraProxies.GetRef(handle.Handle);
	}

	/// Destroys a camera proxy.
	public void DestroyCamera(CameraProxyHandle handle)
	{
		// If this was the main camera, clear it
		if (mMainCamera == handle)
			mMainCamera = .Invalid;

		if (mCameraProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mCameraProxies.Free(handle.Handle);
		mCamerasDirty = true;
	}

	/// Sets the main camera.
	public void SetMainCamera(CameraProxyHandle handle)
	{
		mMainCamera = handle;
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.IsMainCamera = true;
		}
		mCamerasDirty = true;
	}

	/// Sets camera position and orientation using look-at.
	public void SetCameraLookAt(CameraProxyHandle handle, Vector3 position, Vector3 target, Vector3 up)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.SetLookAt(position, target, up);
			mCamerasDirty = true;
		}
	}

	/// Sets camera position and direction.
	public void SetCameraPositionDirection(CameraProxyHandle handle, Vector3 position, Vector3 forward, Vector3 up)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.SetPositionDirection(position, forward, up);
			mCamerasDirty = true;
		}
	}

	/// Updates camera matrices. Should be called after changing position/orientation.
	public void UpdateCameraMatrices(CameraProxyHandle handle, bool flipY = false)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.UpdateMatrices(flipY);
			mCamerasDirty = true;
		}
	}

	/// Sets camera TAA jitter for the current frame.
	public void SetCameraJitter(CameraProxyHandle handle, Vector2 pixelOffset, uint32 viewportWidth, uint32 viewportHeight)
	{
		if (let proxy = mCameraProxies.Get(handle.Handle))
		{
			proxy.SetJitter(pixelOffset, viewportWidth, viewportHeight);
			mCamerasDirty = true;
		}
	}

	/// Iterates over all active cameras.
	public void ForEachCamera(ProxyCallback<CameraProxy> callback)
	{
		mCameraProxies.ForEach(callback);
	}

	// ========================================================================
	// Particle API
	// ========================================================================

	/// Creates a new particle emitter proxy.
	public ParticleEmitterProxyHandle CreateParticleEmitter()
	{
		let handle = mParticleProxies.Allocate();
		var proxy = mParticleProxies.Get(handle);
		*proxy = ParticleEmitterProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mParticlesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a particle emitter proxy by handle.
	public ParticleEmitterProxy* GetParticleEmitter(ParticleEmitterProxyHandle handle)
	{
		return mParticleProxies.Get(handle.Handle);
	}

	/// Gets a reference to a particle emitter proxy.
	public ref ParticleEmitterProxy GetParticleEmitterRef(ParticleEmitterProxyHandle handle)
	{
		return ref mParticleProxies.GetRef(handle.Handle);
	}

	/// Destroys a particle emitter proxy.
	public void DestroyParticleEmitter(ParticleEmitterProxyHandle handle)
	{
		if (mParticleProxies.TryGet(handle.Handle, let proxy))
		{
			if (proxy.CPUEmitter != null)
			{
				delete proxy.CPUEmitter;
				proxy.CPUEmitter = null;
			}
			proxy.Reset();
		}
		mParticleProxies.Free(handle.Handle);
		mParticlesDirty = true;
	}

	/// Sets particle emitter position.
	public void SetParticleEmitterPosition(ParticleEmitterProxyHandle handle, Vector3 position)
	{
		if (let proxy = mParticleProxies.Get(handle.Handle))
		{
			proxy.SetPosition(position);
			mParticlesDirty = true;
		}
	}

	/// Iterates over all active particle emitters.
	public void ForEachParticleEmitter(ProxyCallback<ParticleEmitterProxy> callback)
	{
		mParticleProxies.ForEach(callback);
	}

	// ========================================================================
	// Sprite API
	// ========================================================================

	/// Creates a new sprite proxy.
	public SpriteProxyHandle CreateSprite()
	{
		let handle = mSpriteProxies.Allocate();
		var proxy = mSpriteProxies.Get(handle);
		*proxy = SpriteProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mSpritesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a sprite proxy by handle.
	public SpriteProxy* GetSprite(SpriteProxyHandle handle)
	{
		return mSpriteProxies.Get(handle.Handle);
	}

	/// Gets a reference to a sprite proxy.
	public ref SpriteProxy GetSpriteRef(SpriteProxyHandle handle)
	{
		return ref mSpriteProxies.GetRef(handle.Handle);
	}

	/// Destroys a sprite proxy.
	public void DestroySprite(SpriteProxyHandle handle)
	{
		if (mSpriteProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mSpriteProxies.Free(handle.Handle);
		mSpritesDirty = true;
	}

	/// Sets sprite position.
	public void SetSpritePosition(SpriteProxyHandle handle, Vector3 position)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Position = position;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite size.
	public void SetSpriteSize(SpriteProxyHandle handle, Vector2 size)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Size = size;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite color.
	public void SetSpriteColor(SpriteProxyHandle handle, Color color)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Color = color;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite texture.
	public void SetSpriteTexture(SpriteProxyHandle handle, ITextureView texture)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Texture = texture;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite UV rect for atlas sub-regions.
	public void SetSpriteUVRect(SpriteProxyHandle handle, Vector4 uvRect)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.UVRect = uvRect;
			mSpritesDirty = true;
		}
	}

	/// Iterates over all active sprites.
	public void ForEachSprite(ProxyCallback<SpriteProxy> callback)
	{
		mSpriteProxies.ForEach(callback);
	}

	// ========================================================================
	// General
	// ========================================================================

	/// Clears dirty flags after processing.
	public void ClearDirtyFlags()
	{
		mMeshesDirty = false;
		mSkinnedMeshesDirty = false;
		mLightsDirty = false;
		mCamerasDirty = false;
		mParticlesDirty = false;
		mSpritesDirty = false;
	}

	/// Clears all objects from the world.
	public void Clear()
	{
		// Delete owned CPUParticleEmitter instances before clearing proxies
		mParticleProxies.ForEach(scope (handle, proxy) =>
		{
			if (proxy.CPUEmitter != null)
			{
				delete proxy.CPUEmitter;
				proxy.CPUEmitter = null;
			}
		});

		mMeshProxies.Clear();
		mSkinnedMeshProxies.Clear();
		mLightProxies.Clear();
		mCameraProxies.Clear();
		mParticleProxies.Clear();
		mSpriteProxies.Clear();
		mMainCamera = .Invalid;
		mMeshesDirty = true;
		mSkinnedMeshesDirty = true;
		mLightsDirty = true;
		mCamerasDirty = true;
		mParticlesDirty = true;
		mSpritesDirty = true;
	}

	public void Dispose()
	{
		Clear();
	}
}
