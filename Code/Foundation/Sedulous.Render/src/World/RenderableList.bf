namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Materials;

/// Scene renderable data populated by RenderWorld before the renderer runs.
/// Contains all potentially visible objects — the renderer culls, batches, and
/// draws from this data. Pure rendering data: no scene/ECS types, no proxy pool
/// references. This is the seam between RenderWorld (scene-side) and the rest of
/// Sedulous.Render (renderer-side features, visibility, batching, post-process).
///
/// Populated by: RenderWorld.PopulateRenderables(RenderableList)
/// Consumed by:  RenderSystem → VisibilityResolver → DrawBatcher → features
public class RenderableList
{
	// ==================== Meshes ====================

	/// All opaque static meshes in the scene.
	public List<MeshRenderable> OpaqueMeshes = new .() ~ delete _;

	/// All transparent static meshes in the scene.
	public List<MeshRenderable> TransparentMeshes = new .() ~ delete _;

	/// All skinned meshes in the scene.
	public List<SkinnedMeshRenderable> SkinnedMeshes = new .() ~ delete _;

	// ==================== Lights ====================

	/// All lights in the scene.
	public List<LightRenderable> Lights = new .() ~ delete _;

	// ==================== Sprites ====================

	/// All sprites in the scene.
	public List<SpriteRenderable> Sprites = new .() ~ delete _;

	// ==================== Decals ====================

	/// All decals in the scene.
	public List<DecalRenderable> Decals = new .() ~ delete _;

	/// All curve decals in the scene.
	public List<CurveDecalRenderable> CurveDecals = new .() ~ delete _;

	// ==================== Particles ====================

	/// GPU particle emitters.
	public List<GPUParticleRenderable> GPUParticles = new .() ~ delete _;

	/// CPU particle emitters.
	public List<CPUParticleRenderable> CPUParticles = new .() ~ delete _;

	/// Trail emitters (standalone and particle trails).
	public List<TrailRenderable> Trails = new .() ~ delete _;

	// ==================== Terrain ====================

	/// All terrain patches.
	public List<TerrainRenderable> Terrains = new .() ~ delete _;

	// ==================== Grass ====================

	/// All grass patches.
	public List<GrassRenderable> GrassPatches = new .() ~ delete _;

	// ==================== Water ====================

	/// All water surfaces.
	public List<WaterRenderable> WaterSurfaces = new .() ~ delete _;

	// ==================== Reflection Probes ====================

	/// All reflection probes.
	public List<ReflectionProbeRenderable> ReflectionProbes = new .() ~ delete _;

	// ==================== Environment ====================

	/// Scene-level environment and rendering settings.
	public EnvironmentData Environment;

	/// Source identifier — distinguishes renderables from different worlds.
	/// Used by systems that cache per-handle data across frames (e.g. skinning,
	/// reflection probes) so handles from different producers don't collide.
	public uint32 SourceId;

	// ==================== Lifecycle ====================

	/// Clears all channels for the next frame.
	public void Clear()
	{
		OpaqueMeshes.Clear();
		TransparentMeshes.Clear();
		SkinnedMeshes.Clear();
		Lights.Clear();
		Sprites.Clear();
		Decals.Clear();
		CurveDecals.Clear();
		GPUParticles.Clear();
		CPUParticles.Clear();
		Trails.Clear();
		Terrains.Clear();
		GrassPatches.Clear();
		WaterSurfaces.Clear();
		ReflectionProbes.Clear();
		Environment = .();
	}
}

// ==================== Mesh Renderables ====================

/// A static mesh in the scene (pre-cull). One entry per mesh proxy (not per submesh) —
/// the full Materials array travels with the renderable so the forward pass can
/// resolve per-submesh materials without reaching back to RenderWorld.
public struct MeshRenderable
{
	public GPUMeshHandle MeshHandle;
	public MaterialInstance[RenderConfig.MaxMaterialsPerMesh] Materials;
	public int32 MaterialCount;
	public Matrix WorldMatrix;
	public Matrix PrevWorldMatrix;
	public BoundingBox WorldBounds;
	public MeshFlags Flags;
	public uint32 LayerMask;
	public int32 LODLevel;
	public IBindGroup ObjectBindGroup;
	public MeshRenderHandle MeshRenderHandle;
}

