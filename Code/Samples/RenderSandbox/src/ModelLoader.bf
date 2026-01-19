namespace RenderSandbox;

using System;
using System.IO;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Animation;
using Sedulous.Render;
using Sedulous.Geometry;

/// Result of loading a model.
public struct LoadedModel : IDisposable
{
	/// The loaded skeleton (null for static meshes).
	public Skeleton Skeleton;

	/// Animation clips extracted from the model.
	public AnimationClip[] Clips;

	/// The source Model data (for mesh/material access).
	public Model Model;

	/// The skin index used for this model (-1 if none).
	public int32 SkinIndex;

	/// Mapping from joint index (vertex weights) to bone index (in skeleton).
	/// This is needed because GLTF joints array may reference only a subset of nodes.
	public int32[] JointToBoneMap;

	public void Dispose() mut
	{
		delete Skeleton;
		DeleteContainerAndItems!(Clips);
		delete Model;
		delete JointToBoneMap;
	}
}

/// Utility for loading GLTF models and converting to animation format.
public static class ModelLoader
{
	/// Loads a GLTF model and converts skeleton/animations.
	/// @param path Path to the GLTF or GLB file.
	/// @param skinIndex Which skin to use for skeleton (0 for first skin, -1 for none).
	/// @returns Result containing the loaded model data, or error.
	public static Result<LoadedModel> Load(StringView path, int32 skinIndex = 0)
	{
		// Load GLTF
		let loader = scope GltfLoader();
		let model = new Model();

		let result = loader.Load(path, model);
		if (result != .Ok)
		{
			delete model;
			return .Err;
		}

		LoadedModel loaded = .();
		loaded.Model = model;
		loaded.SkinIndex = -1;

		// Extract skeleton from skin if available
		if (skinIndex >= 0 && skinIndex < model.Skins.Count)
		{
			loaded.SkinIndex = skinIndex;
			let skin = model.Skins[skinIndex];
			loaded.Skeleton = ConvertSkeleton(model, skin, out loaded.JointToBoneMap);
		}

		// Convert animations
		if (model.Animations.Count > 0 && loaded.Skeleton != null)
		{
			loaded.Clips = new AnimationClip[model.Animations.Count];
			for (int i = 0; i < model.Animations.Count; i++)
			{
				loaded.Clips[i] = ConvertAnimation(model.Animations[i], loaded.JointToBoneMap);
			}
		}
		else
		{
			loaded.Clips = new AnimationClip[0];
		}

		return .Ok(loaded);
	}

	/// Converts a ModelSkin to a Skeleton.
	/// @param model The source model.
	/// @param skin The skin to convert.
	/// @param jointToBoneMap Output mapping from joint index to bone index.
	/// @returns The created Skeleton.
	private static Skeleton ConvertSkeleton(Model model, ModelSkin skin, out int32[] jointToBoneMap)
	{
		let jointCount = (int32)skin.Joints.Count;
		let skeleton = new Skeleton(jointCount);
		jointToBoneMap = new int32[jointCount];

		// Create a mapping from model bone index to skeleton joint index
		Dictionary<int32, int32> boneToJoint = scope .();
		for (int32 j = 0; j < jointCount; j++)
		{
			let boneIndex = skin.Joints[j];
			boneToJoint[boneIndex] = j;
			jointToBoneMap[j] = boneIndex;
		}

		// Create skeleton bones from skin joints
		for (int32 j = 0; j < jointCount; j++)
		{
			let boneIndex = skin.Joints[j];
			let modelBone = model.Bones[boneIndex];
			let bone = skeleton.Bones[j];

			bone.Name.Set(modelBone.Name);
			bone.Index = j;

			// Map parent from model bone index to joint index
			if (modelBone.ParentIndex >= 0 && boneToJoint.TryGetValue(modelBone.ParentIndex, let parentJoint))
			{
				bone.ParentIndex = parentJoint;
			}
			else
			{
				bone.ParentIndex = -1; // Root or parent not in skin
			}

			// Set local bind pose from model bone's TRS
			bone.LocalBindPose = Transform(
				modelBone.Translation,
				modelBone.Rotation,
				modelBone.Scale
			);

			// Set inverse bind matrix from skin
			if (j < skin.InverseBindMatrices.Count)
			{
				bone.InverseBindPose = skin.InverseBindMatrices[j];
			}
		}

		// Build skeleton structure
		skeleton.BuildNameMap();
		skeleton.FindRootBones();
		skeleton.BuildChildIndices();

		return skeleton;
	}

