namespace Sedulous.Framework.Renderer;

using System;
using Sedulous.Mathematics;

/// Constants for clustered forward lighting.
static class ClusterConstants
{
	/// Number of cluster tiles in X.
	public const int32 CLUSTER_TILES_X = 16;
	/// Number of cluster tiles in Y.
	public const int32 CLUSTER_TILES_Y = 9;
	/// Number of depth slices.
	public const int32 CLUSTER_DEPTH_SLICES = 24;
	/// Total number of clusters.
	public const int32 CLUSTER_COUNT = CLUSTER_TILES_X * CLUSTER_TILES_Y * CLUSTER_DEPTH_SLICES;
	/// Maximum lights per cluster.
	public const int32 MAX_LIGHTS_PER_CLUSTER = 256;
	/// Maximum total lights in scene.
	public const int32 MAX_LIGHTS = 1024;
}

/// GPU-packed light data for shader consumption.
/// Matches the layout expected by lighting shaders.
[CRepr]
struct GPUClusteredLight
{
	/// Position (xyz) and type (w: 0=dir, 1=point, 2=spot)
	public Vector4 PositionType;
	/// Direction (xyz) and range (w)
	public Vector4 DirectionRange;
	/// Color (rgb) and intensity (a)
	public Vector4 ColorIntensity;
	/// x=cos(innerAngle), y=cos(outerAngle), z=shadowIndex, w=flags
	public Vector4 SpotShadowFlags;

	/// Creates from a LightProxy.
	public static Self FromProxy(LightProxy* proxy)
	{
		Self light = .();
		light.PositionType = .(
			proxy.Position.X, proxy.Position.Y, proxy.Position.Z,
			(float)proxy.Type
		);
		light.DirectionRange = .(
			proxy.Direction.X, proxy.Direction.Y, proxy.Direction.Z,
			proxy.Range
		);
		light.ColorIntensity = .(
			proxy.Color.X * proxy.Intensity,
			proxy.Color.Y * proxy.Intensity,
			proxy.Color.Z * proxy.Intensity,
			proxy.Intensity
		);
		light.SpotShadowFlags = .(
			Math.Cos(proxy.InnerConeAngle),
			Math.Cos(proxy.OuterConeAngle),
			(float)proxy.ShadowMapIndex,
			proxy.CastsShadows ? 1.0f : 0.0f
		);
		return light;
	}
}

/// Cluster AABB bounds for a single cluster.
[CRepr]
struct ClusterAABB
{
	/// Minimum point in view space.
	public Vector4 MinPoint;
	/// Maximum point in view space.
	public Vector4 MaxPoint;
}

/// Light grid entry - stores offset and count into light index list.
[CRepr]
struct LightGridEntry
{
	/// Offset into light index buffer.
	public uint32 Offset;
	/// Number of lights in this cluster.
	public uint32 Count;
	public uint32 _pad0;
	public uint32 _pad1;
}

/// Lighting uniform buffer data.
[CRepr]
struct LightingUniforms
{
	/// View matrix for cluster generation.
	public Matrix ViewMatrix;
	/// Inverse projection for cluster bounds.
	public Matrix InverseProjection;
	/// Screen dimensions (xy) and tile size (zw).
	public Vector4 ScreenParams;
	/// Near/far (xy), cluster depth params (zw).
	public Vector4 ClusterParams;
	/// Directional light direction (xyz), intensity (w).
	public Vector4 DirectionalDir;
	/// Directional light color (rgb), shadow index (a).
	public Vector4 DirectionalColor;
	/// Number of point/spot lights.
	public uint32 LightCount;
	/// Debug flags.
	public uint32 DebugFlags;
	public uint32 _pad0;
	public uint32 _pad1;

