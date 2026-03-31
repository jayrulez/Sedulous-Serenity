namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;

/// A static mesh that passed frustum culling.
[CRepr]
struct VisibleMesh
{
	/// Handle back into the proxy pool.
	public ProxyHandle Handle;
	/// GPU mesh handle (for batching key).
	public GPUMeshHandle MeshHandle;
	/// Squared distance from camera to AABB center.
	public float DistanceSq;
	/// Selected LOD level (0 = highest detail).
	public uint8 LODLevel;
	/// Composite sort key for ordering draw calls.
	public uint64 SortKey;
}

/// A skinned mesh that passed frustum culling.
[CRepr]
struct VisibleSkinnedMesh
{
	/// Handle back into the skinned mesh proxy pool.
	public ProxyHandle Handle;
	/// GPU mesh handle (skinned vertex data).
	public GPUMeshHandle MeshHandle;
	/// Squared distance from camera to AABB center.
	public float DistanceSq;
	/// Selected LOD level (0 = highest detail).
	public uint8 LODLevel;
	/// Composite sort key for ordering draw calls.
	public uint64 SortKey;
}

/// A light that passed frustum culling (or is directional).
[CRepr]
struct VisibleLight
{
	/// Handle back into the proxy pool.
	public ProxyHandle Handle;
	/// Light type.
	public LightType Type;
	/// Squared distance from camera.
	public float DistanceSq;
	/// Whether this light casts shadows.
	public bool CastsShadows;
}

/// Instance data uploaded to the GPU for instanced rendering.
[CRepr]
struct InstanceData
{
	/// World transform matrix (64 bytes).
	public Matrix WorldMatrix;
}

/// Sort key helpers for draw call ordering.
static class SortKeyHelper
{
	/// Opaque: material in high bits (minimize state changes), depth as tiebreaker.
	public static uint64 MakeOpaqueSortKey(uint32 materialIndex, uint32 meshIndex, uint8 lod, float distanceSq)
	{
		// Pack: [16-bit material | 16-bit mesh | 8-bit LOD | 24-bit depth]
		let depthBits = (uint32)(Math.Min(distanceSq, 16777215.0f));
		return ((uint64)materialIndex << 48) |
			   ((uint64)(meshIndex & 0xFFFF) << 32) |
			   ((uint64)lod << 24) |
			   (uint64)(depthBits & 0xFFFFFF);
	}

	/// Transparent: depth dominates (back-to-front), material as tiebreaker.
	public static uint64 MakeTransparentSortKey(float distanceSq, uint32 materialIndex)
	{
		// Invert depth so larger distance sorts first (back-to-front via ascending sort)
		let invDepth = uint32.MaxValue - (uint32)(Math.Min(distanceSq, (float)uint32.MaxValue));
		return ((uint64)invDepth << 32) | (uint64)materialIndex;
	}
}
