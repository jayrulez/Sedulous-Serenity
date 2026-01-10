namespace Sedulous.Renderer;

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
