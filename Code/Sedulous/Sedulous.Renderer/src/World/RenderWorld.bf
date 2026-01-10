namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

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
/// Provides efficient storage and access to meshes, lights, cameras, and particles.
class RenderWorld
{
	// Mesh proxies
	private List<StaticMeshProxy> mStaticMeshProxies = new .() ~ delete _;
	private List<uint32> mStaticMeshGenerations = new .() ~ delete _;
	private List<uint32> mFreeStaticMeshSlots = new .() ~ delete _;
	private uint32 mStaticMeshCount = 0;

	// Skinned mesh proxies
	private List<SkinnedMeshProxy> mSkinnedMeshProxies = new .() ~ delete _;
	private List<uint32> mSkinnedMeshGenerations = new .() ~ delete _;
	private List<uint32> mFreeSkinnedMeshSlots = new .() ~ delete _;
	private uint32 mSkinnedMeshCount = 0;

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

	// Particle emitter proxies
	private List<ParticleEmitterProxy> mParticleEmitterProxies = new .() ~ delete _;
	private List<uint32> mParticleEmitterGenerations = new .() ~ delete _;
	private List<uint32> mFreeParticleEmitterSlots = new .() ~ delete _;
	private uint32 mParticleEmitterCount = 0;

	// Sprite proxies
	private List<SpriteProxy> mSpriteProxies = new .() ~ delete _;
	private List<uint32> mSpriteGenerations = new .() ~ delete _;
	private List<uint32> mFreeSpriteSlots = new .() ~ delete _;
	private uint32 mSpriteCount = 0;

	// Main camera handle
	private ProxyHandle mMainCamera = .Invalid;

	// Dirty flags for GPU sync
	private bool mMeshesDirty = true;
	private bool mSkinnedMeshesDirty = true;
	private bool mLightsDirty = true;
	private bool mCamerasDirty = true;
	private bool mParticleEmittersDirty = true;
	private bool mSpritesDirty = true;

	// Per-frame render views
	private List<RenderView> mRenderViews = new .() ~ delete _;
	private uint32 mNextViewId = 0;

	// ==================== Mesh Proxy Management ====================

	/// Creates a new mesh proxy.
	public ProxyHandle CreateStaticMeshProxy(GPUMeshHandle mesh, Matrix transform, BoundingBox localBounds)
	{
		uint32 index;
		uint32 generation;

		if (mFreeStaticMeshSlots.Count > 0)
		{
			index = mFreeStaticMeshSlots.PopBack();
			generation = mStaticMeshGenerations[(int)index] + 1;
			mStaticMeshGenerations[(int)index] = generation;
		}
		else
		{
			index = (uint32)mStaticMeshProxies.Count;
			generation = 1;
			mStaticMeshProxies.Add(.Invalid);
			mStaticMeshGenerations.Add(generation);
		}

		let proxy = StaticMeshProxy(index, mesh, transform, localBounds);
		mStaticMeshProxies[(int)index] = proxy;
		mStaticMeshCount++;
		mMeshesDirty = true;

		return .(index, generation);
	}

	/// Gets a mesh proxy by handle.
	public StaticMeshProxy* GetStaticMeshProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return null;
		if (handle.Index >= (uint32)mStaticMeshProxies.Count)
			return null;
		if (mStaticMeshGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return &mStaticMeshProxies[(int)handle.Index];
	}

	/// Updates a mesh proxy's transform.
	public void SetStaticMeshTransform(ProxyHandle handle, Matrix transform)
	{
		if (let proxy = GetStaticMeshProxy(handle))
		{
			proxy.Transform = transform;
			proxy.UpdateWorldBounds();
			proxy.Flags |= .Dirty;
			mMeshesDirty = true;
		}
	}

	/// Destroys a mesh proxy.
	public void DestroyStaticMeshProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return;
		if (handle.Index >= (uint32)mStaticMeshProxies.Count)
			return;
		if (mStaticMeshGenerations[(int)handle.Index] != handle.Generation)
			return;

