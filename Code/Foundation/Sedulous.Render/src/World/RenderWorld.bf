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
	private IDevice mDevice;

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

	// Trail emitter instances (owned by RenderWorld, read by ParticleFeature for rendering)
	private Dictionary<TrailEmitterProxyHandle, TrailEmitter> mTrailEmitters = new .() ~ DeleteDictionaryAndValues!(_);

	// Deferred deletion for trail emitters with in-flight GPU resources
	struct PendingTrailDeletion
	{
		public TrailEmitter Emitter;
		public int32 FramesRemaining;
	}
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

	/// Gets the trail emitter instances (owned by RenderWorld, read by ParticleFeature for rendering).
	public Dictionary<TrailEmitterProxyHandle, TrailEmitter> TrailEmitters => mTrailEmitters;

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
		// Delete owned trail emitter instances before clearing proxies
		for (let kv in mTrailEmitters)
			delete kv.value;
		mTrailEmitters.Clear();

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

	public this(IDevice device)
	{
		mDevice = device;
	}

	public void Dispose()
	{
		Clear();
	}
}
