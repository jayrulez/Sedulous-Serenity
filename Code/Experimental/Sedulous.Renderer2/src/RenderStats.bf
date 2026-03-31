namespace Sedulous.Renderer;

/// Per-frame rendering statistics.
/// Reset at BeginFrame, accumulated during rendering, read after EndFrame.
public struct RenderStats
{
	/// Total draw calls issued.
	public int32 DrawCalls;
	/// Total instances rendered (across all draw calls).
	public int32 InstanceCount;
	/// Total compute dispatches.
	public int32 ComputeDispatches;
	/// Total triangles rendered (approximate).
	public int64 TriangleCount;
	/// Number of visible static meshes after culling.
	public int32 VisibleStaticMeshes;
	/// Number of visible skinned meshes after culling.
	public int32 VisibleSkinnedMeshes;
	/// Number of visible lights after culling.
	public int32 VisibleLights;
	/// Number of draw batches (after material grouping).
	public int32 BatchCount;
	/// Number of instance groups (instanced draw path).
	public int32 InstanceGroupCount;

	/// Reset all counters to zero.
	public void Reset() mut
	{
		this = default;
	}
}
