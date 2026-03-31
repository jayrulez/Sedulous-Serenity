namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Materials;

/// Skinning method for GPU skinning.
public enum SkinningMethod : uint8
{
	LinearBlend,
	DualQuaternion
}

/// Proxy for a skinned mesh in the render world.
public struct SkinnedMeshProxy
{
	public GPUMeshHandle MeshHandle;
	public GPUBoneBufferHandle BoneBufferHandle;
	public MaterialInstance[RenderConfig.MaxMaterialsPerMesh] Materials;
	public int32 MaterialCount;
	public Matrix WorldMatrix;
	public Matrix PrevWorldMatrix;
	public BoundingBox WorldBounds;
	public BoundingBox LocalBounds;
	public BoundingBox AnimationBounds;
	public MeshFlags Flags;
	public uint16 BoneCount;
	public SkinningMethod SkinningMethod;
	public uint8 LODLevel;
	public uint32 LayerMask;
	public uint32 SortKey;
	public uint32 Generation;
	public bool IsActive;
	public bool BonesDirty;

	public bool IsVisible => (Flags & .Visible) != 0 && IsActive;
	public bool CastsShadows => (Flags & .CastShadows) != 0;
	public bool ReceivesShadows => (Flags & .ReceiveShadows) != 0;
	public bool HasMotionVectors => (Flags & .MotionVectors) != 0;

	public void SetTransform(Matrix worldMatrix) mut
	{
		PrevWorldMatrix = WorldMatrix;
		WorldMatrix = worldMatrix;
		WorldBounds = BoundsHelper.TransformBounds(AnimationBounds, worldMatrix);
	}

	public void SetTransformImmediate(Matrix worldMatrix) mut
	{
		WorldMatrix = worldMatrix;
		PrevWorldMatrix = worldMatrix;
		WorldBounds = BoundsHelper.TransformBounds(AnimationBounds, worldMatrix);
	}

	public void SetLocalBounds(BoundingBox bounds) mut
	{
		LocalBounds = bounds;
		AnimationBounds = BoundsHelper.ExpandBounds(bounds, 1.2f);
		WorldBounds = BoundsHelper.TransformBounds(AnimationBounds, WorldMatrix);
	}

	public void SetAnimationBounds(BoundingBox bounds) mut
	{
		AnimationBounds = bounds;
		WorldBounds = BoundsHelper.TransformBounds(bounds, WorldMatrix);
	}

	public void MarkBonesDirty() mut { BonesDirty = true; }
	public void ClearBonesDirty() mut { BonesDirty = false; }

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
}

/// GPU-side bone transform data for a single skeleton instance.
[CRepr]
public struct BoneTransforms
{
	public Matrix[RenderConfig.MaxBonesPerMesh] BoneMatrices;
	public Matrix[RenderConfig.MaxBonesPerMesh] PrevBoneMatrices;

	public static uint64 GetSizeForBoneCount(int32 boneCount)
	{
		return (uint64)(boneCount * sizeof(Matrix) * 2);
	}
}
