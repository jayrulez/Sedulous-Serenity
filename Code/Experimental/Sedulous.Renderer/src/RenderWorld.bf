namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;

/// Proxy pool container — the bridge between game code and the renderer.
/// Game code creates/updates proxies here; the renderer reads them each frame.
class RenderWorld
{
	private ProxyPool<StaticMeshProxy> mStaticMeshes = new .() ~ delete _;
	private ProxyPool<SkinnedMeshProxy> mSkinnedMeshes = new .() ~ delete _;
	private ProxyPool<LightProxy> mLights = new .() ~ delete _;
	private ProxyPool<CameraProxy> mCameras = new .() ~ delete _;
	private ProxyPool<ReflectionProbeProxy> mReflectionProbes = new .() ~ delete _;
	private CameraProxyHandle mMainCamera;

	/// Environment settings (sky, IBL, ambient). Owned by the world.
	public EnvironmentSettings Environment = new .() ~ delete _;

	// --- Static Mesh API ---

	public StaticMeshProxyHandle CreateStaticMesh()
	{
		let handle = StaticMeshProxyHandle() { Handle = mStaticMeshes.Allocate() };
		if (let ptr = mStaticMeshes.Get(handle.Handle))
			*ptr = StaticMeshProxy();
		return handle;
	}

	public void DestroyStaticMesh(StaticMeshProxyHandle handle)
	{
		mStaticMeshes.Free(handle.Handle);
	}

	public void SetStaticMeshTransform(StaticMeshProxyHandle handle, Matrix transform)
	{
		if (let ptr = mStaticMeshes.Get(handle.Handle))
			ptr.Transform = transform;
	}

	public void SetStaticMeshBounds(StaticMeshProxyHandle handle, BoundingBox localBounds)
	{
		if (let ptr = mStaticMeshes.Get(handle.Handle))
			ptr.LocalBounds = localBounds;
	}

	public void SetStaticMeshData(StaticMeshProxyHandle handle, GPUMeshHandle meshHandle, BoundingBox localBounds)
	{
		if (let ptr = mStaticMeshes.Get(handle.Handle))
		{
			ptr.MeshHandle = meshHandle;
			ptr.LocalBounds = localBounds;
		}
	}

	public void SetStaticMeshMaterial(StaticMeshProxyHandle handle, int slot, MaterialInstanceHandle material)
	{
		if (let ptr = mStaticMeshes.Get(handle.Handle))
		{
			if (slot >= 0 && slot < RenderConfig.MaxMaterialsPerMesh)
			{
				ptr.Materials[slot] = material;
				if ((uint8)(slot + 1) > ptr.MaterialCount)
					ptr.MaterialCount = (uint8)(slot + 1);
			}
		}
	}

	public void SetStaticMeshFlags(StaticMeshProxyHandle handle, StaticMeshFlags flags)
	{
		if (let ptr = mStaticMeshes.Get(handle.Handle))
			ptr.Flags = flags;
	}

	// --- Skinned Mesh API ---

	public SkinnedMeshProxyHandle CreateSkinnedMesh()
	{
		let handle = SkinnedMeshProxyHandle() { Handle = mSkinnedMeshes.Allocate() };
		if (let ptr = mSkinnedMeshes.Get(handle.Handle))
			*ptr = SkinnedMeshProxy();
		return handle;
	}

	public void DestroySkinnedMesh(SkinnedMeshProxyHandle handle)
	{
		mSkinnedMeshes.Free(handle.Handle);
	}

	public void SetSkinnedMeshTransform(SkinnedMeshProxyHandle handle, Matrix transform)
	{
		if (let ptr = mSkinnedMeshes.Get(handle.Handle))
		{
			ptr.PrevTransform = ptr.Transform;
			ptr.Transform = transform;
		}
	}

	public void SetSkinnedMeshData(SkinnedMeshProxyHandle handle, GPUMeshHandle meshHandle,
		GPUBoneBufferHandle boneBufferHandle, uint16 boneCount, BoundingBox localBounds)
	{
		if (let ptr = mSkinnedMeshes.Get(handle.Handle))
		{
			ptr.MeshHandle = meshHandle;
			ptr.BoneBufferHandle = boneBufferHandle;
			ptr.BoneCount = boneCount;
			ptr.LocalBounds = localBounds;
			// Expand bounds by 1.2x to account for animation
			let center = (localBounds.Min + localBounds.Max) * 0.5f;
			let halfExtent = (localBounds.Max - localBounds.Min) * 0.5f * 1.2f;
			ptr.AnimationBounds = BoundingBox(center - halfExtent, center + halfExtent);
		}
	}

	public void SetSkinnedMeshMaterial(SkinnedMeshProxyHandle handle, int slot, MaterialInstanceHandle material)
	{
		if (let ptr = mSkinnedMeshes.Get(handle.Handle))
		{
			if (slot >= 0 && slot < RenderConfig.MaxMaterialsPerMesh)
			{
				ptr.Materials[slot] = material;
				if ((uint8)(slot + 1) > ptr.MaterialCount)
					ptr.MaterialCount = (uint8)(slot + 1);
			}
		}
	}

	public void SetSkinnedMeshFlags(SkinnedMeshProxyHandle handle, SkinnedMeshFlags flags)
	{
		if (let ptr = mSkinnedMeshes.Get(handle.Handle))
			ptr.Flags = flags;
	}

	public void MarkBonesDirty(SkinnedMeshProxyHandle handle)
	{
		if (let ptr = mSkinnedMeshes.Get(handle.Handle))
			ptr.BonesDirty = true;
	}

