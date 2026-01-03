namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Runtime bone data for skeletal animation.
struct Bone
{
	/// Index of parent bone (-1 if root).
	public int32 ParentIndex;

	/// Local transform relative to parent.
	public Matrix4x4 LocalTransform;

	/// Inverse bind matrix (transforms from mesh space to bone local space).
	public Matrix4x4 InverseBindMatrix;

	/// Current world transform (computed during animation update).
	public Matrix4x4 WorldTransform;

	/// Final skinning matrix = WorldTransform * InverseBindMatrix.
	public Matrix4x4 SkinningMatrix;

	public this()
	{
		ParentIndex = -1;
		LocalTransform = .Identity;
		InverseBindMatrix = .Identity;
		WorldTransform = .Identity;
		SkinningMatrix = .Identity;
	}
}

/// Runtime skeleton for skeletal animation.
/// Manages bone hierarchy and computes skinning matrices.
class Skeleton
{
	private Bone[] mBones ~ delete _;
	private String[] mBoneNames ~ DeleteContainerAndItems!(_);

	/// Number of bones in the skeleton.
	public int32 BoneCount => (int32)(mBones?.Count ?? 0);

	/// Access bone data.
	public Bone[] Bones => mBones;

	/// Maximum bones supported in shader (must match shader constant).
	public const int32 MAX_BONES = 128;

	public this(int32 boneCount)
	{
		mBones = new Bone[boneCount];
		mBoneNames = new String[boneCount];

		for (int32 i = 0; i < boneCount; i++)
		{
			mBones[i] = .();
			mBoneNames[i] = new String();
		}
	}

	/// Sets bone data.
	public void SetBone(int32 index, StringView name, int32 parentIndex, Matrix4x4 localTransform, Matrix4x4 inverseBindMatrix)
	{
		if (index < 0 || index >= mBones.Count)
			return;

		mBoneNames[index].Set(name);
		mBones[index].ParentIndex = parentIndex;
		mBones[index].LocalTransform = localTransform;
		mBones[index].InverseBindMatrix = inverseBindMatrix;
	}

	/// Finds a bone index by name. Returns -1 if not found.
	public int32 FindBone(StringView name)
	{
		for (int32 i = 0; i < mBoneNames.Count; i++)
		{
			if (mBoneNames[i] == name)
				return i;
		}
		return -1;
	}

	/// Updates world transforms and skinning matrices from current local transforms.
	/// Call this after animation has updated local transforms.
	public void UpdateMatrices()
	{
		// Process bones in order (assumes parents come before children)
		for (int32 i = 0; i < mBones.Count; i++)
		{
			ref Bone bone = ref mBones[i];

			if (bone.ParentIndex >= 0 && bone.ParentIndex < mBones.Count)
			{
				// Child bone: world = parent.world * local
				bone.WorldTransform = mBones[bone.ParentIndex].WorldTransform * bone.LocalTransform;
			}
			else
			{
				// Root bone: world = local
				bone.WorldTransform = bone.LocalTransform;
			}

			// Compute final skinning matrix
			bone.SkinningMatrix = bone.WorldTransform * bone.InverseBindMatrix;
		}
	}

	/// Updates a bone's local transform from TRS components.
	public void SetBoneTransform(int32 index, Vector3 translation, Quaternion rotation, Vector3 scale)
	{
		if (index < 0 || index >= mBones.Count)
			return;

		let t = Matrix4x4.CreateTranslation(translation);
		let r = Matrix4x4.CreateFromQuaternion(rotation);
		let s = Matrix4x4.CreateScale(scale);

		// TRS order: Scale -> Rotate -> Translate
		mBones[index].LocalTransform = t * r * s;
	}

	/// Gets the skinning matrices for upload to GPU.
	/// Returns a span of Matrix4x4 that can be uploaded to a uniform/storage buffer.
	public Span<Matrix4x4> GetSkinningMatrices()
	{
		if (mBones == null || mBones.Count == 0)
			return default;

		// Return pointer to first skinning matrix
		// Note: SkinningMatrix is at offset in Bone struct, so we need to copy
		return default; // Caller should iterate and copy
	}

	/// Copies skinning matrices to a destination buffer.
	public void CopySkinningMatrices(Matrix4x4* dest, int32 maxCount)
	{
		int32 count = Math.Min((int32)mBones.Count, maxCount);
		for (int32 i = 0; i < count; i++)
		{
			dest[i] = mBones[i].SkinningMatrix;
		}

		// Zero remaining matrices
		for (int32 i = count; i < maxCount; i++)
		{
			dest[i] = .Identity;
		}
	}
}
