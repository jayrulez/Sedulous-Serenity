namespace Sedulous.Renderer;

using System;

/// Per-frame rendering statistics.
struct RenderStats
{
	/// Total draw calls issued this frame.
	public int32 DrawCalls;
	/// Total triangles rendered this frame.
	public int32 Triangles;
	/// Number of visible objects after culling.
	public int32 VisibleObjects;
	/// Number of objects culled this frame.
	public int32 CulledObjects;
	/// Number of render graph passes executed.
	public int32 PassCount;
	/// Number of active lights.
	public int32 ActiveLights;
	/// GPU frame time in milliseconds (if timestamp queries available).
	public float GpuTimeMs;
	/// CPU frame time in milliseconds.
	public float CpuTimeMs;

	/// Resets all counters to zero.
	public void Reset() mut
	{
		this = default;
	}
}
