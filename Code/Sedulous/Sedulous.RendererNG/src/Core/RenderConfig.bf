namespace Sedulous.RendererNG;

using Sedulous.RHI;

/// Central configuration constants for the RendererNG system.
/// All subsystems should reference these constants instead of defining their own.
static class RenderConfig
{
	// ===== Frame Management =====

	/// Maximum frames in flight (uses RHI constant for consistency).
	public const int32 MAX_FRAMES_IN_FLIGHT = FrameConfig.MAX_FRAMES_IN_FLIGHT;

	/// Frames to defer deletion to ensure GPU has finished using resources.
	public const int32 DELETION_DEFER_FRAMES = FrameConfig.DELETION_DEFER_FRAMES;

	// ===== View System =====

	/// Maximum simultaneous render views (main camera + secondary cameras).
	/// Supports: main camera, split-screen, reflections, portals.
	public const int32 MAX_VIEWS = 4;

	/// Maximum shadow views per frame (cascades + local shadow tiles).
	public const int32 MAX_SHADOW_VIEWS = 16;

	// ===== Mesh Rendering =====

	/// Maximum static mesh instances per frame.
	public const int32 MAX_STATIC_MESH_INSTANCES = 16384;

	/// Maximum skinned meshes per frame.
	public const int32 MAX_SKINNED_MESHES = 256;

	/// Maximum bones per skinned mesh.
	public const int32 MAX_BONES_PER_MESH = 256;

	/// Default vertex buffer size for transient allocations (16 MB).
	public const uint32 TRANSIENT_VERTEX_BUFFER_SIZE = 16 * 1024 * 1024;

	/// Default index buffer size for transient allocations (8 MB).
	public const uint32 TRANSIENT_INDEX_BUFFER_SIZE = 8 * 1024 * 1024;

	/// Default uniform buffer size for transient allocations (4 MB).
	public const uint32 TRANSIENT_UNIFORM_BUFFER_SIZE = 4 * 1024 * 1024;

	// ===== Sprites =====

	/// Maximum sprites per frame.
	public const int32 MAX_SPRITES = 50000;

	// ===== Particles =====

	/// Maximum particles per frame across all emitters.
	public const int32 MAX_PARTICLES = 100000;

	/// Maximum trail vertices per frame.
	public const int32 MAX_TRAIL_VERTICES = 16384;

	/// Maximum particle emitters per scene.
	public const int32 MAX_PARTICLE_EMITTERS = 1024;

	// ===== Lighting =====

	/// Maximum point lights in forward pass uniform buffer.
	public const int32 MAX_POINT_LIGHTS = 4;

	/// Maximum lights per scene.
	public const int32 MAX_LIGHTS = 1024;

	/// Maximum lights per cluster.
	public const int32 MAX_LIGHTS_PER_CLUSTER = 256;

	/// Cluster grid X dimension (horizontal tiles).
	public const int32 CLUSTER_GRID_X = 16;

	/// Cluster grid Y dimension (vertical tiles).
	public const int32 CLUSTER_GRID_Y = 9;

	/// Cluster grid Z dimension (depth slices).
	public const int32 CLUSTER_GRID_Z = 24;

	/// Total number of clusters.
	public const int32 CLUSTER_COUNT = CLUSTER_GRID_X * CLUSTER_GRID_Y * CLUSTER_GRID_Z;

	// ===== Shadows =====

	/// Number of shadow cascades for directional light.
	public const int32 CASCADE_COUNT = 4;

	/// Shadow cascade map resolution (width and height).
	public const int32 CASCADE_MAP_SIZE = 2048;

	/// Shadow atlas resolution (width and height).
	public const int32 SHADOW_ATLAS_SIZE = 4096;

	/// Shadow atlas tile size (width and height).
	public const int32 SHADOW_TILE_SIZE = 256;

	/// Number of tiles per row/column in shadow atlas.
	public const int32 SHADOW_TILES_PER_ROW = SHADOW_ATLAS_SIZE / SHADOW_TILE_SIZE;

	/// Total shadow tiles in atlas.
	public const int32 SHADOW_TILE_COUNT = SHADOW_TILES_PER_ROW * SHADOW_TILES_PER_ROW;

	/// Default shadow bias for directional lights.
	public const int32 DEFAULT_SHADOW_BIAS = 2;

	/// Default shadow slope scale for directional lights.
	public const float DEFAULT_SHADOW_SLOPE_SCALE = 2.0f;

	// ===== Resource Pools =====

	/// Initial capacity for buffer pool.
	public const int32 INITIAL_BUFFER_POOL_CAPACITY = 256;

	/// Initial capacity for texture pool.
	public const int32 INITIAL_TEXTURE_POOL_CAPACITY = 128;

	/// Initial capacity for bind group pool.
	public const int32 INITIAL_BIND_GROUP_POOL_CAPACITY = 512;

	/// Initial capacity for pipeline cache.
	public const int32 INITIAL_PIPELINE_CACHE_CAPACITY = 64;

	// ===== Proxy Pools =====

	/// Initial capacity for static mesh proxy pool.
	public const int32 INITIAL_STATIC_MESH_PROXY_CAPACITY = 1024;

	/// Initial capacity for skinned mesh proxy pool.
	public const int32 INITIAL_SKINNED_MESH_PROXY_CAPACITY = 64;

	/// Initial capacity for light proxy pool.
	public const int32 INITIAL_LIGHT_PROXY_CAPACITY = 128;

	/// Initial capacity for camera proxy pool.
	public const int32 INITIAL_CAMERA_PROXY_CAPACITY = 8;

	/// Initial capacity for sprite proxy pool.
	public const int32 INITIAL_SPRITE_PROXY_CAPACITY = 1024;

	/// Initial capacity for particle emitter proxy pool.
	public const int32 INITIAL_PARTICLE_EMITTER_PROXY_CAPACITY = 128;

	/// Initial capacity for force field proxy pool.
	public const int32 INITIAL_FORCE_FIELD_PROXY_CAPACITY = 32;

	// ===== Default Formats =====

	/// Default color format for render targets.
	public const TextureFormat DEFAULT_COLOR_FORMAT = .BGRA8Unorm;

	/// Default depth format for render targets.
	public const TextureFormat DEFAULT_DEPTH_FORMAT = .Depth32FloatStencil8;

	/// Shadow map depth format.
	public const TextureFormat SHADOW_DEPTH_FORMAT = .Depth32Float;

	// ===== Alignment =====

	/// Uniform buffer alignment (256 bytes for most GPUs).
	public const uint32 UNIFORM_BUFFER_ALIGNMENT = 256;

	/// Storage buffer alignment (typically 16 bytes).
	public const uint32 STORAGE_BUFFER_ALIGNMENT = 16;

	/// Vertex buffer alignment.
	public const uint32 VERTEX_BUFFER_ALIGNMENT = 16;

	/// Index buffer alignment.
	public const uint32 INDEX_BUFFER_ALIGNMENT = 4;
}
