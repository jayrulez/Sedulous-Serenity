namespace Sedulous.RendererNG;

using System;
using System.Collections;

/// Container for all render proxies in a scene.
/// Manages the lifecycle of proxies and provides efficient access.
class RenderWorld
{
	// Proxy pools (~ delete _ ensures cleanup when RenderWorld is deleted)
	private ProxyPool<StaticMeshProxy> mStaticMeshes ~ delete _;
	private ProxyPool<SkinnedMeshProxy> mSkinnedMeshes ~ delete _;
	private ProxyPool<LightProxy> mLights ~ delete _;
	private ProxyPool<CameraProxy> mCameras ~ delete _;
	private ProxyPool<ParticleEmitterProxy> mParticleEmitters ~ delete _;
	private ProxyPool<SpriteProxy> mSprites ~ delete _;
	private ProxyPool<ForceFieldProxy> mForceFields ~ delete _;

	/// Gets the number of active static mesh proxies.
	public int32 StaticMeshCount => (int32)mStaticMeshes.AllocatedCount;

	/// Gets the number of active skinned mesh proxies.
	public int32 SkinnedMeshCount => (int32)mSkinnedMeshes.AllocatedCount;

	/// Gets the number of active light proxies.
	public int32 LightCount => (int32)mLights.AllocatedCount;

	/// Gets the number of active camera proxies.
	public int32 CameraCount => (int32)mCameras.AllocatedCount;

	/// Gets the number of active particle emitter proxies.
	public int32 ParticleEmitterCount => (int32)mParticleEmitters.AllocatedCount;

	/// Gets the number of active sprite proxies.
	public int32 SpriteCount => (int32)mSprites.AllocatedCount;

	/// Gets the number of active force field proxies.
	public int32 ForceFieldCount => (int32)mForceFields.AllocatedCount;

	public this()
	{
		mStaticMeshes = new ProxyPool<StaticMeshProxy>(RenderConfig.INITIAL_STATIC_MESH_PROXY_CAPACITY);
		mSkinnedMeshes = new ProxyPool<SkinnedMeshProxy>(RenderConfig.INITIAL_SKINNED_MESH_PROXY_CAPACITY);
		mLights = new ProxyPool<LightProxy>(RenderConfig.INITIAL_LIGHT_PROXY_CAPACITY);
		mCameras = new ProxyPool<CameraProxy>(RenderConfig.INITIAL_CAMERA_PROXY_CAPACITY);
		mParticleEmitters = new ProxyPool<ParticleEmitterProxy>(RenderConfig.INITIAL_PARTICLE_EMITTER_PROXY_CAPACITY);
		mSprites = new ProxyPool<SpriteProxy>(RenderConfig.INITIAL_SPRITE_PROXY_CAPACITY);
		mForceFields = new ProxyPool<ForceFieldProxy>(RenderConfig.INITIAL_FORCE_FIELD_PROXY_CAPACITY);
	}

	/// Called at the start of each frame.
	public void BeginFrame()
	{
		// Reserved for per-frame state reset
	}

	/// Called at the end of each frame.
	public void EndFrame()
	{
		// Reserved for saving previous transforms for motion vectors
	}

	// ===== Static Mesh Proxies =====

	/// Creates a new static mesh proxy.
	public ProxyHandle<StaticMeshProxy> CreateStaticMesh()
	{
		return mStaticMeshes.Create();
	}

	/// Creates a new static mesh proxy with initial data.
	public ProxyHandle<StaticMeshProxy> CreateStaticMesh(StaticMeshProxy initialData)
	{
		let handle = mStaticMeshes.Create();
		if (let ptr = mStaticMeshes.GetPtr(handle))
			*ptr = initialData;
		return handle;
	}

	/// Destroys a static mesh proxy.
	public void DestroyStaticMesh(ProxyHandle<StaticMeshProxy> handle)
	{
		mStaticMeshes.Destroy(handle);
	}

	/// Gets a pointer to a static mesh proxy.
	public StaticMeshProxy* GetStaticMesh(ProxyHandle<StaticMeshProxy> handle)
	{
		return mStaticMeshes.GetPtr(handle);
	}

	/// Iterates over all active static mesh proxies.
	public void ForEachStaticMesh(delegate void(ProxyHandle<StaticMeshProxy> handle, StaticMeshProxy* proxy) action)
	{
		mStaticMeshes.ForEach(action);
	}

	// ===== Skinned Mesh Proxies =====

	/// Creates a new skinned mesh proxy.
	public ProxyHandle<SkinnedMeshProxy> CreateSkinnedMesh()
	{
		return mSkinnedMeshes.Create();
	}

	/// Creates a new skinned mesh proxy with initial data.
	public ProxyHandle<SkinnedMeshProxy> CreateSkinnedMesh(SkinnedMeshProxy initialData)
	{
		let handle = mSkinnedMeshes.Create();
		if (let ptr = mSkinnedMeshes.GetPtr(handle))
			*ptr = initialData;
		return handle;
	}

	/// Destroys a skinned mesh proxy.
	public void DestroySkinnedMesh(ProxyHandle<SkinnedMeshProxy> handle)
	{
		mSkinnedMeshes.Destroy(handle);
	}

	/// Gets a pointer to a skinned mesh proxy.
	public SkinnedMeshProxy* GetSkinnedMesh(ProxyHandle<SkinnedMeshProxy> handle)
	{
		return mSkinnedMeshes.GetPtr(handle);
	}

	/// Iterates over all active skinned mesh proxies.
	public void ForEachSkinnedMesh(delegate void(ProxyHandle<SkinnedMeshProxy> handle, SkinnedMeshProxy* proxy) action)
	{
		mSkinnedMeshes.ForEach(action);
	}

	// ===== Light Proxies =====

