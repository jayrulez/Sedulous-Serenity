namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Handle to a proxy in RenderWorld.
struct ProxyHandle : IEquatable<ProxyHandle>, IHashable
{
	public uint32 Index;
	public uint32 Generation;

	public static readonly Self Invalid = .((uint32)-1, 0);

	public this(uint32 index, uint32 generation)
	{
		Index = index;
		Generation = generation;
	}

	public bool IsValid => Index != (uint32)-1;

	public bool Equals(ProxyHandle other) => Index == other.Index && Generation == other.Generation;
	public int GetHashCode() => (int)(Index ^ (Generation << 16));
}

/// Manages render proxies for a scene.
/// Provides efficient storage and access to meshes, lights, and cameras.
class RenderWorld
{
	// Mesh proxies
	private List<MeshProxy> mMeshProxies = new .() ~ delete _;
	private List<uint32> mMeshGenerations = new .() ~ delete _;
	private List<uint32> mFreeMeshSlots = new .() ~ delete _;
	private uint32 mMeshCount = 0;

	// Light proxies
	private List<LightProxy> mLightProxies = new .() ~ delete _;
	private List<uint32> mLightGenerations = new .() ~ delete _;
	private List<uint32> mFreeLightSlots = new .() ~ delete _;
	private uint32 mLightCount = 0;

	// Camera proxies
	private List<CameraProxy> mCameraProxies = new .() ~ delete _;
	private List<uint32> mCameraGenerations = new .() ~ delete _;
	private List<uint32> mFreeCameraSlots = new .() ~ delete _;
	private uint32 mCameraCount = 0;

	// Main camera handle
	private ProxyHandle mMainCamera = .Invalid;

	// Dirty flags for GPU sync
	private bool mMeshesDirty = true;
	private bool mLightsDirty = true;
	private bool mCamerasDirty = true;

	// ==================== Mesh Proxy Management ====================

	/// Creates a new mesh proxy.
	public ProxyHandle CreateMeshProxy(GPUMeshHandle mesh, Matrix4x4 transform, BoundingBox localBounds)
	{
		uint32 index;
		uint32 generation;

		if (mFreeMeshSlots.Count > 0)
		{
			index = mFreeMeshSlots.PopBack();
			generation = mMeshGenerations[(int)index] + 1;
			mMeshGenerations[(int)index] = generation;
		}
		else
		{
			index = (uint32)mMeshProxies.Count;
			generation = 1;
			mMeshProxies.Add(.Invalid);
			mMeshGenerations.Add(generation);
		}

		let proxy = MeshProxy(index, mesh, transform, localBounds);
		mMeshProxies[(int)index] = proxy;
		mMeshCount++;
		mMeshesDirty = true;

		return .(index, generation);
	}

	/// Gets a mesh proxy by handle.
	public MeshProxy* GetMeshProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return null;
		if (handle.Index >= (uint32)mMeshProxies.Count)
			return null;
		if (mMeshGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return &mMeshProxies[(int)handle.Index];
	}

	/// Updates a mesh proxy's transform.
	public void SetMeshTransform(ProxyHandle handle, Matrix4x4 transform)
	{
		if (let proxy = GetMeshProxy(handle))
		{
			proxy.Transform = transform;
			proxy.UpdateWorldBounds();
			proxy.Flags |= .Dirty;
			mMeshesDirty = true;
		}
	}

	/// Destroys a mesh proxy.
	public void DestroyMeshProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return;
		if (handle.Index >= (uint32)mMeshProxies.Count)
			return;
		if (mMeshGenerations[(int)handle.Index] != handle.Generation)
			return;