	// --- Light API ---

	public LightProxyHandle CreateLight(LightType type = .Point)
	{
		let handle = LightProxyHandle() { Handle = mLights.Allocate() };
		if (let ptr = mLights.Get(handle.Handle))
		{
			// ProxyPool.Allocate() zeroes the slot (uses `default`), which ignores
			// struct field initializers. Apply proper defaults then set the type.
			*ptr = LightProxy();
			ptr.Type = type;
		}
		return handle;
	}

	public void DestroyLight(LightProxyHandle handle)
	{
		mLights.Free(handle.Handle);
	}

	public void SetLightTransform(LightProxyHandle handle, Vector3 position, Vector3 direction)
	{
		if (let ptr = mLights.Get(handle.Handle))
		{
			ptr.Position = position;
			ptr.Direction = direction;
		}
	}

	public void SetLightColor(LightProxyHandle handle, Vector3 color, float intensity)
	{
		if (let ptr = mLights.Get(handle.Handle))
		{
			ptr.Color = color;
			ptr.Intensity = intensity;
		}
	}

	public void SetLightRange(LightProxyHandle handle, float range)
	{
		if (let ptr = mLights.Get(handle.Handle))
			ptr.Range = range;
	}

	public void SetLightShadows(LightProxyHandle handle, bool enabled, float bias = 0.005f, float normalBias = 0.02f)
	{
		if (let ptr = mLights.Get(handle.Handle))
		{
			ptr.CastShadows = enabled;
			ptr.ShadowBias = bias;
			ptr.ShadowNormalBias = normalBias;
		}
	}

	// --- Camera API ---

	public CameraProxyHandle CreateCamera()
	{
		let handle = CameraProxyHandle() { Handle = mCameras.Allocate() };
		if (let ptr = mCameras.Get(handle.Handle))
			*ptr = CameraProxy();
		return handle;
	}

	public void DestroyCamera(CameraProxyHandle handle)
	{
		mCameras.Free(handle.Handle);
		if (mMainCamera == handle)
			mMainCamera = .Invalid;
	}

	public void SetCameraLookAt(CameraProxyHandle handle, Vector3 position, Vector3 target, Vector3 up)
	{
		if (let ptr = mCameras.Get(handle.Handle))
		{
			ptr.Position = position;
			ptr.Target = target;
			ptr.Up = up;
		}
	}

	public void SetCameraPerspective(CameraProxyHandle handle, float fov, float near, float far)
	{
		if (let ptr = mCameras.Get(handle.Handle))
		{
			ptr.Projection = .Perspective;
			ptr.FieldOfView = fov;
			ptr.NearPlane = near;
			ptr.FarPlane = far;
		}
	}

	public void SetCameraOrthographic(CameraProxyHandle handle, float width, float height, float near, float far)
	{
		if (let ptr = mCameras.Get(handle.Handle))
		{
			ptr.Projection = .Orthographic;
			ptr.OrthoWidth = width;
			ptr.OrthoHeight = height;
			ptr.NearPlane = near;
			ptr.FarPlane = far;
		}
	}

	public void SetMainCamera(CameraProxyHandle handle)
	{
		mMainCamera = handle;
	}

	public CameraProxyHandle MainCamera => mMainCamera;

	// --- Reflection Probe API ---

	public ReflectionProbeProxyHandle CreateReflectionProbe(Vector3 position, Vector3 boxMin, Vector3 boxMax)
	{
		let handle = ReflectionProbeProxyHandle() { Handle = mReflectionProbes.Allocate() };
		if (let ptr = mReflectionProbes.Get(handle.Handle))
		{
			ptr.Position = position;
			ptr.BoxMin = boxMin;
			ptr.BoxMax = boxMax;
			ptr.Enabled = true;
			ptr.IsDirty = true;
			ptr.CubemapLayer = -1;
		}
		return handle;
	}

	public void DestroyReflectionProbe(ReflectionProbeProxyHandle handle)
	{
		mReflectionProbes.Free(handle.Handle);
	}

	public void SetReflectionProbePosition(ReflectionProbeProxyHandle handle, Vector3 position)
	{
		if (let ptr = mReflectionProbes.Get(handle.Handle))
		{
			ptr.Position = position;
			ptr.IsDirty = true;
		}
	}

	public void SetReflectionProbeBox(ReflectionProbeProxyHandle handle, Vector3 boxMin, Vector3 boxMax)
	{
		if (let ptr = mReflectionProbes.Get(handle.Handle))
		{
			ptr.BoxMin = boxMin;
			ptr.BoxMax = boxMax;
			ptr.IsDirty = true;
		}
	}

	public void SetReflectionProbeEnabled(ReflectionProbeProxyHandle handle, bool enabled)
	{
		if (let ptr = mReflectionProbes.Get(handle.Handle))
			ptr.Enabled = enabled;
	}

	public void MarkReflectionProbeDirty(ReflectionProbeProxyHandle handle)
	{
		if (let ptr = mReflectionProbes.Get(handle.Handle))
			ptr.IsDirty = true;
	}

	// --- Internal accessors for the renderer ---

	internal ProxyPool<StaticMeshProxy> StaticMeshes => mStaticMeshes;
	internal ProxyPool<SkinnedMeshProxy> SkinnedMeshes => mSkinnedMeshes;
	internal ProxyPool<LightProxy> Lights => mLights;
	internal ProxyPool<CameraProxy> Cameras => mCameras;
	internal ProxyPool<ReflectionProbeProxy> ReflectionProbes => mReflectionProbes;
}
