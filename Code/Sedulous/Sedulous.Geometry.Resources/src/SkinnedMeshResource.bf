using System;
using System.IO;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Geometry;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Mathematics;
using Sedulous.Animation;
using Sedulous.Animation.Resources;

using static Sedulous.Mathematics.MathSerializerExtensions;

namespace Sedulous.Geometry.Resources;

/// CPU-side skinned mesh resource wrapping a SkinnedMesh.
/// Contains the mesh data plus skeleton and animations for complete skeletal animation support.
class SkinnedMeshResource : Resource
{
	public const int32 FileVersion = 2; // Bumped for new animation format
	public const int32 FileType = 2; // ResourceFileType.SkinnedMesh
	public const int32 BundleFileType = 7; // ResourceFileType.SkinnedMeshBundle

	private SkinnedMesh mMesh;
	private bool mOwnsMesh;
	private Skeleton mSkeleton;
	private bool mOwnsSkeleton;
	private SkeletonResource mSkeletonResource;  // Optional shared skeleton
	private List<AnimationClip> mAnimations ~ if (mOwnsAnimations) DeleteContainerAndItems!(_);
	private bool mOwnsAnimations;

	/// The underlying skinned mesh data.
	public SkinnedMesh Mesh => mMesh;

	/// The skeleton for bone transforms.
	/// Returns from shared SkeletonResource if set, otherwise local skeleton.
	public Skeleton Skeleton => mSkeletonResource?.Skeleton ?? mSkeleton;

	/// The shared skeleton resource, if any.
	public SkeletonResource SkeletonResource => mSkeletonResource;

	/// Available animations.
	public List<AnimationClip> Animations => mAnimations;

	public this()
	{
		mMesh = null;
		mOwnsMesh = false;
	}

	public this(SkinnedMesh mesh, bool ownsMesh = false)
	{
		mMesh = mesh;
		mOwnsMesh = ownsMesh;
	}

	public ~this()
	{
		if (mOwnsMesh && mMesh != null)
			delete mMesh;
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
		if (mSkeletonResource != null)
			mSkeletonResource.ReleaseRef();
	}

	/// Sets a local skeleton. Takes ownership if ownsSkeleton is true.
	/// Clears any shared skeleton resource.
	public void SetSkeleton(Skeleton skeleton, bool ownsSkeleton = false)
	{
		// Clear shared skeleton
		if (mSkeletonResource != null)
		{
			mSkeletonResource.ReleaseRef();
			mSkeletonResource = null;
		}
		// Clear local skeleton
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
		mSkeleton = skeleton;
		mOwnsSkeleton = ownsSkeleton;
	}

	/// Sets a shared skeleton resource. Adds a reference to it.
	/// Clears any local skeleton.
	public void SetSkeletonResource(SkeletonResource skeletonResource)
	{
		// Clear local skeleton
		if (mOwnsSkeleton && mSkeleton != null)
			delete mSkeleton;
		mSkeleton = null;
		mOwnsSkeleton = false;

		// Clear old shared skeleton
		if (mSkeletonResource != null)
			mSkeletonResource.ReleaseRef();

		// Set new shared skeleton
		mSkeletonResource = skeletonResource;
		if (mSkeletonResource != null)
			mSkeletonResource.AddRef();
	}

	/// Sets the animations. Takes ownership if ownsAnimations is true.
	public void SetAnimations(List<AnimationClip> animations, bool ownsAnimations = false)
	{
		if (mOwnsAnimations && mAnimations != null)
			DeleteContainerAndItems!(mAnimations);
		mAnimations = animations;
		mOwnsAnimations = ownsAnimations;
	}

	/// Gets an animation by name, or null if not found.
	public AnimationClip GetAnimation(StringView name)
	{
		if (mAnimations == null)
			return null;

		for (let clip in mAnimations)
		{
			if (clip.Name == name)
				return clip;
		}
		return null;
	}

	/// Gets the number of animations.
	public int AnimationCount => mAnimations?.Count ?? 0;

	/// Creates an AnimationPlayer for this resource.
	/// Caller owns the returned player.
	public AnimationPlayer CreatePlayer()
	{
		let skeleton = Skeleton;
		if (skeleton == null)
			return null;
		return new AnimationPlayer(skeleton);
	}

	// ---- Serialization ----