	public static Self Default => .()
	{
		ViewMatrix = .Identity,
		InverseProjection = .Identity,
		ScreenParams = .(1920, 1080, 120, 120),
		ClusterParams = .(0.1f, 1000.0f, 0, 0),
		DirectionalDir = .(0.5f, -0.707f, 0.5f, 1.0f),
		DirectionalColor = .(1.0f, 1.0f, 1.0f, -1.0f),
		LightCount = 0,
		DebugFlags = 0,
		_pad0 = 0,
		_pad1 = 0
	};
}

/// Shadow cascade data for directional light.
[CRepr]
struct CascadeData
{
	/// View-projection matrix for this cascade.
	public Matrix ViewProjection;
	/// Split depth (near, far, _, _).
	public Vector4 SplitDepths;
}

/// Shadow atlas slot for point/spot lights (CPU-side tracking).
struct ShadowAtlasSlot
{
	/// UV offset in atlas (xy) and size (zw).
	public Vector4 UVOffsetSize;
	/// Light index this slot belongs to.
	public int32 LightIndex;
	/// Face index for point lights (0-5).
	public int32 FaceIndex;
	public int32 _pad0;
	public int32 _pad1;
}

/// Constants for shadow mapping.
static class ShadowConstants
{
	/// Maximum frames in flight for GPU/CPU synchronization.
	public const int32 MAX_FRAMES_IN_FLIGHT = 2;
	/// Number of shadow cascades for directional light.
	public const int32 CASCADE_COUNT = 4;
	/// Resolution of each cascade shadow map.
	public const int32 CASCADE_MAP_SIZE = 2048;
	/// Size of the shadow atlas texture.
	public const int32 ATLAS_SIZE = 4096;
	/// Size of each tile in the shadow atlas.
	public const int32 TILE_SIZE = 512;
	/// Number of tiles per row in the atlas.
	public const int32 TILES_PER_ROW = ATLAS_SIZE / TILE_SIZE;
	/// Maximum number of shadow tiles in the atlas.
	public const int32 MAX_TILES = TILES_PER_ROW * TILES_PER_ROW;
	/// Maximum shadow tiles tracked in uniform buffer.
	public const int32 MAX_SHADOW_TILES = 64;
}

/// GPU-packed shadow tile data for shader consumption.
/// Used for point/spot light shadows in the atlas.
[CRepr]
struct GPUShadowTileData
{
	/// View-projection matrix for this shadow tile.
	public Matrix ViewProjection;
	/// UV offset (xy) and scale (zw) in atlas.
	public Vector4 UVOffsetScale;
	/// Light index this tile belongs to.
	public int32 LightIndex;
	/// Face index for point lights (0-5), -1 for spot.
	public int32 FaceIndex;
	public int32 _pad0;
	public int32 _pad1;
}

/// Shadow uniform buffer data for GPU.
/// Contains cascade and atlas shadow information.
[CRepr]
struct ShadowUniforms
{
	/// Cascade view-projection matrices and split depths (4 cascades).
	public CascadeData[ShadowConstants.CASCADE_COUNT] Cascades;
	/// Shadow tile data for point/spot lights.
	public GPUShadowTileData[ShadowConstants.MAX_SHADOW_TILES] ShadowTiles;
	/// Number of active shadow tiles in the atlas.
	public uint32 ActiveTileCount;
	/// Texel size for shadow atlas PCF (1.0 / ATLAS_SIZE).
	public float AtlasTexelSize;
	/// Texel size for cascade shadow maps (1.0 / CASCADE_MAP_SIZE).
	public float CascadeTexelSize;
	/// Whether directional light has shadows enabled.
	public uint32 DirectionalShadowEnabled;

	public static Self Default => .()
	{
		Cascades = default,
		ShadowTiles = default,
		ActiveTileCount = 0,
		AtlasTexelSize = 1.0f / ShadowConstants.ATLAS_SIZE,
		CascadeTexelSize = 1.0f / ShadowConstants.CASCADE_MAP_SIZE,
		DirectionalShadowEnabled = 0
	};
}