		mStaticMeshProxies[(int)handle.Index] = .Invalid;
		mFreeStaticMeshSlots.Add(handle.Index);
		mStaticMeshCount--;
		mMeshesDirty = true;
	}

	/// Gets all valid mesh proxies.
	public void GetValidStaticMeshProxies(List<StaticMeshProxy*> outProxies)
	{
		outProxies.Clear();
		for (var i < mStaticMeshProxies.Count)
		{
			if (mStaticMeshProxies[i].IsValid)
				outProxies.Add(&mStaticMeshProxies[i]);
		}
	}

	/// Number of active mesh proxies.
	public uint32 StaticMeshCount => mStaticMeshCount;

	// ==================== Skinned Mesh Proxy Management ====================

	/// Creates a new skinned mesh proxy.
	public ProxyHandle CreateSkinnedMeshProxy(GPUSkinnedMeshHandle mesh, Matrix transform, BoundingBox localBounds)
	{
		uint32 index;
		uint32 generation;

		if (mFreeSkinnedMeshSlots.Count > 0)
		{
			index = mFreeSkinnedMeshSlots.PopBack();
			generation = mSkinnedMeshGenerations[(int)index] + 1;
			mSkinnedMeshGenerations[(int)index] = generation;
		}
		else
		{
			index = (uint32)mSkinnedMeshProxies.Count;
			generation = 1;
			mSkinnedMeshProxies.Add(.Invalid);
			mSkinnedMeshGenerations.Add(generation);
		}

		let proxy = SkinnedMeshProxy(index, mesh, transform, localBounds);
		mSkinnedMeshProxies[(int)index] = proxy;
		mSkinnedMeshCount++;
		mSkinnedMeshesDirty = true;

		return .(index, generation);
	}

	/// Gets a skinned mesh proxy by handle.
	public SkinnedMeshProxy* GetSkinnedMeshProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return null;
		if (handle.Index >= (uint32)mSkinnedMeshProxies.Count)
			return null;
		if (mSkinnedMeshGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return &mSkinnedMeshProxies[(int)handle.Index];
	}

	/// Updates a skinned mesh proxy's transform.
	public void SetSkinnedMeshTransform(ProxyHandle handle, Matrix transform)
	{
		if (let proxy = GetSkinnedMeshProxy(handle))
		{
			proxy.Transform = transform;
			proxy.UpdateWorldBounds();
			proxy.Flags |= .Dirty;
			mSkinnedMeshesDirty = true;
		}
	}

	/// Destroys a skinned mesh proxy.
	public void DestroySkinnedMeshProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return;
		if (handle.Index >= (uint32)mSkinnedMeshProxies.Count)
			return;
		if (mSkinnedMeshGenerations[(int)handle.Index] != handle.Generation)
			return;

		mSkinnedMeshProxies[(int)handle.Index] = .Invalid;
		mFreeSkinnedMeshSlots.Add(handle.Index);
		mSkinnedMeshCount--;
		mSkinnedMeshesDirty = true;
	}

	/// Gets all valid skinned mesh proxies.
	public void GetValidSkinnedMeshProxies(List<SkinnedMeshProxy*> outProxies)
	{
		outProxies.Clear();
		for (var i < mSkinnedMeshProxies.Count)
		{
			if (mSkinnedMeshProxies[i].IsValid)
				outProxies.Add(&mSkinnedMeshProxies[i]);
		}
	}

	/// Number of active skinned mesh proxies.
	public uint32 SkinnedMeshCount => mSkinnedMeshCount;

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

	// ==================== Particle Emitter Proxy Management ====================

	/// Creates a particle emitter proxy.
	public ProxyHandle CreateParticleEmitterProxy(ParticleSystem system, Vector3 position)
	{
		uint32 index;
		uint32 generation;

		if (mFreeParticleEmitterSlots.Count > 0)
		{
			index = mFreeParticleEmitterSlots.PopBack();
			generation = mParticleEmitterGenerations[(int)index] + 1;
			mParticleEmitterGenerations[(int)index] = generation;
		}
		else
		{
			index = (uint32)mParticleEmitterProxies.Count;
			generation = 1;
			mParticleEmitterProxies.Add(.Invalid);
			mParticleEmitterGenerations.Add(generation);
		}

		let proxy = ParticleEmitterProxy(index, system, position);
		mParticleEmitterProxies[(int)index] = proxy;
		mParticleEmitterCount++;
		mParticleEmittersDirty = true;

		return .(index, generation);
	}

	/// Gets a particle emitter proxy by handle.
	public ParticleEmitterProxy* GetParticleEmitterProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return null;
		if (handle.Index >= (uint32)mParticleEmitterProxies.Count)
			return null;
		if (mParticleEmitterGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return &mParticleEmitterProxies[(int)handle.Index];
	}

	/// Destroys a particle emitter proxy.
	public void DestroyParticleEmitterProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return;
		if (handle.Index >= (uint32)mParticleEmitterProxies.Count)
			return;
		if (mParticleEmitterGenerations[(int)handle.Index] != handle.Generation)
			return;

		mParticleEmitterProxies[(int)handle.Index] = .Invalid;
		mFreeParticleEmitterSlots.Add(handle.Index);
		mParticleEmitterCount--;
		mParticleEmittersDirty = true;
	}

	/// Gets all valid particle emitter proxies.
	public void GetValidParticleEmitterProxies(List<ParticleEmitterProxy*> outProxies)
	{
		outProxies.Clear();
		for (var i < mParticleEmitterProxies.Count)
		{
			if (mParticleEmitterProxies[i].IsValid && mParticleEmitterProxies[i].IsVisible)
				outProxies.Add(&mParticleEmitterProxies[i]);
		}
	}

	/// Number of active particle emitter proxies.
	public uint32 ParticleEmitterCount => mParticleEmitterCount;

	// ==================== Sprite Proxy Management ====================

	/// Creates a sprite proxy.
	public ProxyHandle CreateSpriteProxy(Vector3 position, Vector2 size, Color color = .White)
	{
		uint32 index;
		uint32 generation;

		if (mFreeSpriteSlots.Count > 0)
		{
			index = mFreeSpriteSlots.PopBack();
			generation = mSpriteGenerations[(int)index] + 1;
			mSpriteGenerations[(int)index] = generation;
		}
		else
		{
			index = (uint32)mSpriteProxies.Count;
			generation = 1;
			mSpriteProxies.Add(.Invalid);
			mSpriteGenerations.Add(generation);
		}

		let proxy = SpriteProxy(index, position, size, color);
		mSpriteProxies[(int)index] = proxy;
		mSpriteCount++;
		mSpritesDirty = true;

		return .(index, generation);
	}

	/// Creates a sprite proxy with UV rect.
	public ProxyHandle CreateSpriteProxy(Vector3 position, Vector2 size, Vector4 uvRect, Color color)
	{
		uint32 index;
		uint32 generation;

		if (mFreeSpriteSlots.Count > 0)
		{
			index = mFreeSpriteSlots.PopBack();
			generation = mSpriteGenerations[(int)index] + 1;
			mSpriteGenerations[(int)index] = generation;
		}
		else
		{
			index = (uint32)mSpriteProxies.Count;
			generation = 1;
			mSpriteProxies.Add(.Invalid);
			mSpriteGenerations.Add(generation);
		}

		let proxy = SpriteProxy(index, position, size, uvRect, color);
		mSpriteProxies[(int)index] = proxy;
		mSpriteCount++;
		mSpritesDirty = true;

		return .(index, generation);
	}

	/// Gets a sprite proxy by handle.
	public SpriteProxy* GetSpriteProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return null;
		if (handle.Index >= (uint32)mSpriteProxies.Count)
			return null;
		if (mSpriteGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return &mSpriteProxies[(int)handle.Index];
	}

	/// Updates a sprite proxy's position.
	public void SetSpritePosition(ProxyHandle handle, Vector3 position)
	{
		if (let proxy = GetSpriteProxy(handle))
		{
			proxy.SetPosition(position);
			mSpritesDirty = true;
		}
	}

	/// Updates a sprite proxy's size.
	public void SetSpriteSize(ProxyHandle handle, Vector2 size)
	{
		if (let proxy = GetSpriteProxy(handle))
		{
			proxy.SetSize(size);
			mSpritesDirty = true;
		}
	}

	/// Updates a sprite proxy's color.
	public void SetSpriteColor(ProxyHandle handle, Color color)
	{
		if (let proxy = GetSpriteProxy(handle))
		{
			proxy.Color = color;
			mSpritesDirty = true;
		}
	}

	/// Updates a sprite proxy's UV rect.
	public void SetSpriteUVRect(ProxyHandle handle, Vector4 uvRect)
	{
		if (let proxy = GetSpriteProxy(handle))
		{
			proxy.UVRect = uvRect;
			mSpritesDirty = true;
		}
	}

	/// Destroys a sprite proxy.
	public void DestroySpriteProxy(ProxyHandle handle)
	{
		if (!handle.IsValid)
			return;
		if (handle.Index >= (uint32)mSpriteProxies.Count)
			return;
		if (mSpriteGenerations[(int)handle.Index] != handle.Generation)
			return;

		mSpriteProxies[(int)handle.Index] = .Invalid;
		mFreeSpriteSlots.Add(handle.Index);
		mSpriteCount--;
		mSpritesDirty = true;
	}

	/// Gets all valid sprite proxies.
	public void GetValidSpriteProxies(List<SpriteProxy*> outProxies)
	{
		outProxies.Clear();
		for (var i < mSpriteProxies.Count)
		{
			if (mSpriteProxies[i].IsValid && mSpriteProxies[i].IsVisible)
				outProxies.Add(&mSpriteProxies[i]);
		}
	}

	/// Number of active sprite proxies.
	public uint32 SpriteCount => mSpriteCount;

	// ==================== Render View Management ====================

	/// Clears all render views and resets the view ID counter.
	/// Call at the start of each frame before adding views.
	public void ClearRenderViews()
	{
		mRenderViews.Clear();
		mNextViewId = 0;
	}

	/// Adds a render view and returns its index in the view list.
	public int32 AddRenderView(RenderView view)
	{
		var v = view;
		v.Id = mNextViewId++;
		let index = (int32)mRenderViews.Count;
		mRenderViews.Add(v);
		return index;
	}

	/// Adds a main camera view from the current main camera proxy.
	/// Returns the view index, or -1 if no main camera is set.
	public int32 AddMainCameraView(ITextureView* colorTarget, ITextureView* depthTarget)
	{
		if (let camera = MainCamera)
		{
			let view = RenderView.FromCameraProxy(mNextViewId, camera, colorTarget, depthTarget, true);
			return AddRenderView(view);
		}
		return -1;
	}

	/// Adds a camera view from a camera proxy handle.
	/// Returns the view index, or -1 if the handle is invalid.
	public int32 AddCameraView(ProxyHandle cameraHandle, ITextureView* colorTarget, ITextureView* depthTarget, bool isMain = false)
	{
		if (let camera = GetCameraProxy(cameraHandle))
		{
			let view = RenderView.FromCameraProxy(mNextViewId, camera, colorTarget, depthTarget, isMain);
			return AddRenderView(view);
		}
		return -1;
	}

	/// Gets the list of render views for iteration.
	public List<RenderView> RenderViews => mRenderViews;

	/// Gets the number of render views.
	public int32 RenderViewCount => (int32)mRenderViews.Count;

	/// Gets a render view by index.
	public RenderView* GetRenderView(int32 index)
	{
		if (index >= 0 && index < mRenderViews.Count)
			return &mRenderViews[index];
		return null;
	}

	/// Gets all views of a specific type.
	public void GetViewsByType(RenderViewType type, List<RenderView*> outViews)
	{
		outViews.Clear();
		for (var i < mRenderViews.Count)
		{
			if (mRenderViews[i].Type == type)
				outViews.Add(&mRenderViews[i]);
		}
	}

	/// Gets all views sorted by priority (lower priority renders first).
	public void GetSortedViews(List<RenderView*> outViews)
	{
		outViews.Clear();
		for (var i < mRenderViews.Count)
			outViews.Add(&mRenderViews[i]);

		// Sort by priority (ascending)
		outViews.Sort(scope (a, b) => (int32)a.Priority - (int32)b.Priority);
	}

	/// Gets all enabled views sorted by priority.
	public void GetEnabledSortedViews(List<RenderView*> outViews)
	{
		outViews.Clear();
		for (var i < mRenderViews.Count)
		{
			if (mRenderViews[i].IsEnabled)
				outViews.Add(&mRenderViews[i]);
		}

		outViews.Sort(scope (a, b) => (int32)a.Priority - (int32)b.Priority);
	}

	/// Adds shadow cascade views from cascade data.
	/// Returns the number of views added.
	public int32 AddShadowCascadeViews(
		Span<CascadeData> cascadeData,
		Span<ITextureView*> depthTargets,
		uint32 shadowMapSize,
		ProxyHandle lightHandle,
		uint32 layerMask = 0xFFFFFFFF)
	{
		int32 count = 0;
		int32 cascadeCount = Math.Min((int32)cascadeData.Length, (int32)depthTargets.Length);

		for (int32 i = 0; i < cascadeCount; i++)
		{
			if (depthTargets[i] == null)
				continue;

			let view = RenderView.ForShadowCascade(
				mNextViewId,
				i,
				cascadeData[i].ViewProjection,
				depthTargets[i],
				shadowMapSize,
				0, 0,  // No atlas offset for cascades
				lightHandle,
				layerMask
			);
			AddRenderView(view);
			count++;
		}

		return count;
	}

	/// Adds a single shadow cascade view.
	public int32 AddShadowCascadeView(
		int32 cascadeIndex,
		Matrix viewProjection,
		ITextureView* depthTarget,
		uint32 shadowMapSize,
		ProxyHandle lightHandle,
		uint32 layerMask = 0xFFFFFFFF)
	{
		if (depthTarget == null)
			return -1;

		let view = RenderView.ForShadowCascade(
			mNextViewId,
			cascadeIndex,
			viewProjection,
			depthTarget,
			shadowMapSize,
			0, 0,
			lightHandle,
			layerMask
		);
		return AddRenderView(view);
	}

	/// Adds a local shadow view (point/spot light).
	public int32 AddLocalShadowView(
		int32 atlasSlot,
		Matrix viewProjection,
		ITextureView* depthTarget,
		int32 viewportX,
		int32 viewportY,
		uint32 tileSize,
		ProxyHandle lightHandle,
		uint32 layerMask = 0xFFFFFFFF)
	{
		if (depthTarget == null)
			return -1;

		let view = RenderView.ForLocalShadow(
			mNextViewId,
			atlasSlot,
			viewProjection,
			depthTarget,
			viewportX,
			viewportY,
			tileSize,
			lightHandle,
			layerMask
		);
		return AddRenderView(view);
	}

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
		for (var i < mStaticMeshProxies.Count)
		{
			if (mStaticMeshProxies[i].IsValid)
			{
				mStaticMeshProxies[i].SavePreviousTransform();
				mStaticMeshProxies[i].Flags &= ~.Dirty;
				mStaticMeshProxies[i].Flags &= ~.Culled;
			}
		}

		for (var i < mSkinnedMeshProxies.Count)
		{
			if (mSkinnedMeshProxies[i].IsValid)
			{
				mSkinnedMeshProxies[i].SavePreviousTransform();
				mSkinnedMeshProxies[i].Flags &= ~.Dirty;
				mSkinnedMeshProxies[i].Flags &= ~.Culled;
			}
		}

		for (var i < mParticleEmitterProxies.Count)
		{
			if (mParticleEmitterProxies[i].IsValid)
			{
				mParticleEmitterProxies[i].Flags &= ~.Culled;
			}
		}

		for (var i < mSpriteProxies.Count)
		{
			if (mSpriteProxies[i].IsValid)
			{
				mSpriteProxies[i].Flags &= ~.Culled;
			}
		}

		mMeshesDirty = false;
		mSkinnedMeshesDirty = false;
		mLightsDirty = false;
		mCamerasDirty = false;
		mParticleEmittersDirty = false;
		mSpritesDirty = false;
	}

	/// Clears all proxies.
	public void Clear()
	{
		mStaticMeshProxies.Clear();
		mStaticMeshGenerations.Clear();
		mFreeStaticMeshSlots.Clear();
		mStaticMeshCount = 0;

		mSkinnedMeshProxies.Clear();
		mSkinnedMeshGenerations.Clear();
		mFreeSkinnedMeshSlots.Clear();
		mSkinnedMeshCount = 0;

		mLightProxies.Clear();
		mLightGenerations.Clear();
		mFreeLightSlots.Clear();
		mLightCount = 0;

		mCameraProxies.Clear();
		mCameraGenerations.Clear();
		mFreeCameraSlots.Clear();
		mCameraCount = 0;

		mParticleEmitterProxies.Clear();
		mParticleEmitterGenerations.Clear();
		mFreeParticleEmitterSlots.Clear();
		mParticleEmitterCount = 0;

		mSpriteProxies.Clear();
		mSpriteGenerations.Clear();
		mFreeSpriteSlots.Clear();
		mSpriteCount = 0;

		mMainCamera = .Invalid;

		mRenderViews.Clear();
		mNextViewId = 0;

		mMeshesDirty = true;
		mSkinnedMeshesDirty = true;
		mLightsDirty = true;
		mCamerasDirty = true;
		mParticleEmittersDirty = true;
		mSpritesDirty = true;
	}

	// ==================== Queries ====================

	/// Gets all mesh proxies within a bounding box.
	public void GetMeshesInBounds(BoundingBox bounds, List<ProxyHandle> outHandles)
	{
		outHandles.Clear();
		for (var i < mStaticMeshProxies.Count)
		{
			let proxy = mStaticMeshProxies[i];
			if (proxy.IsValid && proxy.WorldBounds.Intersects(bounds))
				outHandles.Add(.(proxy.Id, mStaticMeshGenerations[i]));
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
	public bool SkinnedMeshesDirty => mSkinnedMeshesDirty;
	public bool LightsDirty => mLightsDirty;
	public bool CamerasDirty => mCamerasDirty;
	public bool ParticleEmittersDirty => mParticleEmittersDirty;
	public bool SpritesDirty => mSpritesDirty;
}