	public override int32 SerializationVersion => FileVersion;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		if (s.IsWriting)
		{
			if (mMesh == null)
				return .InvalidData;

			// Serialize mesh
			SerializeMesh(s);

			// Serialize skeleton if present
			let skeleton = Skeleton;
			bool hasSkeleton = skeleton != null;
			s.Bool("hasSkeleton", ref hasSkeleton);
			if (hasSkeleton)
				SerializeSkeleton(s, skeleton);

			// Serialize animations
			int32 animCount = (int32)(mAnimations?.Count ?? 0);
			s.Int32("animationCount", ref animCount);
			if (animCount > 0)
				SerializeAnimations(s, mAnimations);
		}
		else
		{
			// Deserialize mesh
			DeserializeMesh(s);

			// Deserialize skeleton
			bool hasSkeleton = false;
			s.Bool("hasSkeleton", ref hasSkeleton);
			if (hasSkeleton)
			{
				let skeleton = DeserializeSkeleton(s);
				if (skeleton != null)
					SetSkeleton(skeleton, true);
			}

			// Deserialize animations
			int32 animCount = 0;
			s.Int32("animationCount", ref animCount);
			if (animCount > 0)
			{
				let anims = DeserializeAnimations(s, animCount);
				if (anims != null)
					SetAnimations(anims, true);
			}
		}