	/// Converts a ModelAnimation to an AnimationClip.
	/// @param modelAnim The source animation.
	/// @param jointToBoneMap Mapping from joint index to bone index (for remapping targets).
	/// @returns The created AnimationClip.
	private static AnimationClip ConvertAnimation(ModelAnimation modelAnim, int32[] jointToBoneMap)
	{
		let clip = new AnimationClip(modelAnim.Name, modelAnim.Duration, false);

		// Build reverse mapping: bone index -> joint index
		Dictionary<int32, int32> boneToJoint = scope .();
		if (jointToBoneMap != null)
		{
			for (int32 j = 0; j < jointToBoneMap.Count; j++)
			{
				boneToJoint[jointToBoneMap[j]] = j;
			}
		}

		for (let channel in modelAnim.Channels)
		{
			// Map from bone index to joint index
			int32 jointIndex;
			if (!boneToJoint.TryGetValue(channel.TargetBone, out jointIndex))
			{
				// This bone is not part of the skin - skip
				continue;
			}

			let interpolation = ConvertInterpolation(channel.Interpolation);

			switch (channel.Path)
			{
			case .Translation:
				let track = clip.GetOrCreatePositionTrack(jointIndex);
				track.Interpolation = interpolation;
				for (let kf in channel.Keyframes)
				{
					track.AddKeyframe(kf.Time, Vector3(kf.Value.X, kf.Value.Y, kf.Value.Z));
				}

			case .Rotation:
				let track = clip.GetOrCreateRotationTrack(jointIndex);
				track.Interpolation = interpolation;
				for (let kf in channel.Keyframes)
				{
					track.AddKeyframe(kf.Time, Quaternion(kf.Value.X, kf.Value.Y, kf.Value.Z, kf.Value.W));
				}

			case .Scale:
				let track = clip.GetOrCreateScaleTrack(jointIndex);
				track.Interpolation = interpolation;
				for (let kf in channel.Keyframes)
				{
					track.AddKeyframe(kf.Time, Vector3(kf.Value.X, kf.Value.Y, kf.Value.Z));
				}

			case .Weights:
				// Morph target weights not yet supported
				continue;
			}
		}

		clip.SortAllKeyframes();
		clip.ComputeDuration();

		return clip;
	}

	/// Converts Models interpolation mode to Animation interpolation mode.
	private static InterpolationMode ConvertInterpolation(AnimationInterpolation interp)
	{
		switch (interp)
		{
		case .Step: return .Step;
		case .Linear: return .Linear;
		case .CubicSpline: return .CubicSpline;
		}
	}

	/// Helper to find which mesh node uses a specific skin.
	/// @param model The model to search.
	/// @param skinIndex The skin index to find.
	/// @returns The bone index of the mesh node, or -1 if not found.
	public static int32 FindSkinnedMeshNode(Model model, int32 skinIndex)
	{
		for (let bone in model.Bones)
		{
			if (bone.SkinIndex == skinIndex)
				return bone.Index;
		}
		return -1;
	}

	/// Gets the mesh index for a skinned mesh node.
	/// @param model The model.
	/// @param skinIndex The skin index.
	/// @returns The mesh index, or -1 if not found.
	public static int32 GetSkinnedMeshIndex(Model model, int32 skinIndex)
	{
		let nodeIndex = FindSkinnedMeshNode(model, skinIndex);
		if (nodeIndex >= 0)
			return model.Bones[nodeIndex].MeshIndex;
		return -1;
	}

