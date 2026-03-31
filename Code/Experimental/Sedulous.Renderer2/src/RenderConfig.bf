namespace Sedulous.Renderer;

/// Configuration constants for the renderer.
/// All render features and subsystems reference these for consistency.
public static class RenderConfig
{
	// ==================== Frame Buffering ====================

	/// Number of frames to buffer for multi-buffering.
	public const int32 FrameBufferCount = 2;

	/// Maximum number of simultaneous views (split-screen).
	public const int32 MaxViews = 4;

	/// Total buffer slots (FrameBufferCount * MaxViews).
	public const int32 TotalBufferSlots = FrameBufferCount * MaxViews;

	/// Computes the buffer slot index for a given frame and view.
	/// Handles modulo on frameIndex so callers don't need to.
	public static int32 BufferSlot(int32 frameIndex, int32 viewIndex = 0)
	{
		return (frameIndex % FrameBufferCount) * MaxViews + viewIndex;
	}

	// ==================== Object Limits ====================

	/// Maximum opaque objects per frame.
	public const int32 MaxOpaqueObjectsPerFrame = 200000;

	/// Maximum transparent objects per frame.
	public const int32 MaxTransparentObjectsPerFrame = 256;

	/// Maximum total instances per frame.
	public const int32 MaxInstancesPerFrame = MaxOpaqueObjectsPerFrame + MaxTransparentObjectsPerFrame;

	/// Maximum instances per draw call for instanced rendering.
	public const int32 MaxInstancesPerDraw = 1024;

	// ==================== Lighting ====================

	/// Maximum total lights (all types combined).
	public const int32 MaxLights = 1024;

	/// Maximum lights per cluster for clustered lighting.
	public const int32 MaxLightsPerCluster = 256;

	/// Cluster grid dimensions.
	public const int32 ClusterCountX = 16;
	public const int32 ClusterCountY = 9;
	public const int32 ClusterCountZ = 24;
	public const int32 TotalClusterCount = ClusterCountX * ClusterCountY * ClusterCountZ;

	// ==================== Shadows ====================

	/// Shadow cascade count for directional lights.
	public const int32 ShadowCascadeCount = 4;

	/// Default shadow map resolution per cascade.
	public const int32 DefaultShadowMapResolution = 2048;

	/// Shadow atlas size for point/spot lights.
	public const int32 ShadowAtlasSize = 4096;

	// ==================== Skinning ====================

	/// Maximum bone count per skinned mesh.
	public const int32 MaxBonesPerMesh = 256;

	/// Maximum material slots per mesh (for multi-material submeshes).
	public const int MaxMaterialsPerMesh = 32;

	/// Maximum control points per curve decal.
	public const int32 MaxCurveDecalPoints = 32;

	// ==================== Buffers ====================

	/// Staging buffer size for mesh/texture uploads.
	public const uint64 StagingBufferSize = 64 * 1024 * 1024; // 64 MB

	/// Transient buffer pool size per frame.
	public const uint64 TransientBufferPoolSize = 16 * 1024 * 1024; // 16 MB
}
