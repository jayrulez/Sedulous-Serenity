using System;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Mathematics;
using Sedulous.Framework.Renderer;

using static Sedulous.Mathematics.MathSerializerExtensions;

namespace Sedulous.Geometry.Tooling;

/// Serialization helper for Skeleton data.
static class SkeletonSerializer
{
	/// Serialize a Skeleton to a serializer.
	public static SerializationResult Serialize(Serializer s, StringView name, Skeleton skeleton)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return result;

		if (s.IsWriting)
		{
			int32 boneCount = skeleton.BoneCount;
			result = s.Int32("boneCount", ref boneCount);
			if (result != .Ok) { s.EndObject(); return result; }

			if (boneCount > 0)
			{
				result = s.BeginObject("bones");
				if (result != .Ok) { s.EndObject(); return result; }

				for (int32 i = 0; i < boneCount; i++)
				{
					int32 parentIndex = 0;
					Matrix localTransform = .Identity;
					Matrix inverseBindMatrix = .Identity;
					skeleton.GetBoneData(i, out parentIndex, out localTransform, out inverseBindMatrix);

					Vector3 bindTranslation = .Zero;
					Quaternion bindRotation = .Identity;
					Vector3 bindScale = .(1, 1, 1);
					skeleton.GetBindPose(i, out bindTranslation, out bindRotation, out bindScale);

					s.BeginObject(scope $"bone{i}");

					String boneName = scope String(skeleton.GetBoneName(i));
					s.String("name", boneName);

					s.Int32("parentIndex", ref parentIndex);

					// Write inverse bind matrix
					s.Matrix4x4("inverseBindMatrix", ref inverseBindMatrix);

					// Write bind pose TRS (critical for animation)
					s.Vector3("bindTranslation", ref bindTranslation);
					s.Quaternion("bindRotation", ref bindRotation);
					s.Vector3("bindScale", ref bindScale);

					s.EndObject();
				}

				s.EndObject();
			}
		}

		s.EndObject();
		return .Ok;
	}

	/// Deserialize a Skeleton from a serializer.
	public static Result<Skeleton> Deserialize(Serializer s, StringView name)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return .Err;

		int32 boneCount = 0;
		result = s.Int32("boneCount", ref boneCount);
		if (result != .Ok) { s.EndObject(); return .Err; }

		let skeleton = new Skeleton(boneCount);

		if (boneCount > 0)
		{
			result = s.BeginObject("bones");
			if (result != .Ok) { delete skeleton; s.EndObject(); return .Err; }

			for (int32 i = 0; i < boneCount; i++)
			{
				result = s.BeginObject(scope $"bone{i}");
				if (result != .Ok) break;

				String boneName = scope String();
				s.String("name", boneName);

				int32 parentIdx = -1;
				s.Int32("parentIndex", ref parentIdx);

				Matrix inverseBindMatrix = .Identity;
				s.Matrix4x4("inverseBindMatrix", ref inverseBindMatrix);

				// Read bind pose TRS (critical for animation)
				Vector3 bindTranslation = .Zero;
				s.Vector3("bindTranslation", ref bindTranslation);

				Quaternion bindRotation = .Identity;
				s.Quaternion("bindRotation", ref bindRotation);

				Vector3 bindScale = .(1, 1, 1);
				s.Vector3("bindScale", ref bindScale);

				// Use TRS overload to properly set bind pose for animation
				skeleton.SetBone(i, boneName, parentIdx, bindTranslation, bindRotation, bindScale, inverseBindMatrix);

				s.EndObject();
			}

			s.EndObject();
		}

		s.EndObject();
		return .Ok(skeleton);
	}
}
