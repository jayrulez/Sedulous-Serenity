using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Geometry;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Mathematics;

using static Sedulous.Mathematics.MathSerializerExtensions;

namespace Sedulous.Framework.Renderer;

/// CPU-side skeleton resource for skeletal animation.
/// Can be shared between multiple SkinnedMeshResources.
class SkeletonResource : Resource
{
	public const int32 FileVersion = 1;
	public const int32 FileType = 3; // ResourceFileType.Skeleton

	private Skeleton mSkeleton;
	private bool mOwnsSkeleton;

	/// The underlying skeleton data.
	public Skeleton Skeleton => mSkeleton;

	/// Number of bones in the skeleton.
	public int32 BoneCount => mSkeleton?.BoneCount ?? 0;

	public this()
	{
		mSkeleton = null;
		mOwnsSkeleton = false;
	}

	public this(Skeleton skeleton, bool ownsSkeleton = false)
	{
		mSkeleton = skeleton;
		mOwnsSkeleton = ownsSkeleton;
	}

	public ~this()
	{
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
	}

	/// Sets the skeleton. Takes ownership if ownsSkeleton is true.
	public void SetSkeleton(Skeleton skeleton, bool ownsSkeleton = false)
	{
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
		mSkeleton = skeleton;
		mOwnsSkeleton = ownsSkeleton;
	}

	/// Create an AnimationPlayer for this skeleton.
	public AnimationPlayer CreatePlayer()
	{
		if (mSkeleton == null)
			return null;
		return new AnimationPlayer(mSkeleton);
	}

	// ---- Serialization ----

	public override int32 SerializationVersion => FileVersion;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		if (s.IsWriting)
		{
			if (mSkeleton == null)
				return .InvalidData;

			int32 boneCount = mSkeleton.BoneCount;
			s.Int32("boneCount", ref boneCount);

			if (boneCount > 0)
			{
				s.BeginObject("bones");

				for (int32 i = 0; i < boneCount; i++)
				{
					int32 parentIndex = 0;
					Matrix localTransform = .Identity;
					Matrix inverseBindMatrix = .Identity;
					mSkeleton.GetBoneData(i, out parentIndex, out localTransform, out inverseBindMatrix);

					Vector3 bindTranslation = .Zero;
					Quaternion bindRotation = .Identity;
					Vector3 bindScale = .(1, 1, 1);
					mSkeleton.GetBindPose(i, out bindTranslation, out bindRotation, out bindScale);

					s.BeginObject(scope $"bone{i}");

					String boneName = scope String(mSkeleton.GetBoneName(i));
					s.String("name", boneName);

					s.Int32("parentIndex", ref parentIndex);
					s.Matrix4x4("inverseBindMatrix", ref inverseBindMatrix);
					s.Vector3("bindTranslation", ref bindTranslation);
					s.Quaternion("bindRotation", ref bindRotation);
					s.Vector3("bindScale", ref bindScale);

					s.EndObject();
				}

				s.EndObject();
			}
		}
		else
		{
			int32 boneCount = 0;
			s.Int32("boneCount", ref boneCount);

			let skeleton = new Skeleton(boneCount);

			if (boneCount > 0)
			{
				s.BeginObject("bones");

				for (int32 i = 0; i < boneCount; i++)
				{
					s.BeginObject(scope $"bone{i}");

					String boneName = scope String();
					s.String("name", boneName);

					int32 parentIdx = -1;
					s.Int32("parentIndex", ref parentIdx);

					Matrix inverseBindMatrix = .Identity;
					s.Matrix4x4("inverseBindMatrix", ref inverseBindMatrix);

					Vector3 bindTranslation = .Zero;
					s.Vector3("bindTranslation", ref bindTranslation);

					Quaternion bindRotation = .Identity;
					s.Quaternion("bindRotation", ref bindRotation);

					Vector3 bindScale = .(1, 1, 1);
					s.Vector3("bindScale", ref bindScale);

					skeleton.SetBone(i, boneName, parentIdx, bindTranslation, bindRotation, bindScale, inverseBindMatrix);

					s.EndObject();
				}

				s.EndObject();
			}

			SetSkeleton(skeleton, true);
		}

		return .Ok;
	}

	/// Save this skeleton resource to a file.
	public Result<void> SaveToFile(StringView path)
	{
		if (mSkeleton == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = FileVersion;
		writer.Int32("version", ref version);

		int32 fileType = FileType;
		writer.Int32("type", ref fileType);

		Serialize(writer);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load a skeleton resource from a file.
	public static Result<SkeletonResource> LoadFromFile(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > FileVersion)
			return .Err;

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != FileType)
			return .Err;

		let resource = new SkeletonResource();
		resource.Serialize(reader);

		return .Ok(resource);
	}
}
