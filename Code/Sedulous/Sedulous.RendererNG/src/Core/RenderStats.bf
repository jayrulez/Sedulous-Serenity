namespace Sedulous.RendererNG;

using System;

/// Performance statistics for the renderer.
/// Updated per-frame to track rendering performance.
struct RenderStats
{
	// ===== Draw Calls =====

	/// Total draw calls this frame.
	public int32 DrawCalls;

	/// Draw calls for static meshes.
	public int32 StaticMeshDrawCalls;

	/// Draw calls for skinned meshes.
	public int32 SkinnedMeshDrawCalls;

	/// Draw calls for particles.
	public int32 ParticleDrawCalls;

	/// Draw calls for sprites.
	public int32 SpriteDrawCalls;

	/// Draw calls for shadows.
	public int32 ShadowDrawCalls;

	// ===== Geometry =====

	/// Total triangles rendered.
	public int64 Triangles;

	/// Total vertices processed.
	public int64 Vertices;

	/// Static mesh instances rendered.
	public int32 StaticMeshInstances;

	/// Skinned meshes rendered.
	public int32 SkinnedMeshes;

	/// Sprites rendered.
	public int32 Sprites;

	/// Particles rendered.
	public int32 Particles;

	/// Trail vertices rendered.
	public int32 TrailVertices;

	// ===== Culling =====

	/// Meshes tested for visibility.
	public int32 MeshesTestedForVisibility;

	/// Meshes that passed visibility test.
	public int32 MeshesVisible;

	/// Meshes culled (not visible).
	public int32 MeshesCulled;

	// ===== Lighting =====

	/// Active lights this frame.
	public int32 ActiveLights;

	/// Clusters with lights.
	public int32 ClustersWithLights;

	/// Shadow casting lights.
	public int32 ShadowCastingLights;

	/// Shadow passes rendered.
	public int32 ShadowPasses;

	// ===== Resources =====

	/// GPU buffers allocated.
	public int32 BuffersAllocated;

	/// GPU textures allocated.
	public int32 TexturesAllocated;

	/// Bind groups allocated.
	public int32 BindGroupsAllocated;

	/// Pipelines in cache.
	public int32 PipelinesCached;

	/// Transient buffer memory used (bytes).
	public uint64 TransientBufferMemoryUsed;

	// ===== Batching =====

	/// Draw batches created.
	public int32 DrawBatches;

	/// Batches merged.
	public int32 BatchesMerged;

	// ===== Render Graph =====

	/// Render passes executed.
	public int32 RenderPassesExecuted;

	/// Barriers inserted.
	public int32 BarriersInserted;

	// ===== Timing (milliseconds) =====

	/// Total frame time.
	public float FrameTimeMs;

	/// Visibility resolution time.
	public float VisibilityTimeMs;

	/// GPU upload time.
	public float UploadTimeMs;

	/// Shadow rendering time.
	public float ShadowTimeMs;

	/// Main scene rendering time.
	public float SceneTimeMs;

	/// Resets all statistics to zero.
	public void Reset() mut
	{
		this = default;
	}

	/// Adds another stats instance (for aggregation).
	public void Add(RenderStats other) mut
	{
		DrawCalls += other.DrawCalls;
		StaticMeshDrawCalls += other.StaticMeshDrawCalls;
		SkinnedMeshDrawCalls += other.SkinnedMeshDrawCalls;
		ParticleDrawCalls += other.ParticleDrawCalls;
		SpriteDrawCalls += other.SpriteDrawCalls;
		ShadowDrawCalls += other.ShadowDrawCalls;

		Triangles += other.Triangles;
		Vertices += other.Vertices;
		StaticMeshInstances += other.StaticMeshInstances;
		SkinnedMeshes += other.SkinnedMeshes;
		Sprites += other.Sprites;
		Particles += other.Particles;
		TrailVertices += other.TrailVertices;

		MeshesTestedForVisibility += other.MeshesTestedForVisibility;
		MeshesVisible += other.MeshesVisible;
		MeshesCulled += other.MeshesCulled;

		ActiveLights += other.ActiveLights;
		ClustersWithLights += other.ClustersWithLights;
		ShadowCastingLights += other.ShadowCastingLights;
		ShadowPasses += other.ShadowPasses;

		BuffersAllocated += other.BuffersAllocated;
		TexturesAllocated += other.TexturesAllocated;
		BindGroupsAllocated += other.BindGroupsAllocated;
		PipelinesCached += other.PipelinesCached;
		TransientBufferMemoryUsed += other.TransientBufferMemoryUsed;

		DrawBatches += other.DrawBatches;
		BatchesMerged += other.BatchesMerged;

		RenderPassesExecuted += other.RenderPassesExecuted;
		BarriersInserted += other.BarriersInserted;
	}
}

/// Accumulated statistics over multiple frames.
class RenderStatsAccumulator
{
	private RenderStats mAccumulated;
	private RenderStats mMin;
	private RenderStats mMax;
	private int32 mFrameCount;

	/// Number of frames accumulated.
	public int32 FrameCount => mFrameCount;

	/// Accumulated totals.
	public RenderStats Total => mAccumulated;

	/// Records stats from a frame.
	public void RecordFrame(RenderStats stats)
	{
		if (mFrameCount == 0)
		{
			mMin = stats;
			mMax = stats;
		}
		else
		{
			// Update min/max for key metrics
			mMin.DrawCalls = Math.Min(mMin.DrawCalls, stats.DrawCalls);
			mMax.DrawCalls = Math.Max(mMax.DrawCalls, stats.DrawCalls);
			mMin.Triangles = Math.Min(mMin.Triangles, stats.Triangles);
			mMax.Triangles = Math.Max(mMax.Triangles, stats.Triangles);
			mMin.FrameTimeMs = Math.Min(mMin.FrameTimeMs, stats.FrameTimeMs);
			mMax.FrameTimeMs = Math.Max(mMax.FrameTimeMs, stats.FrameTimeMs);
		}

		mAccumulated.Add(stats);
		mFrameCount++;
	}

	/// Gets average draw calls per frame.
	public float AverageDrawCalls => mFrameCount > 0 ? (float)mAccumulated.DrawCalls / mFrameCount : 0;

	/// Gets average triangles per frame.
	public float AverageTriangles => mFrameCount > 0 ? (float)mAccumulated.Triangles / mFrameCount : 0;

	/// Gets average frame time.
	public float AverageFrameTimeMs => mFrameCount > 0 ? mAccumulated.FrameTimeMs / mFrameCount : 0;

	/// Gets minimum frame time.
	public float MinFrameTimeMs => mMin.FrameTimeMs;

	/// Gets maximum frame time.
	public float MaxFrameTimeMs => mMax.FrameTimeMs;

	/// Resets the accumulator.
	public void Reset()
	{
		mAccumulated.Reset();
		mMin.Reset();
		mMax.Reset();
		mFrameCount = 0;
	}
}
