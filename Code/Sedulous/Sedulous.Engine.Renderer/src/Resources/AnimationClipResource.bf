using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Geometry;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Mathematics;

namespace Sedulous.Engine.Renderer;

/// CPU-side animation clip resource for skeletal animation.
/// Can be shared between multiple AnimationPlayers.
class AnimationClipResource : Resource
{
	public const int32 FileVersion = 1;
	public const int32 FileType = 4; // ResourceFileType.Animation

	private AnimationClip mClip;
	private bool mOwnsClip;

	/// The underlying animation clip data.
	public AnimationClip Clip => mClip;

	/// Duration of the animation in seconds.
	public float Duration => mClip?.Duration ?? 0;

	/// Number of animation channels.
	public int ChannelCount => mClip?.Channels?.Count ?? 0;

	public this()
	{
		mClip = null;
		mOwnsClip = false;
	}

	public this(AnimationClip clip, bool ownsClip = false)
	{
		mClip = clip;
		mOwnsClip = ownsClip;
		if (clip != null && Name.IsEmpty)
			Name.Set(clip.Name);
	}

	public ~this()
	{
		if (mOwnsClip && mClip != null)
			delete mClip;
	}

	/// Sets the animation clip. Takes ownership if ownsClip is true.
	public void SetClip(AnimationClip clip, bool ownsClip = false)
	{
		if (mOwnsClip && mClip != null)
			delete mClip;
		mClip = clip;
		mOwnsClip = ownsClip;
	}

	// ---- Serialization ----

	public override int32 SerializationVersion => 1;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		if (s.IsWriting)
		{
			if (mClip == null)
				return .InvalidData;

			// Write clip name
			String clipName = scope String(mClip.Name);
			s.String("clipName", clipName);

			// Write duration
			float duration = mClip.Duration;
			s.Float("duration", ref duration);

			// Write channels
			int32 channelCount = (int32)mClip.Channels.Count;
			s.Int32("channelCount", ref channelCount);

			for (int32 i = 0; i < channelCount; i++)
			{
				let channel = mClip.Channels[i];
				s.BeginObject(scope $"ch{i}");

				int32 boneIndex = channel.BoneIndex;
				s.Int32("boneIndex", ref boneIndex);

				int32 propertyInt = (int32)channel.Property;
				s.Int32("property", ref propertyInt);

				int32 interpInt = (int32)channel.Interpolation;
				s.Int32("interpolation", ref interpInt);

				int32 keyframeCount = (int32)channel.Keyframes.Count;
				s.Int32("keyframeCount", ref keyframeCount);

				if (keyframeCount > 0)
				{
					let times = scope float[keyframeCount];
					let values = scope float[keyframeCount * 4]; // Max 4 components per value

					for (int32 k = 0; k < keyframeCount; k++)
					{
						let kf = channel.Keyframes[k];
						times[k] = kf.Time;
						values[k * 4 + 0] = kf.Value.X;
						values[k * 4 + 1] = kf.Value.Y;
						values[k * 4 + 2] = kf.Value.Z;
						values[k * 4 + 3] = kf.Value.W;
					}

					s.FixedFloatArray("times", &times[0], keyframeCount);

					int32 valueComponents = GetComponentCount(channel.Property);
					s.FixedFloatArray("values", &values[0], keyframeCount * valueComponents);
				}

				s.EndObject();
			}
		}
		else
		{
			// Read clip name
			String clipName = scope String();
			s.String("clipName", clipName);

			// Create new clip
			let clip = new AnimationClip(clipName);

			// Read duration
			float duration = 0;
			s.Float("duration", ref duration);
			clip.Duration = duration;

			// Read channels
			int32 channelCount = 0;
			s.Int32("channelCount", ref channelCount);

			for (int32 i = 0; i < channelCount; i++)
			{
				s.BeginObject(scope $"ch{i}");

				int32 boneIndex = 0;
				s.Int32("boneIndex", ref boneIndex);

				int32 propertyInt = 0;
				s.Int32("property", ref propertyInt);
				let property = (AnimationProperty)propertyInt;

				int32 interpInt = 0;
				s.Int32("interpolation", ref interpInt);
				let interpolation = (AnimationInterpolation)interpInt;

				let channel = clip.AddChannel(boneIndex, property);
				channel.Interpolation = interpolation;

				int32 keyframeCount = 0;
				s.Int32("keyframeCount", ref keyframeCount);

				if (keyframeCount > 0)
				{
					int32 valueComponents = GetComponentCount(property);
					let times = scope float[keyframeCount];
					let values = scope float[keyframeCount * valueComponents];

					s.FixedFloatArray("times", &times[0], keyframeCount);
					s.FixedFloatArray("values", &values[0], keyframeCount * valueComponents);

					for (int32 k = 0; k < keyframeCount; k++)
					{
						Vector4 value = .Zero;
						switch (property)
						{
						case .Translation, .Scale:
							value = .(values[k * valueComponents + 0],
									  values[k * valueComponents + 1],
									  values[k * valueComponents + 2], 0);
						case .Rotation:
							value = .(values[k * valueComponents + 0],
									  values[k * valueComponents + 1],
									  values[k * valueComponents + 2],
									  values[k * valueComponents + 3]);
						}

						channel.AddKeyframe(times[k], value);
					}
				}

				s.EndObject();
			}

			// Set the clip
			SetClip(clip, true);
		}

		return .Ok;
	}

	private static int32 GetComponentCount(AnimationProperty prop)
	{
		switch (prop)
		{
		case .Translation, .Scale: return 3;
		case .Rotation: return 4;
		}
	}

	/// Save this animation resource to a file.
	public Result<void> SaveToFile(StringView path)
	{
		if (mClip == null)
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

	/// Load an animation resource from a file.
	public static Result<AnimationClipResource> LoadFromFile(StringView path)
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

		let resource = new AnimationClipResource();
		resource.Serialize(reader);

		return .Ok(resource);
	}
}
