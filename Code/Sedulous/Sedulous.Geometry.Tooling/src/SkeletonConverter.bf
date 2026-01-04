using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Models;
using Sedulous.Framework.Renderer;

namespace Sedulous.Geometry.Tooling;

/// Converts Model bone/skin data to runtime Skeleton format.
static class SkeletonConverter
{
	/// Creates a Skeleton from a Model's skin and bones.
	/// The skeleton is ordered by skin joint index so that bone indices match vertex joint indices.
	public static Skeleton CreateFromSkin(Model model, ModelSkin skin)
	{
		if (model == null || skin == null || skin.Joints.Count == 0)
			return null;

		let skeleton = new Skeleton((int32)skin.Joints.Count);

		// Build node-to-skinJoint mapping for parent index remapping
		var nodeToSkinJoint = scope int32[model.Bones.Count];
		for (int i = 0; i < nodeToSkinJoint.Count; i++)
			nodeToSkinJoint[i] = -1;

		for (int32 skinJointIdx = 0; skinJointIdx < skin.Joints.Count; skinJointIdx++)
		{
			let nodeIdx = skin.Joints[skinJointIdx];
			if (nodeIdx >= 0 && nodeIdx < nodeToSkinJoint.Count)
				nodeToSkinJoint[nodeIdx] = skinJointIdx;
		}

		// Create skeleton bones ordered by skin joint index
		for (int32 skinJointIdx = 0; skinJointIdx < skin.Joints.Count; skinJointIdx++)
		{
			let nodeIdx = skin.Joints[skinJointIdx];
			if (nodeIdx < 0 || nodeIdx >= model.Bones.Count)
				continue;

			let modelBone = model.Bones[nodeIdx];

			// Remap parent index from node index to skin joint index
			int32 parentSkinJointIdx = -1;
			if (modelBone.ParentIndex >= 0 && modelBone.ParentIndex < nodeToSkinJoint.Count)
				parentSkinJointIdx = nodeToSkinJoint[modelBone.ParentIndex];

			// Use inverse bind matrix from skin (more reliable than bone's copy)
			let ibm = (skinJointIdx < skin.InverseBindMatrices.Count)
				? skin.InverseBindMatrices[skinJointIdx]
				: Matrix4x4.Identity;

			skeleton.SetBone(
				skinJointIdx,
				modelBone.Name,
				parentSkinJointIdx,
				modelBone.Translation,
				modelBone.Rotation,
				modelBone.Scale,
				ibm
			);
		}

		return skeleton;
	}

	/// Creates a node-to-bone mapping from a skin.
	/// This maps node indices to skeleton bone indices for animation channel remapping.
	/// Caller owns the returned array.
	public static int32[] CreateNodeToBoneMapping(Model model, ModelSkin skin)
	{
		if (model == null || skin == null)
			return null;

		let mapping = new int32[model.Bones.Count];
		for (int i = 0; i < mapping.Count; i++)
			mapping[i] = -1;

		for (int32 skinJointIdx = 0; skinJointIdx < skin.Joints.Count; skinJointIdx++)
		{
			let nodeIdx = skin.Joints[skinJointIdx];
			if (nodeIdx >= 0 && nodeIdx < mapping.Count)
				mapping[nodeIdx] = skinJointIdx;
		}

		return mapping;
	}
}