	/// Creates a new light proxy.
	public ProxyHandle<LightProxy> CreateLight()
	{
		return mLights.Create();
	}

	/// Creates a new light proxy with initial data.
	public ProxyHandle<LightProxy> CreateLight(LightProxy initialData)
	{
		let handle = mLights.Create();
		if (let ptr = mLights.GetPtr(handle))
			*ptr = initialData;
		return handle;
	}

	/// Destroys a light proxy.
	public void DestroyLight(ProxyHandle<LightProxy> handle)
	{
		mLights.Destroy(handle);
	}

	/// Gets a pointer to a light proxy.
	public LightProxy* GetLight(ProxyHandle<LightProxy> handle)
	{
		return mLights.GetPtr(handle);
	}

	/// Iterates over all active light proxies.
	public void ForEachLight(delegate void(ProxyHandle<LightProxy> handle, LightProxy* proxy) action)
	{
		mLights.ForEach(action);
	}

	// ===== Camera Proxies =====

	/// Creates a new camera proxy.
	public ProxyHandle<CameraProxy> CreateCamera()
	{
		return mCameras.Create();
	}

	/// Creates a new camera proxy with initial data.
	public ProxyHandle<CameraProxy> CreateCamera(CameraProxy initialData)
	{
		let handle = mCameras.Create();
		if (let ptr = mCameras.GetPtr(handle))
			*ptr = initialData;
		return handle;
	}

	/// Destroys a camera proxy.
	public void DestroyCamera(ProxyHandle<CameraProxy> handle)
	{
		mCameras.Destroy(handle);
	}

	/// Gets a pointer to a camera proxy.
	public CameraProxy* GetCamera(ProxyHandle<CameraProxy> handle)
	{
		return mCameras.GetPtr(handle);
	}

	/// Iterates over all active camera proxies.
	public void ForEachCamera(delegate void(ProxyHandle<CameraProxy> handle, CameraProxy* proxy) action)
	{
		mCameras.ForEach(action);
	}

	// ===== Particle Emitter Proxies =====

	/// Creates a new particle emitter proxy.
	public ProxyHandle<ParticleEmitterProxy> CreateParticleEmitter()
	{
		return mParticleEmitters.Create();
	}

	/// Creates a new particle emitter proxy with initial data.
	public ProxyHandle<ParticleEmitterProxy> CreateParticleEmitter(ParticleEmitterProxy initialData)
	{
		let handle = mParticleEmitters.Create();
		if (let ptr = mParticleEmitters.GetPtr(handle))
			*ptr = initialData;
		return handle;
	}

	/// Destroys a particle emitter proxy.
	public void DestroyParticleEmitter(ProxyHandle<ParticleEmitterProxy> handle)
	{
		mParticleEmitters.Destroy(handle);
	}

	/// Gets a pointer to a particle emitter proxy.
	public ParticleEmitterProxy* GetParticleEmitter(ProxyHandle<ParticleEmitterProxy> handle)
	{
		return mParticleEmitters.GetPtr(handle);
	}

	/// Iterates over all active particle emitter proxies.
	public void ForEachParticleEmitter(delegate void(ProxyHandle<ParticleEmitterProxy> handle, ParticleEmitterProxy* proxy) action)
	{
		mParticleEmitters.ForEach(action);
	}

	// ===== Sprite Proxies =====

	/// Creates a new sprite proxy.
	public ProxyHandle<SpriteProxy> CreateSprite()
	{
		return mSprites.Create();
	}

	/// Creates a new sprite proxy with initial data.
	public ProxyHandle<SpriteProxy> CreateSprite(SpriteProxy initialData)
	{
		let handle = mSprites.Create();
		if (let ptr = mSprites.GetPtr(handle))
			*ptr = initialData;
		return handle;
	}

	/// Destroys a sprite proxy.
	public void DestroySprite(ProxyHandle<SpriteProxy> handle)
	{
		mSprites.Destroy(handle);
	}

	/// Gets a pointer to a sprite proxy.
	public SpriteProxy* GetSprite(ProxyHandle<SpriteProxy> handle)
	{
		return mSprites.GetPtr(handle);
	}

	/// Iterates over all active sprite proxies.
	public void ForEachSprite(delegate void(ProxyHandle<SpriteProxy> handle, SpriteProxy* proxy) action)
	{
		mSprites.ForEach(action);
	}

	// ===== Force Field Proxies =====

	/// Creates a new force field proxy.
	public ProxyHandle<ForceFieldProxy> CreateForceField()
	{
		return mForceFields.Create();
	}

	/// Creates a new force field proxy with initial data.
	public ProxyHandle<ForceFieldProxy> CreateForceField(ForceFieldProxy initialData)
	{
		let handle = mForceFields.Create();
		if (let ptr = mForceFields.GetPtr(handle))
			*ptr = initialData;
		return handle;
	}

	/// Destroys a force field proxy.
	public void DestroyForceField(ProxyHandle<ForceFieldProxy> handle)
	{
		mForceFields.Destroy(handle);
	}

	/// Gets a pointer to a force field proxy.
	public ForceFieldProxy* GetForceField(ProxyHandle<ForceFieldProxy> handle)
	{
		return mForceFields.GetPtr(handle);
	}

	/// Iterates over all active force field proxies.
	public void ForEachForceField(delegate void(ProxyHandle<ForceFieldProxy> handle, ForceFieldProxy* proxy) action)
	{
		mForceFields.ForEach(action);
	}

	/// Clears all proxies from the world.
	public void Clear()
	{
		mStaticMeshes.Clear();
		mSkinnedMeshes.Clear();
		mLights.Clear();
		mCameras.Clear();
		mParticleEmitters.Clear();
		mSprites.Clear();
		mForceFields.Clear();
	}

}
