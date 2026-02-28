namespace Sedulous.RenderGraph;

/// Configuration for the render graph, passed in at construction time.
public struct RenderGraphConfig
{
	/// Number of frame buffer slots for triple/double buffering.
	public int32 FrameBufferCount = 2;

	/// Size of each transient buffer pool in bytes.
	public uint64 TransientBufferPoolSize = 16 * 1024 * 1024; // 16 MB
}
