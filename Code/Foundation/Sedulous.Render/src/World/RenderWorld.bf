namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
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
	private ProxyPool<TrailEmitterProxy> mTrailProxies = new .() ~ delete _;
	private ProxyPool<DecalProxy> mDecalProxies = new .() ~ delete _;
	private ProxyPool<ReflectionProbeProxy> mReflectionProbeProxies = new .() ~ delete _;
	private ProxyPool<TerrainProxy> mTerrainProxies = new .() ~ delete _;
	private ProxyPool<WaterProxy> mWaterProxies = new .() ~ delete _;
	private ProxyPool<GrassProxy> mGrassProxies = new .() ~ delete _;
	private ProxyPool<CurveDecalProxy> mCurveDecalProxies = new .() ~ delete _;

	// Main camera handle
	private CameraProxyHandle mMainCamera = .Invalid;

	// Environment lighting settings
	private Vector3 mAmbientColor = .(0.03f, 0.03f, 0.03f);
	private float mAmbientIntensity = 1.0f;
	private float mExposure = 1.0f;
	private bool mEnvironmentDirty = true;

	// Tonemapping
	private TonemapOperator mTonemapOperator = .ACES;

	// Bloom
	private bool mBloomEnabled = true;
	private float mBloomIntensity = 0.5f;
	private float mBloomThreshold = 1.0f;

	// Auto-exposure
	private ExposureMode mExposureMode = .Manual;
	private float mAutoExposureMin = 0.1f;
	private float mAutoExposureMax = 10.0f;
	private float mAutoExposureSpeed = 1.0f;

	// Anti-aliasing
	private AAMode mAAMode = .None;
	private bool mSharpenEnabled = true;
	private float mSharpenIntensity = 0.75f;

	// SSAO
	private bool mSSAOEnabled = true;
	private float mSSAORadius = 0.5f;
	private float mSSAOIntensity = 1.5f;

	// SSR
	private bool mSSREnabled = false; // Off by default (expensive)
	private float mSSRIntensity = 1.0f;

	// Contact Shadows
	private bool mContactShadowsEnabled = true;
	private float mContactShadowLength = 0.1f;

	// Depth of Field
	private bool mDOFEnabled = false;
	private float mDOFFocusDistance = 10.0f;
	private float mDOFFocusRange = 5.0f;
	private float mDOFBokehSize = 4.0f;

	// Motion Blur
	private bool mMotionBlurEnabled = false;
	private float mMotionBlurIntensity = 1.0f;

	// Film Grain
	private bool mFilmGrainEnabled = false;
	private float mFilmGrainIntensity = 0.15f;

	// Color Grading
	private bool mColorGradingEnabled = false;
	private ITextureView mColorGradingLUT = null;

	// Vignette
	private bool mVignetteEnabled = false;
	private float mVignetteIntensity = 0.4f;
	private float mVignetteSmoothness = 0.5f;

	// Chromatic Aberration
	private bool mChromaticAberrationEnabled = false;
	private float mChromaticAberrationIntensity = 0.005f;

	// LOD & Instancing
	private float mLODBias = 1.0f;
	private bool mInstancingEnabled = true;

	// Deferred deletion queue for GPU-referenced resources
	struct PendingEmitterDeletion
	{
		public CPUParticleEmitter Emitter;
		public int32 FramesRemaining;
	}
	struct PendingTrailDeletion
	{
		public TrailEmitter Emitter;
		public int32 FramesRemaining;
	}
	private List<PendingEmitterDeletion> mPendingEmitterDeletions = new .() ~ {
		for (let pending in _)
			delete pending.Emitter;
		delete _;
	};
	private List<PendingTrailDeletion> mPendingTrailDeletions = new .() ~ {
		for (let pending in _)
			delete pending.Emitter;
		delete _;
	};

	// Dirty tracking
	private bool mMeshesDirty = false;
	private bool mSkinnedMeshesDirty = false;
	private bool mLightsDirty = false;
	private bool mCamerasDirty = false;
	private bool mParticlesDirty = false;
	private bool mSpritesDirty = false;
	private bool mTrailsDirty = false;
	private bool mDecalsDirty = false;
	private bool mReflectionProbesDirty = false;
	private bool mTerrainsDirty = false;
	private bool mWatersDirty = false;
	private bool mGrassDirty = false;
	private bool mCurveDecalsDirty = false;

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

	/// Gets the decal proxy pool.
	public ProxyPool<DecalProxy> DecalProxies => mDecalProxies;

	/// Gets the reflection probe proxy pool.
	public ProxyPool<ReflectionProbeProxy> ReflectionProbeProxies => mReflectionProbeProxies;

	/// Gets the terrain proxy pool.
	public ProxyPool<TerrainProxy> TerrainProxies => mTerrainProxies;

	/// Gets the water proxy pool.
	public ProxyPool<WaterProxy> WaterProxies => mWaterProxies;

	/// Gets the grass proxy pool.
	public ProxyPool<GrassProxy> GrassProxies => mGrassProxies;

	/// Gets the curve decal proxy pool.
	public ProxyPool<CurveDecalProxy> CurveDecalProxies => mCurveDecalProxies;

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

	/// Gets the number of active decals.
	public int32 DecalCount => mDecalProxies.ActiveCount;

	/// Whether any sprites have changed.
	public bool SpritesDirty => mSpritesDirty;

	/// Whether any decals have changed.
	public bool DecalsDirty => mDecalsDirty;

	/// Whether any reflection probes have changed.
	public bool ReflectionProbesDirty => mReflectionProbesDirty;

	/// Whether any terrains have changed.
	public bool TerrainsDirty => mTerrainsDirty;

	/// Gets the number of active terrains.
	public int32 TerrainCount => mTerrainProxies.ActiveCount;

	/// Whether any waters have changed.
	public bool WatersDirty => mWatersDirty;

	/// Gets the number of active water planes.
	public int32 WaterCount => mWaterProxies.ActiveCount;

	/// Whether any grass has changed.
	public bool GrassDirty => mGrassDirty;

	/// Gets the number of active grass types.
	public int32 GrassCount => mGrassProxies.ActiveCount;

	/// Whether any curve decals have changed.
	public bool CurveDecalsDirty => mCurveDecalsDirty;

	/// Gets the number of active curve decals.
	public int32 CurveDecalCount => mCurveDecalProxies.ActiveCount;

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
	// Tonemapping API
	// ========================================================================

	/// Gets or sets the tonemap operator.
	public TonemapOperator TonemapOperator
	{
		get => mTonemapOperator;
		set { mTonemapOperator = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Bloom API
	// ========================================================================

	/// Gets or sets whether bloom is enabled.
	public bool BloomEnabled
	{
		get => mBloomEnabled;
		set { mBloomEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the bloom intensity (0-1+).
	public float BloomIntensity
	{
		get => mBloomIntensity;
		set { mBloomIntensity = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the bloom threshold (HDR brightness to start blooming).
	public float BloomThreshold
	{
		get => mBloomThreshold;
		set { mBloomThreshold = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Auto-Exposure API
	// ========================================================================

	/// Gets or sets the exposure mode (Manual or Auto).
	public ExposureMode ExposureMode
	{
		get => mExposureMode;
		set { mExposureMode = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the minimum auto-exposure value.
	public float AutoExposureMin
	{
		get => mAutoExposureMin;
		set { mAutoExposureMin = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the maximum auto-exposure value.
	public float AutoExposureMax
	{
		get => mAutoExposureMax;
		set { mAutoExposureMax = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the auto-exposure adaptation speed.
	public float AutoExposureSpeed
	{
		get => mAutoExposureSpeed;
		set { mAutoExposureSpeed = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Anti-Aliasing API
	// ========================================================================

	/// Gets or sets the anti-aliasing mode.
	public AAMode AAMode
	{
		get => mAAMode;
		set { mAAMode = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets whether post-AA sharpening is enabled.
	public bool SharpenEnabled
	{
		get => mSharpenEnabled;
		set { mSharpenEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the sharpening intensity (0-1).
	public float SharpenIntensity
	{
		get => mSharpenIntensity;
		set { mSharpenIntensity = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// SSAO API
	// ========================================================================

	/// Gets or sets whether SSAO is enabled.
	public bool SSAOEnabled
	{
		get => mSSAOEnabled;
		set { mSSAOEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the SSAO sampling radius in view space.
	public float SSAORadius
	{
		get => mSSAORadius;
		set { mSSAORadius = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the SSAO intensity.
	public float SSAOIntensity
	{
		get => mSSAOIntensity;
		set { mSSAOIntensity = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// SSR API
	// ========================================================================

	/// Gets or sets whether screen-space reflections are enabled.
	public bool SSREnabled
	{
		get => mSSREnabled;
		set { mSSREnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the SSR intensity (0-1).
	public float SSRIntensity
	{
		get => mSSRIntensity;
		set { mSSRIntensity = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Contact Shadows API
	// ========================================================================

	/// Gets or sets whether contact shadows are enabled.
	public bool ContactShadowsEnabled
	{
		get => mContactShadowsEnabled;
		set { mContactShadowsEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the contact shadow ray length in view space.
	public float ContactShadowLength
	{
		get => mContactShadowLength;
		set { mContactShadowLength = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Depth of Field API
	// ========================================================================

	/// Gets or sets whether depth of field is enabled.
	public bool DOFEnabled
	{
		get => mDOFEnabled;
		set { mDOFEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the DOF focus distance in world units.
	public float DOFFocusDistance
	{
		get => mDOFFocusDistance;
		set { mDOFFocusDistance = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the DOF focus range (transition width).
	public float DOFFocusRange
	{
		get => mDOFFocusRange;
		set { mDOFFocusRange = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the DOF bokeh size (max blur radius in pixels).
	public float DOFBokehSize
	{
		get => mDOFBokehSize;
		set { mDOFBokehSize = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Motion Blur API
	// ========================================================================

	/// Gets or sets whether motion blur is enabled.
	public bool MotionBlurEnabled
	{
		get => mMotionBlurEnabled;
		set { mMotionBlurEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the motion blur intensity.
	public float MotionBlurIntensity
	{
		get => mMotionBlurIntensity;
		set { mMotionBlurIntensity = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Film Grain API
	// ========================================================================

	/// Gets or sets whether film grain is enabled.
	public bool FilmGrainEnabled
	{
		get => mFilmGrainEnabled;
		set { mFilmGrainEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the film grain intensity.
	public float FilmGrainIntensity
	{
		get => mFilmGrainIntensity;
		set { mFilmGrainIntensity = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Color Grading API
	// ========================================================================

	/// Gets or sets whether color grading is enabled.
	public bool ColorGradingEnabled
	{
		get => mColorGradingEnabled;
		set { mColorGradingEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the color grading LUT texture view (non-owning, 1024x32 2D atlas).
	public ITextureView ColorGradingLUT
	{
		get => mColorGradingLUT;
		set { mColorGradingLUT = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Vignette API
	// ========================================================================

	/// Gets or sets whether vignette is enabled.
	public bool VignetteEnabled
	{
		get => mVignetteEnabled;
		set { mVignetteEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the vignette intensity (0-1).
	public float VignetteIntensity
	{
		get => mVignetteIntensity;
		set { mVignetteIntensity = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the vignette smoothness (0-1).
	public float VignetteSmoothness
	{
		get => mVignetteSmoothness;
		set { mVignetteSmoothness = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// Chromatic Aberration API
	// ========================================================================

	/// Gets or sets whether chromatic aberration is enabled.
	public bool ChromaticAberrationEnabled
	{
		get => mChromaticAberrationEnabled;
		set { mChromaticAberrationEnabled = value; mEnvironmentDirty = true; }
	}

	/// Gets or sets the chromatic aberration intensity.
	public float ChromaticAberrationIntensity
	{
		get => mChromaticAberrationIntensity;
		set { mChromaticAberrationIntensity = value; mEnvironmentDirty = true; }
	}

	// ========================================================================
	// LOD & Instancing API
	// ========================================================================

	/// Gets or sets the LOD bias. Higher values push LOD transitions farther (higher quality).
	public float LODBias
	{
		get => mLODBias;
		set { mLODBias = Math.Max(0.01f, value); }
	}

	/// Gets or sets whether GPU instancing is enabled.
	public bool InstancingEnabled
	{
		get => mInstancingEnabled;
		set { mInstancingEnabled = value; }
	}

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

	/// Sets mesh material for a specific slot.
	public void SetMeshMaterial(MeshProxyHandle handle, int32 slot, MaterialInstance material)
	{
		if (let proxy = mMeshProxies.Get(handle.Handle))
		{
			if (slot >= 0 && slot < RenderConfig.MaxMaterialsPerMesh)
			{
				proxy.Materials[slot] = material;
				if (slot >= proxy.MaterialCount)
					proxy.MaterialCount = slot + 1;
				mMeshesDirty = true;
			}
		}
	}

	/// Sets mesh material (slot 0 convenience overload).
	public void SetMeshMaterial(MeshProxyHandle handle, MaterialInstance material)
	{
		SetMeshMaterial(handle, 0, material);
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

	/// Sets skinned mesh material for a specific slot.
	public void SetSkinnedMeshMaterial(SkinnedMeshProxyHandle handle, int32 slot, MaterialInstance material)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			if (slot >= 0 && slot < RenderConfig.MaxMaterialsPerMesh)
			{
				proxy.Materials[slot] = material;
				if (slot >= proxy.MaterialCount)
					proxy.MaterialCount = slot + 1;
				mSkinnedMeshesDirty = true;
			}
		}
	}

	/// Sets skinned mesh material (slot 0 convenience overload).
	public void SetSkinnedMeshMaterial(SkinnedMeshProxyHandle handle, MaterialInstance material)
	{
		SetSkinnedMeshMaterial(handle, 0, material);
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
	/// When backend is CPU, a CPUParticleEmitter is created automatically.
	public ParticleEmitterProxyHandle CreateParticleEmitter(IDevice device = null, ParticleSimulationBackend backend = .CPU, int32 maxParticles = 500)
	{
		let handle = mParticleProxies.Allocate();
		var proxy = mParticleProxies.Get(handle);
		*proxy = ParticleEmitterProxy.CreateDefault();
		proxy.Backend = backend;
		proxy.MaxParticles = (uint32)maxParticles;
		if (backend == .CPU && device != null)
			proxy.CPUEmitter = new CPUParticleEmitter(device, maxParticles);
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
	/// CPU emitter buffers are deferred for deletion to avoid destroying
	/// GPU resources that may still be referenced by in-flight command buffers.
	public void DestroyParticleEmitter(ParticleEmitterProxyHandle handle)
	{
		if (mParticleProxies.TryGet(handle.Handle, let proxy))
		{
			if (proxy.CPUEmitter != null)
			{
				// Defer deletion until in-flight frames have completed
				var pending = PendingEmitterDeletion();
				pending.Emitter = proxy.CPUEmitter;
				pending.FramesRemaining = RenderConfig.FrameBufferCount + 1;
				mPendingEmitterDeletions.Add(pending);
				proxy.CPUEmitter = null;
			}
			proxy.Reset();
		}
		mParticleProxies.Free(handle.Handle);
		mParticlesDirty = true;
	}

	/// Processes deferred deletions. Call once per frame from the render system.
	public void ProcessDeferredDeletions()
	{
		for (int32 i = (int32)mPendingEmitterDeletions.Count - 1; i >= 0; i--)
		{
			var pending = ref mPendingEmitterDeletions[i];
			pending.FramesRemaining--;
			if (pending.FramesRemaining <= 0)
			{
				delete pending.Emitter;
				mPendingEmitterDeletions.RemoveAt(i);
			}
		}

		for (int32 i = (int32)mPendingTrailDeletions.Count - 1; i >= 0; i--)
		{
			var pending = ref mPendingTrailDeletions[i];
			pending.FramesRemaining--;
			if (pending.FramesRemaining <= 0)
			{
				delete pending.Emitter;
				mPendingTrailDeletions.RemoveAt(i);
			}
		}
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
	// Trail API
	// ========================================================================

	/// Creates a new standalone trail emitter proxy.
	public TrailEmitterProxyHandle CreateTrailEmitter()
	{
		let handle = mTrailProxies.Allocate();
		var proxy = mTrailProxies.Get(handle);
		*proxy = TrailEmitterProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mTrailsDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a trail emitter proxy by handle.
	public TrailEmitterProxy* GetTrailEmitter(TrailEmitterProxyHandle handle)
	{
		return mTrailProxies.Get(handle.Handle);
	}

	/// Destroys a trail emitter proxy.
	/// Trail emitter buffers are deferred for deletion to avoid destroying
	/// GPU resources that may still be referenced by in-flight command buffers.
	public void DestroyTrailEmitter(TrailEmitterProxyHandle handle)
	{
		if (mTrailProxies.TryGet(handle.Handle, let proxy))
		{
			if (proxy.Emitter != null)
			{
				var pending = PendingTrailDeletion();
				pending.Emitter = proxy.Emitter;
				pending.FramesRemaining = RenderConfig.FrameBufferCount + 1;
				mPendingTrailDeletions.Add(pending);
				proxy.Emitter = null;
			}
			proxy.Reset();
		}
		mTrailProxies.Free(handle.Handle);
		mTrailsDirty = true;
	}

	/// Iterates over all active trail emitters.
	public void ForEachTrailEmitter(ProxyCallback<TrailEmitterProxy> callback)
	{
		mTrailProxies.ForEach(callback);
	}

	// ========================================================================
	// Decal API
	// ========================================================================

	/// Creates a new decal proxy.
	public DecalProxyHandle CreateDecal()
	{
		let handle = mDecalProxies.Allocate();
		var proxy = mDecalProxies.Get(handle);
		*proxy = DecalProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mDecalsDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a decal proxy by handle.
	public DecalProxy* GetDecal(DecalProxyHandle handle)
	{
		return mDecalProxies.Get(handle.Handle);
	}

	/// Gets a reference to a decal proxy.
	public ref DecalProxy GetDecalRef(DecalProxyHandle handle)
	{
		return ref mDecalProxies.GetRef(handle.Handle);
	}

	/// Destroys a decal proxy.
	public void DestroyDecal(DecalProxyHandle handle)
	{
		if (mDecalProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mDecalProxies.Free(handle.Handle);
		mDecalsDirty = true;
	}

	/// Sets decal transform (position, rotation, scale).
	public void SetDecalTransform(DecalProxyHandle handle, Vector3 position, Quaternion rotation, Vector3 scale)
	{
		if (let proxy = mDecalProxies.Get(handle.Handle))
		{
			proxy.Position = position;
			proxy.Rotation = rotation;
			proxy.Scale = scale;
			mDecalsDirty = true;
		}
	}

	/// Sets decal albedo texture and sampler.
	public void SetDecalTexture(DecalProxyHandle handle, ITextureView texture, ISampler sampler = null)
	{
		if (let proxy = mDecalProxies.Get(handle.Handle))
		{
			proxy.AlbedoTexture = texture;
			proxy.Sampler = sampler;
			mDecalsDirty = true;
		}
	}

	/// Sets decal blend mode.
	public void SetDecalBlendMode(DecalProxyHandle handle, DecalBlendMode blendMode)
	{
		if (let proxy = mDecalProxies.Get(handle.Handle))
		{
			proxy.BlendMode = blendMode;
			mDecalsDirty = true;
		}
	}

	/// Enables or disables a decal.
	public void SetDecalEnabled(DecalProxyHandle handle, bool enabled)
	{
		if (let proxy = mDecalProxies.Get(handle.Handle))
		{
			proxy.IsActive = enabled;
			mDecalsDirty = true;
		}
	}

	/// Iterates over all active decals.
	public void ForEachDecal(ProxyCallback<DecalProxy> callback)
	{
		mDecalProxies.ForEach(callback);
	}

	// ========================================================================
	// Reflection Probe API
	// ========================================================================

	/// Creates a new reflection probe proxy.
	public ReflectionProbeProxyHandle CreateReflectionProbe()
	{
		let handle = mReflectionProbeProxies.Allocate();
		var proxy = mReflectionProbeProxies.Get(handle);
		*proxy = ReflectionProbeProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mReflectionProbesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a reflection probe proxy by handle.
	public ReflectionProbeProxy* GetReflectionProbe(ReflectionProbeProxyHandle handle)
	{
		return mReflectionProbeProxies.Get(handle.Handle);
	}

	/// Gets a reference to a reflection probe proxy.
	public ref ReflectionProbeProxy GetReflectionProbeRef(ReflectionProbeProxyHandle handle)
	{
		return ref mReflectionProbeProxies.GetRef(handle.Handle);
	}

	/// Destroys a reflection probe proxy.
	public void DestroyReflectionProbe(ReflectionProbeProxyHandle handle)
	{
		if (mReflectionProbeProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mReflectionProbeProxies.Free(handle.Handle);
		mReflectionProbesDirty = true;
	}

	/// Marks reflection probes as dirty (need GPU re-upload).
	public void MarkReflectionProbesDirty()
	{
		mReflectionProbesDirty = true;
	}

	/// Iterates over all active reflection probes.
	public void ForEachReflectionProbe(ProxyCallback<ReflectionProbeProxy> callback)
	{
		mReflectionProbeProxies.ForEach(callback);
	}

	// ========================================================================
	// Terrain API
	// ========================================================================

	/// Creates a new terrain proxy.
	public TerrainProxyHandle CreateTerrain()
	{
		let handle = mTerrainProxies.Allocate();
		var proxy = mTerrainProxies.Get(handle);
		*proxy = TerrainProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mTerrainsDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a terrain proxy by handle.
	public TerrainProxy* GetTerrain(TerrainProxyHandle handle)
	{
		return mTerrainProxies.Get(handle.Handle);
	}

	/// Gets a reference to a terrain proxy.
	public ref TerrainProxy GetTerrainRef(TerrainProxyHandle handle)
	{
		return ref mTerrainProxies.GetRef(handle.Handle);
	}

	/// Destroys a terrain proxy.
	public void DestroyTerrain(TerrainProxyHandle handle)
	{
		if (mTerrainProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mTerrainProxies.Free(handle.Handle);
		mTerrainsDirty = true;
	}

	/// Marks terrains as dirty (need GPU re-upload).
	public void MarkTerrainsDirty()
	{
		mTerrainsDirty = true;
	}

	/// Iterates over all active terrains.
	public void ForEachTerrain(ProxyCallback<TerrainProxy> callback)
	{
		mTerrainProxies.ForEach(callback);
	}

	// ========================================================================
	// Water API
	// ========================================================================

	/// Creates a new water proxy.
	public WaterProxyHandle CreateWater()
	{
		let handle = mWaterProxies.Allocate();
		var proxy = mWaterProxies.Get(handle);
		*proxy = WaterProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mWatersDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a water proxy by handle.
	public WaterProxy* GetWater(WaterProxyHandle handle)
	{
		return mWaterProxies.Get(handle.Handle);
	}

	/// Gets a reference to a water proxy.
	public ref WaterProxy GetWaterRef(WaterProxyHandle handle)
	{
		return ref mWaterProxies.GetRef(handle.Handle);
	}

	/// Destroys a water proxy.
	public void DestroyWater(WaterProxyHandle handle)
	{
		if (mWaterProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mWaterProxies.Free(handle.Handle);
		mWatersDirty = true;
	}

	/// Marks waters as dirty (need GPU re-upload).
	public void MarkWatersDirty()
	{
		mWatersDirty = true;
	}

	/// Iterates over all active water planes.
	public void ForEachWater(ProxyCallback<WaterProxy> callback)
	{
		mWaterProxies.ForEach(callback);
	}

	// ========================================================================
	// Grass API
	// ========================================================================

	/// Creates a new grass proxy.
	public GrassProxyHandle CreateGrass()
	{
		let handle = mGrassProxies.Allocate();
		var proxy = mGrassProxies.Get(handle);
		*proxy = GrassProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mGrassDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a grass proxy by handle.
	public GrassProxy* GetGrass(GrassProxyHandle handle)
	{
		return mGrassProxies.Get(handle.Handle);
	}

	/// Gets a reference to a grass proxy.
	public ref GrassProxy GetGrassRef(GrassProxyHandle handle)
	{
		return ref mGrassProxies.GetRef(handle.Handle);
	}

	/// Destroys a grass proxy.
	public void DestroyGrass(GrassProxyHandle handle)
	{
		if (mGrassProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mGrassProxies.Free(handle.Handle);
		mGrassDirty = true;
	}

	/// Marks grass as dirty (need GPU re-upload).
	public void MarkGrassDirty()
	{
		mGrassDirty = true;
	}

	/// Iterates over all active grass proxies.
	public void ForEachGrass(ProxyCallback<GrassProxy> callback)
	{
		mGrassProxies.ForEach(callback);
	}

	// ========================================================================
	// Curve Decal API
	// ========================================================================

	/// Creates a new curve decal proxy.
	public CurveDecalProxyHandle CreateCurveDecal()
	{
		let handle = mCurveDecalProxies.Allocate();
		var proxy = mCurveDecalProxies.Get(handle);
		*proxy = CurveDecalProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mCurveDecalsDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a curve decal proxy by handle.
	public CurveDecalProxy* GetCurveDecal(CurveDecalProxyHandle handle)
	{
		return mCurveDecalProxies.Get(handle.Handle);
	}

	/// Gets a reference to a curve decal proxy.
	public ref CurveDecalProxy GetCurveDecalRef(CurveDecalProxyHandle handle)
	{
		return ref mCurveDecalProxies.GetRef(handle.Handle);
	}

	/// Destroys a curve decal proxy.
	public void DestroyCurveDecal(CurveDecalProxyHandle handle)
	{
		if (mCurveDecalProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mCurveDecalProxies.Free(handle.Handle);
		mCurveDecalsDirty = true;
	}

	/// Marks curve decals as dirty (need mesh rebuild).
	public void MarkCurveDecalsDirty()
	{
		mCurveDecalsDirty = true;
	}

	/// Iterates over all active curve decal proxies.
	public void ForEachCurveDecal(ProxyCallback<CurveDecalProxy> callback)
	{
		mCurveDecalProxies.ForEach(callback);
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
		mTrailsDirty = false;
		mDecalsDirty = false;
		mReflectionProbesDirty = false;
		mTerrainsDirty = false;
		mWatersDirty = false;
		mGrassDirty = false;
		mCurveDecalsDirty = false;
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

		// Delete owned standalone trail emitters before clearing
		mTrailProxies.ForEach(scope (handle, proxy) =>
		{
			if (proxy.Emitter != null)
			{
				delete proxy.Emitter;
				proxy.Emitter = null;
			}
		});

		mMeshProxies.Clear();
		mSkinnedMeshProxies.Clear();
		mLightProxies.Clear();
		mCameraProxies.Clear();
		mParticleProxies.Clear();
		mSpriteProxies.Clear();
		mTrailProxies.Clear();
		mDecalProxies.Clear();
		mReflectionProbeProxies.Clear();
		mTerrainProxies.Clear();
		mWaterProxies.Clear();
		mGrassProxies.Clear();
		mCurveDecalProxies.Clear();
		mMainCamera = .Invalid;
		mMeshesDirty = true;
		mSkinnedMeshesDirty = true;
		mLightsDirty = true;
		mCamerasDirty = true;
		mParticlesDirty = true;
		mSpritesDirty = true;
		mTrailsDirty = true;
		mDecalsDirty = true;
		mReflectionProbesDirty = true;
		mTerrainsDirty = true;
		mWatersDirty = true;
		mGrassDirty = true;
		mCurveDecalsDirty = true;
	}

	public void Dispose()
	{
		Clear();
	}
}
