using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Geometry;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Mathematics;
using Sedulous.Animation;

using static Sedulous.Mathematics.MathSerializerExtensions;

namespace Sedulous.Animation.Resources;

/// CPU-side skeleton resource for skeletal animation.
/// Can be shared between multiple SkinnedMeshResources.
class SkeletonResource : Resource
{
	public const int32 FileVersion = 2; // Bumped for new animation format
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
					let bone = mSkeleton.Bones[i];
					if (bone == null)
						continue;

					s.BeginObject(scope $"bone{i}");

					String boneName = scope String(bone.Name);
					s.String("name", boneName);

					int32 parentIndex = bone.ParentIndex;
					s.Int32("parentIndex", ref parentIndex);

					Matrix inverseBindMatrix = bone.InverseBindPose;
					s.Matrix4x4("inverseBindMatrix", ref inverseBindMatrix);

					Vector3 bindTranslation = bone.LocalBindPose.Position;
					s.Vector3("bindTranslation", ref bindTranslation);

					Quaternion bindRotation = bone.LocalBindPose.Rotation;
					s.Quaternion("bindRotation", ref bindRotation);

					Vector3 bindScale = bone.LocalBindPose.Scale;
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

					// Set up the bone using the new API
					let bone = skeleton.Bones[i];
					bone.Name.Set(boneName);
					bone.Index = i;
					bone.ParentIndex = parentIdx;
					bone.InverseBindPose = inverseBindMatrix;
					bone.LocalBindPose = Transform(bindTranslation, bindRotation, bindScale);

					s.EndObject();
				}

				s.EndObject();
			}

			// Build skeleton hierarchy
			skeleton.BuildNameMap();
			skeleton.FindRootBones();
			skeleton.BuildChildIndices();

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