	/// Converts a ModelMesh to a SkinnedMesh for GPU upload.
	/// @param modelMesh The source model mesh.
	/// @returns The created SkinnedMesh, or null if conversion fails.
	public static SkinnedMesh ConvertToSkinnedMesh(ModelMesh modelMesh)
	{
		if (modelMesh == null)
			return null;

		// Find vertex element offsets
		int32 posOffset = -1, normalOffset = -1, uvOffset = -1;
		int32 colorOffset = -1, tangentOffset = -1;
		int32 jointsOffset = -1, weightsOffset = -1;

		for (let element in modelMesh.VertexElements)
		{
			switch (element.Semantic)
			{
			case .Position: posOffset = element.Offset;
			case .Normal: normalOffset = element.Offset;
			case .TexCoord: uvOffset = element.Offset;
			case .Color: colorOffset = element.Offset;
			case .Tangent: tangentOffset = element.Offset;
			case .Joints: jointsOffset = element.Offset;
			case .Weights: weightsOffset = element.Offset;
			default:
			}
		}

		if (posOffset < 0)
			return null; // Need at least positions

		let skinnedMesh = new SkinnedMesh();
		let vertexCount = modelMesh.VertexCount;
		let stride = modelMesh.VertexStride;
		let vertexData = modelMesh.GetVertexData();

		skinnedMesh.ResizeVertices(vertexCount);

		for (int32 i = 0; i < vertexCount; i++)
		{
			uint8* v = vertexData + i * stride;
			SkinnedVertex vertex = .();

			// Position
			vertex.Position = *(Vector3*)(v + posOffset);

			// Normal
			if (normalOffset >= 0)
				vertex.Normal = *(Vector3*)(v + normalOffset);
			else
				vertex.Normal = .(0, 1, 0);

			// TexCoord
			if (uvOffset >= 0)
				vertex.TexCoord = *(Vector2*)(v + uvOffset);

			// Color
			if (colorOffset >= 0)
				vertex.Color = *(uint32*)(v + colorOffset);
			else
				vertex.Color = 0xFFFFFFFF;

			// Tangent
			if (tangentOffset >= 0)
				vertex.Tangent = *(Vector3*)(v + tangentOffset);
			else
				vertex.Tangent = .(1, 0, 0);

			// Joints
			if (jointsOffset >= 0)
				vertex.Joints = *(uint16[4]*)(v + jointsOffset);

			// Weights
			if (weightsOffset >= 0)
				vertex.Weights = *(Vector4*)(v + weightsOffset);
			else
				vertex.Weights = .(1, 0, 0, 0);

			skinnedMesh.SetVertex(i, vertex);
		}

		// Copy indices (if any)
		let indexCount = modelMesh.IndexCount;
		if (indexCount > 0)
		{
			skinnedMesh.ReserveIndices(indexCount);
			let indexData = modelMesh.GetIndexData();
			let use32Bit = modelMesh.Use32BitIndices;

			for (int32 i = 0; i < indexCount; i++)
			{
				uint32 idx;
				if (use32Bit)
					idx = ((uint32*)indexData)[i];
				else
					idx = ((uint16*)indexData)[i];
				skinnedMesh.AddIndex(idx);
			}

			// Copy submeshes with index info
			for (let part in modelMesh.Parts)
			{
				skinnedMesh.AddSubMesh(.(part.IndexStart, part.IndexCount, part.MaterialIndex));
			}
		}
		else
		{
			// Non-indexed mesh - create submesh based on vertex count
			if (modelMesh.Parts.Count > 0)
			{
				for (let part in modelMesh.Parts)
				{
					// For non-indexed meshes, IndexStart/IndexCount refer to vertex ranges
					skinnedMesh.AddSubMesh(.(part.IndexStart, part.IndexCount, part.MaterialIndex));
				}
			}
			else
			{
				// Single submesh covering all vertices
				skinnedMesh.AddSubMesh(.(0, vertexCount, 0));
			}
		}

		skinnedMesh.CalculateBounds();

		return skinnedMesh;
	}
}