/// A skinned mesh in the scene (pre-cull). One entry per mesh proxy.
public struct SkinnedMeshRenderable
{
	public GPUMeshHandle MeshHandle;
	public GPUBoneBufferHandle BoneBufferHandle;
	public MaterialInstance[RenderConfig.MaxMaterialsPerMesh] Materials;
	public int32 MaterialCount;
	public Matrix WorldMatrix;
	public Matrix PrevWorldMatrix;
	public BoundingBox WorldBounds;
	public MeshFlags Flags;
	public uint32 LayerMask;
	public uint16 BoneCount;
	public int32 LODLevel;

	/// Handle for skinning system lookups (cache key).
	public SkinnedMeshRenderHandle SkinnedMeshHandle;
}

// ==================== Light Renderables ====================

/// A light in the scene (pre-cull).
public struct LightRenderable
{
	public LightType Type;
	public Vector3 Position;
	public Vector3 Direction;
	public Vector3 Color;
	public float Intensity;
	public float Range;
	public float InnerConeAngle;
	public float OuterConeAngle;
	public bool CastsShadows;
	public int32 ShadowIndex;
	public float ShadowBias;
	public float ShadowNormalBias;
	public uint32 LayerMask;
	public LightRenderHandle LightHandle;
}

// ==================== Sprite Renderables ====================

/// A sprite in the scene (pre-cull).
public struct SpriteRenderable
{
	public Vector3 Position;
	public Vector2 Size;
	public Color Color;
	public ITextureView Texture;
	public Vector4 UVRect;
	public uint32 LayerMask;
}

// ==================== Decal Renderables ====================

/// A decal in the scene (pre-cull).
public struct DecalRenderable
{
	public Matrix WorldMatrix;
	public Matrix InvWorldMatrix;
	public Vector3 Scale;
	public Vector4 Color;
	public float AngleFadeStart;
	public float AngleFadeEnd;
	public int32 SortOrder;
	public DecalBlendMode BlendMode;
	public ITextureView AlbedoTexture;
	public ISampler Sampler;
}

/// A curve decal in the scene (pre-cull).
public struct CurveDecalRenderable
{
	public CurveDecalPoint[RenderConfig.MaxCurveDecalPoints] ControlPoints;
	public int32 PointCount;
	public Vector4 Color;
	public DecalBlendMode BlendMode;
	public int32 SortOrder;
	public ITextureView AlbedoTexture;
	public ISampler Sampler;
	public float UVTilingU;
	public float UVTilingV;
	public float ProjectionDepth;
	public BoundingBox WorldBounds;
}

// ==================== Particle Renderables ====================

/// A GPU particle emitter in the scene.
public struct GPUParticleRenderable
{
	public ParticleEmitterRenderHandle EmitterHandle;
	public IBuffer ParticleBuffer;
	public IBuffer IndirectBuffer;
	public ITextureView ParticleTexture;
	public ParticleBlendMode BlendMode;
	public ParticleRenderMode RenderMode;
	public float SoftParticleDistance;
	public float StretchFactor;
	public uint32 AliveCount;
	public uint32 LayerMask;
}

/// A CPU particle emitter in the scene.
public struct CPUParticleRenderable
{
	public ParticleEmitterRenderHandle EmitterHandle;
	public IBuffer VertexBuffer;
	public uint32 AliveCount;
	public ParticleBlendMode BlendMode;
	public ParticleRenderMode RenderMode;
	public float SoftParticleDistance;
	public bool SortParticles;
	public bool Lit;
	public int32 AtlasColumns;
	public int32 AtlasRows;
	public uint32 LayerMask;
	public bool HasTrails;
	public IBuffer TrailVertexBuffer;
	public int32 TrailVertexCount;
}

