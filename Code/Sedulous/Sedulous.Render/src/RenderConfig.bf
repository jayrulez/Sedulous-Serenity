namespace Sedulous.Render;

/// Configuration constants for the renderer.
/// All render features should reference these constants for consistency.
static class RenderConfig
{
	// ==================== Frame Buffering ====================

	/// Number of frames to buffer for multi-buffering.
	public const int32 FrameBufferCount = 2;

	// ==================== Object Limits ====================

	/// Maximum opaque objects per frame.
	public const int32 MaxOpaqueObjectsPerFrame = 2048;

	/// Maximum transparent objects per frame.
	public const int32 MaxTransparentObjectsPerFrame = 256;

	/// Maximum debug vertices for debug rendering.
	public const int32 MaxDebugVertices = 65536;

	// ==================== Lighting ====================

	/// Maximum number of point lights supported.
	public const int32 MaxPointLights = 256;

	/// Maximum number of spot lights supported.
	public const int32 MaxSpotLights = 128;

	/// Maximum number of area lights supported.
	public const int32 MaxAreaLights = 32;

	/// Maximum total lights (all types combined).
	public const int32 MaxLights = 1024;

	/// Maximum lights per cluster for clustered lighting.
	public const int32 MaxLightsPerCluster = 256;

	/// Cluster grid dimensions.
	public const int32 ClusterCountX = 16;
	public const int32 ClusterCountY = 9;
	public const int32 ClusterCountZ = 24;
	public const int32 TotalClusterCount = ClusterCountX * ClusterCountY * ClusterCountZ;

	/// Shadow cascade count for directional lights.
	public const int32 ShadowCascadeCount = 4;

	/// Default shadow map resolution per cascade.
	public const int32 DefaultShadowMapResolution = 2048;

	/// Shadow atlas size for point/spot lights.
	public const int32 ShadowAtlasSize = 4096;

	/// Maximum instances per draw call for instanced rendering.
	public const int32 MaxInstancesPerDraw = 1024;

	/// Maximum total instances per frame (buffer capacity for all instance groups).
	/// Should be at least MaxOpaqueObjectsPerFrame + MaxTransparentObjectsPerFrame.
	public const int32 MaxInstancesPerFrame = MaxOpaqueObjectsPerFrame + MaxTransparentObjectsPerFrame;

	/// Maximum bone count for skinned meshes.
	public const int32 MaxBonesPerMesh = 256;

	/// Maximum particle count per emitter.
	public const int32 MaxParticlesPerEmitter = 65536;

	/// Staging buffer size for mesh/texture uploads.
	public const uint64 StagingBufferSize = 64 * 1024 * 1024; // 64 MB

	/// Transient buffer pool size per frame.
	public const uint64 TransientBufferPoolSize = 16 * 1024 * 1024; // 16 MB
}
