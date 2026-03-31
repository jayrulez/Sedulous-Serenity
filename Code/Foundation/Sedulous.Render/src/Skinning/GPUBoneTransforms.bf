using System;
using Sedulous.Core.Mathematics;
namespace Sedulous.Render;

/// GPU bone transform buffer for a single skinned mesh.
[CRepr]
public struct GPUBoneTransforms
{
	/// Bone matrices in model space.
	public Matrix[RenderConfig.MaxBonesPerMesh] BoneMatrices;

	/// Size of the struct in bytes.
	public static int Size => RenderConfig.MaxBonesPerMesh * sizeof(Matrix);
}