/// A trail emitter in the scene (standalone or particle trail).
public struct TrailRenderable
{
	public TrailEmitterRenderHandle TrailHandle;
	public IBuffer VertexBuffer;
	public int32 VertexCount;
	public ParticleBlendMode BlendMode;
	public float SoftParticleDistance;
	public uint32 LayerMask;
}

// ==================== Terrain Renderables ====================

/// A terrain in the scene.
public struct TerrainRenderable
{
	public int32 PatchCountX;
	public int32 PatchCountZ;
	public Vector3 Origin;
	public Vector2 WorldSize;
	public float HeightScale;
	public uint32 HeightmapWidth;
	public uint32 HeightmapHeight;
	public Vector4 LayerScales;
	public float Roughness;
	public float Metallic;
	public ITextureView HeightmapView;
	public ITextureView NormalMapView;
	public ITextureView SplatmapView;
	public ITextureView[4] LayerAlbedoViews;
	public BoundingBox WorldBounds;
}

// ==================== Grass Renderables ====================

/// A grass patch in the scene.
public struct GrassRenderable
{
	public Vector3 Origin;
	public Vector2 WorldSize;
	public float HeightScale;
	public float* HeightmapData;
	public uint32 HeightmapWidth;
	public uint32 HeightmapHeight;
	public uint8* SplatmapData;
	public uint32 SplatmapWidth;
	public uint32 SplatmapHeight;
	public int32 SplatChannel;
	public float SplatThreshold;
	public ITextureView AlbedoView;
	public Vector3 GrassColor;
	public float AlphaCutoff;
	public float Roughness;
	public float BladeWidth;
	public float BladeHeight;
	public float Distance;
	public float Density;
	public float MinScale;
	public float MaxScale;
	public float WindStrength;
	public float WindFrequency;
	public Vector2 WindDirection;
	public BoundingBox WorldBounds;
}

// ==================== Water Renderables ====================

/// A water surface in the scene.
public struct WaterRenderable
{
	public Vector3 Center;
	public Vector2 WorldSize;
	public Vector4 WaterColor;
	public float WaveSpeed;
	public float WaveScale;
	public float NormalStrength;
	public float FresnelR0;
	public float RefractionStrength;
	public float SpecularPower;
	public float MaxVisibleDepth;
	public float FoamDepthThreshold;
	public float FoamIntensity;
	public float Roughness;
	public Vector2 FlowDirection;
	public ITextureView NormalMapView;
	public ITextureView FoamTextureView;
	public BoundingBox WorldBounds;
}

// ==================== Reflection Probe Renderables ====================

/// A reflection probe in the scene.
/// Note: ArrayLayer and IsDirty are round-tripped — ReflectionProbeSystem mutates
/// them on the renderable during UpdateProbeUniforms, and RenderWorld reads those
/// mutations back into the proxy so they persist across frames.
public struct ReflectionProbeRenderable
{
	public ReflectionProbeRenderHandle ProbeHandle;
	public Vector3 Position;
	public float Radius;
	public bool IsEnabled;
	public int32 ArrayLayer;
	public bool IsDirty;
	public Color ZenithColor;
	public Color HorizonColor;
	public Color GroundColor;
	public Vector4[9] IrradianceSH;
}

// ==================== Environment Data ====================

/// Scene-level rendering environment settings, snapshotted each frame.
/// Field defaults match RenderWorld's defaults so that when no world is active
/// (or .Clear() resets the list) consumers get sensible values.
public struct EnvironmentData
{
	public Vector3 AmbientColor;
	public float AmbientIntensity = 1.0f;
	public float Exposure = 1.0f;
	public TonemapOperator Tonemap = .ACES;
	public AAMode AA = .None;
	public bool InstancingEnabled = true;
	public float LODBias = 1.0f;
}
