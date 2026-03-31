namespace Sedulous.Renderer;

/// All renderer configuration constants.
static class RenderConfig
{
	/// Number of frames that can be in flight simultaneously.
	public const int FrameBufferCount = 2;

	/// Maximum number of simultaneous render views (split-screen, etc.).
	public const int MaxViews = 4;

	/// Maximum opaque objects in the render world.
	public const int MaxOpaqueObjects = 200000;

	/// Maximum transparent objects in the render world.
	public const int MaxTransparentObjects = 256;

	/// Maximum lights in the scene.
	public const int MaxLights = 1024;

	/// Maximum lights affecting a single cluster.
	public const int MaxLightsPerCluster = 128;

	/// Cluster grid dimensions for Forward+ light culling.
	public const int ClusterCountX = 16;
	public const int ClusterCountY = 9;
	public const int ClusterCountZ = 24;

	/// Shadow cascade count for directional lights.
	public const int ShadowCascadeCount = 4;

	/// Shadow map resolution per cascade.
	public const int ShadowMapResolution = 2048;

	/// Shadow atlas size for point/spot lights.
	public const int ShadowAtlasSize = 4096;

	/// Shadow atlas tile size.
	public const int ShadowAtlasTileSize = 512;

	/// Shadow atlas tiles per side.
	public const int ShadowAtlasTilesPerSide = ShadowAtlasSize / ShadowAtlasTileSize;

	/// Total shadow atlas tiles.
	public const int ShadowAtlasTotalTiles = ShadowAtlasTilesPerSide * ShadowAtlasTilesPerSide;

	/// Maximum shadow-casting point lights (6 tiles each).
	public const int MaxShadowPointLights = 8;

	/// Maximum shadow-casting spot lights (1 tile each).
	public const int MaxShadowSpotLights = 16;

	/// Maximum bones per skeletal mesh.
	public const int MaxBonesPerMesh = 256;

	/// Maximum instances per instanced draw call.
	public const int MaxInstancesPerDraw = 1024;

	/// Maximum material slots per mesh.
	public const int MaxMaterialsPerMesh = 32;

	/// Total buffer slots for multi-buffered, per-view resources.
	/// Mapped CpuToGpu buffers whose content differs per view need this many slots
	/// to avoid overwrites when batching multiple views into one submission.
	public const int TotalBufferSlots = FrameBufferCount * MaxViews;

	/// Computes the buffer slot index for a given frame and view.
	public static int BufferSlot(int frameIndex, int viewIndex) => frameIndex * MaxViews + viewIndex;
}
