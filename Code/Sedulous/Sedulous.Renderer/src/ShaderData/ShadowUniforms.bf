using System;
namespace Sedulous.Renderer;

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
