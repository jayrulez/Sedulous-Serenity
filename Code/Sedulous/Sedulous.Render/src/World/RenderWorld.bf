namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Materials;

/// Container for all renderable objects in a scene.
/// Manages proxy pools for meshes, lights, particles, etc.
public class RenderWorld : IDisposable
{
	// Proxy pools
	private ProxyPool<MeshProxy> mMeshProxies = new .() ~ delete _;
	private ProxyPool<LightProxy> mLightProxies = new .() ~ delete _;
	private ProxyPool<ParticleEmitterProxy> mParticleProxies = new .() ~ delete _;

	// Dirty tracking
	private bool mMeshesDirty = false;
	private bool mLightsDirty = false;
	private bool mParticlesDirty = false;

	/// Gets the mesh proxy pool.
	public ProxyPool<MeshProxy> MeshProxies => mMeshProxies;

	/// Gets the light proxy pool.
	public ProxyPool<LightProxy> LightProxies => mLightProxies;

	/// Gets the particle emitter proxy pool.
	public ProxyPool<ParticleEmitterProxy> ParticleProxies => mParticleProxies;

	/// Gets the number of active meshes.
	public int32 MeshCount => mMeshProxies.ActiveCount;

	/// Gets the number of active lights.
	public int32 LightCount => mLightProxies.ActiveCount;

	/// Gets the number of active particle emitters.
	public int32 ParticleEmitterCount => mParticleProxies.ActiveCount;

	/// Whether any meshes have changed.
	public bool MeshesDirty => mMeshesDirty;

	/// Whether any lights have changed.
	public bool LightsDirty => mLightsDirty;

	/// Whether any particles have changed.
	public bool ParticlesDirty => mParticlesDirty;

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
	// General
	// ========================================================================

	/// Clears dirty flags after processing.
	public void ClearDirtyFlags()
	{
		mMeshesDirty = false;
		mLightsDirty = false;
		mParticlesDirty = false;
	}

	/// Clears all objects from the world.
	public void Clear()
	{
		mMeshProxies.Clear();
		mLightProxies.Clear();
		mParticleProxies.Clear();
		mMeshesDirty = true;
		mLightsDirty = true;
		mParticlesDirty = true;
	}

	public void Dispose()
	{
		Clear();
	}
}
