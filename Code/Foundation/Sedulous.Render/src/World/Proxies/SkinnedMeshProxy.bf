namespace Sedulous.Render;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Materials;

/// Skinning method for GPU skinning.
public enum SkinningMethod : uint8
{
	/// Linear blend skinning with matrices.
	LinearBlend,

	/// Dual quaternion skinning (better for twisting).
	DualQuaternion
}

/// Proxy for a skinned mesh in the render world.
/// Contains all data needed to render an animated mesh instance.
public struct SkinnedMeshProxy
{
	/// Handle to the GPU mesh data.
	public GPUMeshHandle MeshHandle;

	/// Handle to the GPU bone transform buffer.
	public GPUBoneBufferHandle BoneBufferHandle;

	/// Material instances for rendering (one per submesh slot).
	public MaterialInstance[RenderConfig.MaxMaterialsPerMesh] Materials;

	/// Number of active material slots.
	public int32 MaterialCount;

	/// World transform matrix (root transform).
	public Matrix WorldMatrix;

	/// Previous frame world matrix (for motion vectors).
	public Matrix PrevWorldMatrix;

	/// World-space bounding box (should include animation bounds).
	public BoundingBox WorldBounds;

	/// Local-space bounding box (bind pose bounds).
	public BoundingBox LocalBounds;

	/// Extended bounds to account for animation (optional padding).
	public BoundingBox AnimationBounds;

	/// Rendering flags (same as MeshProxy).
	public MeshFlags Flags;

	/// Number of bones in the skeleton.
	public uint16 BoneCount;

	/// Skinning method to use.
	public SkinningMethod SkinningMethod;

	/// LOD level (0 = highest detail).
	public uint8 LODLevel;

	/// Render layer mask (for layer-based rendering).
	public uint32 LayerMask;

	/// Custom sort key for render order control.
	public uint32 SortKey;

	/// Generation counter (for handle validation).
	public uint32 Generation;

	/// Whether this proxy slot is in use.
	public bool IsActive;

	/// Whether bone transforms are dirty and need upload.
	public bool BonesDirty;

	/// Whether the proxy is visible.
	public bool IsVisible => (Flags & .Visible) != 0 && IsActive;

	/// Whether the mesh casts shadows.
	public bool CastsShadows => (Flags & .CastShadows) != 0;

	/// Whether the mesh receives shadows.
	public bool ReceivesShadows => (Flags & .ReceiveShadows) != 0;

	/// Whether motion vectors should be generated.
	public bool HasMotionVectors => (Flags & .MotionVectors) != 0;

	/// Updates the world transform and derived values.
	public void SetTransform(Matrix worldMatrix) mut
	{
		PrevWorldMatrix = WorldMatrix;
		WorldMatrix = worldMatrix;

		// Transform animation bounds to world space
		WorldBounds = TransformBounds(AnimationBounds, worldMatrix);
	}

	/// Updates transform without saving previous (for initialization).
	public void SetTransformImmediate(Matrix worldMatrix) mut
	{
		WorldMatrix = worldMatrix;
		PrevWorldMatrix = worldMatrix;

		WorldBounds = TransformBounds(AnimationBounds, worldMatrix);
	}

	/// Sets the local bounds (typically from the mesh data in bind pose).
	public void SetLocalBounds(BoundingBox bounds) mut
	{
		LocalBounds = bounds;
		// Default animation bounds to local bounds with some padding
		AnimationBounds = ExpandBounds(bounds, 1.2f);
		WorldBounds = TransformBounds(AnimationBounds, WorldMatrix);
	}

	/// Sets expanded animation bounds (should encompass all animation poses).
	public void SetAnimationBounds(BoundingBox bounds) mut
	{
		AnimationBounds = bounds;
		WorldBounds = TransformBounds(bounds, WorldMatrix);
	}

	/// Marks bone transforms as needing upload.
	public void MarkBonesDirty() mut
	{
		BonesDirty = true;
	}

	/// Clears the bones dirty flag after upload.
	public void ClearBonesDirty() mut
	{
		BonesDirty = false;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		MeshHandle = .Invalid;
		BoneBufferHandle = .Invalid;
		Materials = .();
		MaterialCount = 0;
		WorldMatrix = .Identity;
		PrevWorldMatrix = .Identity;
		WorldBounds = .(Vector3.Zero, Vector3.Zero);
		LocalBounds = .(Vector3.Zero, Vector3.Zero);
		AnimationBounds = .(Vector3.Zero, Vector3.Zero);
		Flags = .None;
		BoneCount = 0;
		SkinningMethod = .LinearBlend;
		LODLevel = 0;
		LayerMask = 0xFFFFFFFF;
		SortKey = 0;
		IsActive = false;
		BonesDirty = false;
	}

	/// Expands a bounding box by a scale factor.
	private static BoundingBox ExpandBounds(BoundingBox bounds, float scale)
	{
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let halfExtent = (bounds.Max - bounds.Min) * 0.5f * scale;
		return .(center - halfExtent, center + halfExtent);
	}

	/// Transforms a bounding box by a matrix.
	private static BoundingBox TransformBounds(BoundingBox bounds, Matrix matrix)
	{
		// Transform all 8 corners and find new AABB
		Vector3[8] corners = .(
			.(bounds.Min.X, bounds.Min.Y, bounds.Min.Z),
			.(bounds.Max.X, bounds.Min.Y, bounds.Min.Z),
			.(bounds.Min.X, bounds.Max.Y, bounds.Min.Z),
			.(bounds.Max.X, bounds.Max.Y, bounds.Min.Z),
			.(bounds.Min.X, bounds.Min.Y, bounds.Max.Z),
			.(bounds.Max.X, bounds.Min.Y, bounds.Max.Z),
			.(bounds.Min.X, bounds.Max.Y, bounds.Max.Z),
			.(bounds.Max.X, bounds.Max.Y, bounds.Max.Z)
		);

		Vector3 newMin = .(float.MaxValue, float.MaxValue, float.MaxValue);
		Vector3 newMax = .(float.MinValue, float.MinValue, float.MinValue);

		for (let corner in corners)
		{
			let transformed = Vector3.Transform(corner, matrix);
			newMin = Vector3.Min(newMin, transformed);
			newMax = Vector3.Max(newMax, transformed);
		}

		return .(newMin, newMax);
	}
}

/// GPU-side bone transform data for a single skeleton instance.
/// This is uploaded per-frame when bones change.
[CRepr]
public struct BoneTransforms
{
	/// Current frame bone matrices (model space -> bone space -> model space).
	/// These are the final skinning matrices: inverseBindPose * currentPose.
	public Matrix[RenderConfig.MaxBonesPerMesh] BoneMatrices;

	/// Previous frame bone matrices (for motion vectors).
	public Matrix[RenderConfig.MaxBonesPerMesh] PrevBoneMatrices;

	/// Size in bytes for a given bone count.
	public static uint64 GetSizeForBoneCount(int32 boneCount)
	{
		// Two matrices per bone
		return (uint64)(boneCount * sizeof(Matrix) * 2);
	}
}