		return .Ok;
	}

	private void SerializeMesh(Serializer s)
	{
		s.BeginObject("mesh");

		int32 vertexCount = mMesh.VertexCount;
		s.Int32("vertexCount", ref vertexCount);

		if (vertexCount > 0)
		{
			s.BeginObject("vertices");

			let positions = scope List<float>();
			let normals = scope List<float>();
			let uvs = scope List<float>();
			let colors = scope List<int32>();
			let tangents = scope List<float>();
			let joints = scope List<int32>();
			let weights = scope List<float>();

			for (int32 i = 0; i < vertexCount; i++)
			{
				let v = mMesh.GetVertex(i);
				positions.Add(v.Position.X); positions.Add(v.Position.Y); positions.Add(v.Position.Z);
				normals.Add(v.Normal.X); normals.Add(v.Normal.Y); normals.Add(v.Normal.Z);
				uvs.Add(v.TexCoord.X); uvs.Add(v.TexCoord.Y);
				colors.Add((int32)v.Color);
				tangents.Add(v.Tangent.X); tangents.Add(v.Tangent.Y); tangents.Add(v.Tangent.Z);
				joints.Add((int32)v.Joints[0]); joints.Add((int32)v.Joints[1]);
				joints.Add((int32)v.Joints[2]); joints.Add((int32)v.Joints[3]);
				weights.Add(v.Weights.X); weights.Add(v.Weights.Y);
				weights.Add(v.Weights.Z); weights.Add(v.Weights.W);
			}

			s.ArrayFloat("positions", positions);
			s.ArrayFloat("normals", normals);
			s.ArrayFloat("uvs", uvs);
			s.ArrayInt32("colors", colors);
			s.ArrayFloat("tangents", tangents);
			s.ArrayInt32("joints", joints);
			s.ArrayFloat("weights", weights);

			s.EndObject();
		}

		// Write indices
		int32 indexCount = mMesh.IndexCount;
		s.Int32("indexCount", ref indexCount);

		if (indexCount > 0)
		{
			let indices = scope List<int32>();
			for (int32 i = 0; i < indexCount; i++)
				indices.Add((int32)mMesh.Indices.GetIndex(i));
			s.ArrayInt32("indices", indices);
		}

		// Write submeshes
		int32 submeshCount = (int32)mMesh.SubMeshes.Count;
		s.Int32("submeshCount", ref submeshCount);

		if (submeshCount > 0)
		{
			s.BeginObject("submeshes");

			for (int32 i = 0; i < submeshCount; i++)
			{
				let sm = mMesh.SubMeshes[i];
				s.BeginObject(scope $"sm{i}");

				int32 startIndex = sm.startIndex;
				int32 indexCnt = sm.indexCount;
				int32 materialIndex = sm.materialIndex;

				s.Int32("startIndex", ref startIndex);
				s.Int32("indexCount", ref indexCnt);
				s.Int32("materialIndex", ref materialIndex);

				s.EndObject();
			}

			s.EndObject();
		}

		s.EndObject();
	}

	private void DeserializeMesh(Serializer s)
	{
		s.BeginObject("mesh");

		let mesh = new SkinnedMesh();

		int32 vertexCount = 0;
		s.Int32("vertexCount", ref vertexCount);

		if (vertexCount > 0)
		{
			mesh.ResizeVertices(vertexCount);

			s.BeginObject("vertices");

			let positions = scope List<float>();
			let normals = scope List<float>();
			let uvs = scope List<float>();
			let colors = scope List<int32>();
			let tangents = scope List<float>();
			let joints = scope List<int32>();
			let weights = scope List<float>();

			s.ArrayFloat("positions", positions);
			s.ArrayFloat("normals", normals);
			s.ArrayFloat("uvs", uvs);
			s.ArrayInt32("colors", colors);
			s.ArrayFloat("tangents", tangents);
			s.ArrayInt32("joints", joints);
			s.ArrayFloat("weights", weights);

			for (int32 i = 0; i < vertexCount; i++)
			{
				SkinnedVertex v = .();
				if (i * 3 + 2 < positions.Count)
					v.Position = .(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2]);
				if (i * 3 + 2 < normals.Count)
					v.Normal = .(normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2]);
				if (i * 2 + 1 < uvs.Count)
					v.TexCoord = .(uvs[i * 2], uvs[i * 2 + 1]);
				if (i < colors.Count)
					v.Color = (uint32)colors[i];
				if (i * 3 + 2 < tangents.Count)
					v.Tangent = .(tangents[i * 3], tangents[i * 3 + 1], tangents[i * 3 + 2]);
				if (i * 4 + 3 < joints.Count)
					v.Joints = .((uint16)joints[i * 4], (uint16)joints[i * 4 + 1],
						(uint16)joints[i * 4 + 2], (uint16)joints[i * 4 + 3]);
				if (i * 4 + 3 < weights.Count)
					v.Weights = .(weights[i * 4], weights[i * 4 + 1],
						weights[i * 4 + 2], weights[i * 4 + 3]);
				mesh.SetVertex(i, v);
			}

			s.EndObject();
		}

		// Read indices
		int32 indexCount = 0;
		s.Int32("indexCount", ref indexCount);

		if (indexCount > 0)
		{
			mesh.ReserveIndices(indexCount);
			let indices = scope List<int32>();
			s.ArrayInt32("indices", indices);
			for (int32 i = 0; i < Math.Min(indexCount, (int32)indices.Count); i++)
				mesh.AddIndex((uint32)indices[i]);
		}

		// Read submeshes
		int32 submeshCount = 0;
		s.Int32("submeshCount", ref submeshCount);

		if (submeshCount > 0)
		{
			s.BeginObject("submeshes");

			for (int32 i = 0; i < submeshCount; i++)
			{
				s.BeginObject(scope $"sm{i}");

				int32 startIndex = 0, idxCount = 0, materialIndex = 0;
				s.Int32("startIndex", ref startIndex);
				s.Int32("indexCount", ref idxCount);
				s.Int32("materialIndex", ref materialIndex);

				mesh.AddSubMesh(SubMesh(startIndex, idxCount, materialIndex));
				s.EndObject();
			}

			s.EndObject();
		}

		mesh.CalculateBounds();
		s.EndObject();

		// Set the mesh
		if (mOwnsMesh && mMesh != null)
			delete mMesh;
		mMesh = mesh;
		mOwnsMesh = true;
	}

	private void SerializeSkeleton(Serializer s, Skeleton skeleton)
	{
		s.BeginObject("skeleton");

		int32 boneCount = skeleton.BoneCount;
		s.Int32("boneCount", ref boneCount);

		if (boneCount > 0)
		{
			s.BeginObject("bones");

			for (int32 i = 0; i < boneCount; i++)
			{
				let bone = skeleton.Bones[i];
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

		s.EndObject();
	}

	private Skeleton DeserializeSkeleton(Serializer s)
	{
		s.BeginObject("skeleton");

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

		s.EndObject();
		return skeleton;
	}

	private void SerializeAnimations(Serializer s, List<AnimationClip> animations)
	{
		s.BeginObject("animations");

		int32 count = (int32)animations.Count;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			let clip = animations[i];
			s.BeginObject(scope $"clip{i}");

			String clipName = scope String(clip.Name);
			s.String("name", clipName);

			float duration = clip.Duration;
			s.Float("duration", ref duration);

			bool isLooping = clip.IsLooping;
			s.Bool("isLooping", ref isLooping);

			// Serialize position tracks
			int32 posTrackCount = (int32)clip.PositionTracks.Count;
			s.Int32("positionTrackCount", ref posTrackCount);
			for (int32 t = 0; t < posTrackCount; t++)
			{
				let track = clip.PositionTracks[t];
				s.BeginObject(scope $"posTrack{t}");

				int32 boneIndex = track.BoneIndex;
				s.Int32("boneIndex", ref boneIndex);

				int32 interpInt = (int32)track.Interpolation;
				s.Int32("interpolation", ref interpInt);

				int32 keyframeCount = (int32)track.Keyframes.Count;
				s.Int32("keyframeCount", ref keyframeCount);

				if (keyframeCount > 0)
				{
					let times = scope List<float>();
					let values = scope List<float>();
					for (let kf in track.Keyframes)
					{
						times.Add(kf.Time);
						values.Add(kf.Value.X);
						values.Add(kf.Value.Y);
						values.Add(kf.Value.Z);
					}
					s.ArrayFloat("times", times);
					s.ArrayFloat("values", values);
				}

				s.EndObject();
			}

			// Serialize rotation tracks
			int32 rotTrackCount = (int32)clip.RotationTracks.Count;
			s.Int32("rotationTrackCount", ref rotTrackCount);
			for (int32 t = 0; t < rotTrackCount; t++)
			{
				let track = clip.RotationTracks[t];
				s.BeginObject(scope $"rotTrack{t}");

				int32 boneIndex = track.BoneIndex;
				s.Int32("boneIndex", ref boneIndex);

				int32 interpInt = (int32)track.Interpolation;
				s.Int32("interpolation", ref interpInt);

				int32 keyframeCount = (int32)track.Keyframes.Count;
				s.Int32("keyframeCount", ref keyframeCount);

				if (keyframeCount > 0)
				{
					let times = scope List<float>();
					let values = scope List<float>();
					for (let kf in track.Keyframes)
					{
						times.Add(kf.Time);
						values.Add(kf.Value.X);
						values.Add(kf.Value.Y);
						values.Add(kf.Value.Z);
						values.Add(kf.Value.W);
					}
					s.ArrayFloat("times", times);
					s.ArrayFloat("values", values);
				}

				s.EndObject();
			}

			// Serialize scale tracks
			int32 scaleTrackCount = (int32)clip.ScaleTracks.Count;
			s.Int32("scaleTrackCount", ref scaleTrackCount);
			for (int32 t = 0; t < scaleTrackCount; t++)
			{
				let track = clip.ScaleTracks[t];
				s.BeginObject(scope $"scaleTrack{t}");

				int32 boneIndex = track.BoneIndex;
				s.Int32("boneIndex", ref boneIndex);

				int32 interpInt = (int32)track.Interpolation;
				s.Int32("interpolation", ref interpInt);

				int32 keyframeCount = (int32)track.Keyframes.Count;
				s.Int32("keyframeCount", ref keyframeCount);

				if (keyframeCount > 0)
				{
					let times = scope List<float>();
					let values = scope List<float>();
					for (let kf in track.Keyframes)
					{
						times.Add(kf.Time);
						values.Add(kf.Value.X);
						values.Add(kf.Value.Y);
						values.Add(kf.Value.Z);
					}
					s.ArrayFloat("times", times);
					s.ArrayFloat("values", values);
				}

				s.EndObject();
			}

			s.EndObject();
		}

		s.EndObject();
	}

	private List<AnimationClip> DeserializeAnimations(Serializer s, int32 expectedCount)
	{
		s.BeginObject("animations");

		int32 count = 0;
		s.Int32("count", ref count);

		let animations = new List<AnimationClip>();

		for (int32 i = 0; i < count; i++)
		{
			s.BeginObject(scope $"clip{i}");

			String clipName = scope String();
			s.String("name", clipName);

			float duration = 0;
			s.Float("duration", ref duration);

			bool isLooping = false;
			s.Bool("isLooping", ref isLooping);

			let clip = new AnimationClip(clipName, duration, isLooping);

			// Deserialize position tracks
			int32 posTrackCount = 0;
			s.Int32("positionTrackCount", ref posTrackCount);
			for (int32 t = 0; t < posTrackCount; t++)
			{
				s.BeginObject(scope $"posTrack{t}");

				int32 boneIndex = 0;
				s.Int32("boneIndex", ref boneIndex);

				int32 interpInt = 0;
				s.Int32("interpolation", ref interpInt);

				let track = clip.GetOrCreatePositionTrack(boneIndex);
				track.Interpolation = (InterpolationMode)interpInt;

				int32 keyframeCount = 0;
				s.Int32("keyframeCount", ref keyframeCount);

				if (keyframeCount > 0)
				{
					let times = scope List<float>();
					let values = scope List<float>();
					s.ArrayFloat("times", times);
					s.ArrayFloat("values", values);

					for (int32 k = 0; k < keyframeCount; k++)
					{
						float time = k < times.Count ? times[k] : 0;
						int32 baseIdx = k * 3;
						Vector3 value = .Zero;
						if (baseIdx + 2 < values.Count)
							value = .(values[baseIdx], values[baseIdx + 1], values[baseIdx + 2]);
						track.AddKeyframe(time, value);
					}
				}

				s.EndObject();
			}

			// Deserialize rotation tracks
			int32 rotTrackCount = 0;
			s.Int32("rotationTrackCount", ref rotTrackCount);
			for (int32 t = 0; t < rotTrackCount; t++)
			{
				s.BeginObject(scope $"rotTrack{t}");

				int32 boneIndex = 0;
				s.Int32("boneIndex", ref boneIndex);

				int32 interpInt = 0;
				s.Int32("interpolation", ref interpInt);

				let track = clip.GetOrCreateRotationTrack(boneIndex);
				track.Interpolation = (InterpolationMode)interpInt;

				int32 keyframeCount = 0;
				s.Int32("keyframeCount", ref keyframeCount);

				if (keyframeCount > 0)
				{
					let times = scope List<float>();
					let values = scope List<float>();
					s.ArrayFloat("times", times);
					s.ArrayFloat("values", values);

					for (int32 k = 0; k < keyframeCount; k++)
					{
						float time = k < times.Count ? times[k] : 0;
						int32 baseIdx = k * 4;
						Quaternion value = .Identity;
						if (baseIdx + 3 < values.Count)
							value = Quaternion(values[baseIdx], values[baseIdx + 1], values[baseIdx + 2], values[baseIdx + 3]);
						track.AddKeyframe(time, value);
					}
				}

				s.EndObject();
			}

			// Deserialize scale tracks
			int32 scaleTrackCount = 0;
			s.Int32("scaleTrackCount", ref scaleTrackCount);
			for (int32 t = 0; t < scaleTrackCount; t++)
			{
				s.BeginObject(scope $"scaleTrack{t}");

				int32 boneIndex = 0;
				s.Int32("boneIndex", ref boneIndex);

				int32 interpInt = 0;
				s.Int32("interpolation", ref interpInt);

				let track = clip.GetOrCreateScaleTrack(boneIndex);
				track.Interpolation = (InterpolationMode)interpInt;

				int32 keyframeCount = 0;
				s.Int32("keyframeCount", ref keyframeCount);

				if (keyframeCount > 0)
				{
					let times = scope List<float>();
					let values = scope List<float>();
					s.ArrayFloat("times", times);
					s.ArrayFloat("values", values);

					for (int32 k = 0; k < keyframeCount; k++)
					{
						float time = k < times.Count ? times[k] : 0;
						int32 baseIdx = k * 3;
						Vector3 value = .(1, 1, 1);
						if (baseIdx + 2 < values.Count)
							value = .(values[baseIdx], values[baseIdx + 1], values[baseIdx + 2]);
						track.AddKeyframe(time, value);
					}
				}

				s.EndObject();
			}

			animations.Add(clip);
			s.EndObject();
		}

		s.EndObject();
		return animations;
	}

	/// Save this skinned mesh resource to a file (bundle format with skeleton + animations).
	public Result<void> SaveToFile(StringView path)
	{
		if (mMesh == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = FileVersion;
		writer.Int32("version", ref version);

		int32 fileType = BundleFileType;
		writer.Int32("type", ref fileType);

		Serialize(writer);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load a skinned mesh resource from a file.
	public static Result<SkinnedMeshResource> LoadFromFile(StringView path)
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
		if (fileType != BundleFileType && fileType != FileType)
			return .Err;

		let resource = new SkinnedMeshResource();
		resource.Serialize(reader);

		return .Ok(resource);
	}
}