		mMeshProxies[(int)handle.Index] = .Invalid;
		mFreeMeshSlots.Add(handle.Index);
		mMeshCount--;
		mMeshesDirty = true;
	}

	/// Gets all valid mesh proxies.
	public void GetValidMeshProxies(List<MeshProxy*> outProxies)
	{
		outProxies.Clear();
		for (var i < mMeshProxies.Count)
		{
			if (mMeshProxies[i].IsValid)
				outProxies.Add(&mMeshProxies[i]);
		}
	}

	/// Number of active mesh proxies.
	public uint32 MeshCount => mMeshCount;

	// ==================== Light Proxy Management ====================

	/// Creates a directional light.
	public ProxyHandle CreateDirectionalLight(Vector3 direction, Vector3 color, float intensity = 1.0f)
	{
		let (index, generation) = AllocateLightSlot();
		mLightProxies[(int)index] = .CreateDirectional(index, direction, color, intensity);
		mLightCount++;
		mLightsDirty = true;
		return .(index, generation);
	}

	/// Creates a point light.
	public ProxyHandle CreatePointLight(Vector3 position, Vector3 color, float intensity, float range)
	{
		let (index, generation) = AllocateLightSlot();
		mLightProxies[(int)index] = .CreatePoint(index, position, color, intensity, range);
		mLightCount++;
		mLightsDirty = true;
		return .(index, generation);
	}

	/// Creates a spot light.
	public ProxyHandle CreateSpotLight(Vector3 position, Vector3 direction, Vector3 color,
		float intensity, float range, float innerAngle, float outerAngle)
	{
		let (index, generation) = AllocateLightSlot();
		mLightProxies[(int)index] = .CreateSpot(index, position, direction, color, intensity, range, innerAngle, outerAngle);
		mLightCount++;
		mLightsDirty = true;
		return .(index, generation);
	}

	/// Gets a light proxy by handle.
	public LightProxy* GetLightProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return null;
		if (handle.Index >= (uint32)mLightProxies.Count)
			return null;
		if (mLightGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return &mLightProxies[(int)handle.Index];
	}

	/// Destroys a light proxy.
	public void DestroyLightProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return;
		if (handle.Index >= (uint32)mLightProxies.Count)
			return;
		if (mLightGenerations[(int)handle.Index] != handle.Generation)
			return;

		mLightProxies[(int)handle.Index] = .Invalid;
		mFreeLightSlots.Add(handle.Index);
		mLightCount--;
		mLightsDirty = true;
	}

	/// Gets all valid light proxies.
	public void GetValidLightProxies(List<LightProxy*> outProxies)
	{
		outProxies.Clear();
		for (var i < mLightProxies.Count)
		{
			if (mLightProxies[i].IsValid && mLightProxies[i].Enabled)
				outProxies.Add(&mLightProxies[i]);
		}
	}

	/// Number of active light proxies.
	public uint32 LightCount => mLightCount;

	private (uint32 index, uint32 generation) AllocateLightSlot()
	{
		uint32 index;
		uint32 generation;

		if (mFreeLightSlots.Count > 0)
		{
			index = mFreeLightSlots.PopBack();
			generation = mLightGenerations[(int)index] + 1;
			mLightGenerations[(int)index] = generation;
		}
		else
		{
			index = (uint32)mLightProxies.Count;
			generation = 1;
			mLightProxies.Add(.Invalid);
			mLightGenerations.Add(generation);
		}

		return (index, generation);
	}

	// ==================== Camera Proxy Management ====================

	/// Creates a camera proxy.
	public ProxyHandle CreateCamera(Camera camera, uint32 viewportWidth, uint32 viewportHeight, bool isMain = false)
	{
		uint32 index;
		uint32 generation;

		if (mFreeCameraSlots.Count > 0)
		{
			index = mFreeCameraSlots.PopBack();
			generation = mCameraGenerations[(int)index] + 1;
			mCameraGenerations[(int)index] = generation;
		}
		else
		{
			index = (uint32)mCameraProxies.Count;
			generation = 1;
			mCameraProxies.Add(.Invalid);
			mCameraGenerations.Add(generation);
		}

		var proxy = CameraProxy.FromCamera(index, camera, viewportWidth, viewportHeight);
		proxy.IsMain = isMain;
		mCameraProxies[(int)index] = proxy;
		mCameraCount++;
		mCamerasDirty = true;

		let handle = ProxyHandle(index, generation);
		if (isMain)
			mMainCamera = handle;

		return handle;
	}

	/// Gets a camera proxy by handle.
	public CameraProxy* GetCameraProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return null;
		if (handle.Index >= (uint32)mCameraProxies.Count)
			return null;
		if (mCameraGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return &mCameraProxies[(int)handle.Index];
	}

	/// Gets the main camera proxy.
	public CameraProxy* MainCamera => GetCameraProxy(mMainCamera);

	/// Sets the main camera.
	public void SetMainCamera(ProxyHandle handle)
	{
		// Clear old main camera flag
		if (let oldMain = GetCameraProxy(mMainCamera))
			oldMain.IsMain = false;

		mMainCamera = handle;

		// Set new main camera flag
		if (let newMain = GetCameraProxy(mMainCamera))
			newMain.IsMain = true;
	}

	/// Destroys a camera proxy.
	public void DestroyCameraProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return;
		if (handle.Index >= (uint32)mCameraProxies.Count)
			return;
		if (mCameraGenerations[(int)handle.Index] != handle.Generation)
			return;

		if (mMainCamera.Equals(handle))
			mMainCamera = .Invalid;

		mCameraProxies[(int)handle.Index] = .Invalid;
		mFreeCameraSlots.Add(handle.Index);
		mCameraCount--;
		mCamerasDirty = true;
	}

	/// Number of active camera proxies.
	public uint32 CameraCount => mCameraCount;

	// ==================== Frame Updates ====================

	/// Called at the start of a frame to prepare proxies.
	public void BeginFrame()
	{
		// Update all camera matrices
		for (var i < mCameraProxies.Count)
		{
			if (mCameraProxies[i].IsValid && mCameraProxies[i].Enabled)
				mCameraProxies[i].UpdateMatrices();
		}
	}

	/// Called at the end of a frame to save previous state.
	public void EndFrame()
	{
		// Save previous transforms for motion vectors
		for (var i < mMeshProxies.Count)
		{
			if (mMeshProxies[i].IsValid)
			{
				mMeshProxies[i].SavePreviousTransform();
				mMeshProxies[i].Flags &= ~.Dirty;
				mMeshProxies[i].Flags &= ~.Culled;
			}
		}

		mMeshesDirty = false;
		mLightsDirty = false;
		mCamerasDirty = false;
	}

	/// Clears all proxies.
	public void Clear()
	{
		mMeshProxies.Clear();
		mMeshGenerations.Clear();
		mFreeMeshSlots.Clear();
		mMeshCount = 0;

		mLightProxies.Clear();
		mLightGenerations.Clear();
		mFreeLightSlots.Clear();
		mLightCount = 0;

		mCameraProxies.Clear();
		mCameraGenerations.Clear();
		mFreeCameraSlots.Clear();
		mCameraCount = 0;

		mMainCamera = .Invalid;

		mMeshesDirty = true;
		mLightsDirty = true;
		mCamerasDirty = true;
	}

	// ==================== Queries ====================

	/// Gets all mesh proxies within a bounding box.
	public void GetMeshesInBounds(BoundingBox bounds, List<ProxyHandle> outHandles)
	{
		outHandles.Clear();
		for (var i < mMeshProxies.Count)
		{
			let proxy = mMeshProxies[i];
			if (proxy.IsValid && proxy.WorldBounds.Intersects(bounds))
				outHandles.Add(.(proxy.Id, mMeshGenerations[i]));
		}
	}

	/// Gets lights affecting a point.
	public void GetLightsAtPoint(Vector3 point, List<ProxyHandle> outHandles)
	{
		outHandles.Clear();
		for (var i < mLightProxies.Count)
		{
			let proxy = mLightProxies[i];
			if (!proxy.IsValid || !proxy.Enabled)
				continue;

			if (proxy.Type == .Directional)
			{
				outHandles.Add(.(proxy.Id, mLightGenerations[i]));
			}
			else
			{
				float dist = Vector3.Distance(point, proxy.Position);
				if (dist <= proxy.Range)
					outHandles.Add(.(proxy.Id, mLightGenerations[i]));
			}
		}
	}

	/// Dirty flags
	public bool MeshesDirty => mMeshesDirty;
	public bool LightsDirty => mLightsDirty;
	public bool CamerasDirty => mCamerasDirty;
}
