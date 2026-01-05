namespace Sedulous.Framework.Renderer;

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
