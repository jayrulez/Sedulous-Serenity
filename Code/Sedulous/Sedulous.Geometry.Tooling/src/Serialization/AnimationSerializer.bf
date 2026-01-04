using System;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Mathematics;
using Sedulous.Framework.Renderer;

namespace Sedulous.Geometry.Tooling;

/// Serialization helper for AnimationClip data.
static class AnimationSerializer
{
	/// Serialize an AnimationClip to a serializer.
	public static SerializationResult Serialize(Serializer s, StringView name, AnimationClip clip)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return result;

		if (s.IsWriting)
		{
			String clipName = scope String(clip.Name);
			s.String("name", clipName);

			float duration = clip.Duration;
			s.Float("duration", ref duration);

			int32 channelCount = (int32)clip.Channels.Count;
			s.Int32("channelCount", ref channelCount);

			if (channelCount > 0)
			{
				result = s.BeginObject("channels");
				if (result != .Ok) { s.EndObject(); return result; }

				for (int32 i = 0; i < channelCount; i++)
				{
					let channel = clip.Channels[i];
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
						let times = new List<float>();
						let values = new List<float>();
						defer { delete times; delete values; }

						for (int32 k = 0; k < keyframeCount; k++)
						{
							let kf = channel.Keyframes[k];
							times.Add(kf.Time);

							switch (channel.Property)
							{
							case .Translation, .Scale:
								values.Add(kf.Value.X);
								values.Add(kf.Value.Y);
								values.Add(kf.Value.Z);
							case .Rotation:
								values.Add(kf.Value.X);
								values.Add(kf.Value.Y);
								values.Add(kf.Value.Z);
								values.Add(kf.Value.W);
							}
						}

						s.ArrayFloat("times", times);
						s.ArrayFloat("values", values);
					}

					s.EndObject();
				}

				s.EndObject();
			}
		}

		s.EndObject();
		return .Ok;
	}

	/// Deserialize an AnimationClip from a serializer.
	public static Result<AnimationClip> Deserialize(Serializer s, StringView name)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return .Err;

		String clipName = scope String();
		s.String("name", clipName);

		let clip = new AnimationClip(clipName);

		float duration = 0;
		s.Float("duration", ref duration);
		clip.Duration = duration;

		int32 channelCount = 0;
		s.Int32("channelCount", ref channelCount);

		if (channelCount > 0)
		{
			result = s.BeginObject("channels");
			if (result != .Ok) { delete clip; s.EndObject(); return .Err; }

			for (int32 i = 0; i < channelCount; i++)
			{
				result = s.BeginObject(scope $"ch{i}");
				if (result != .Ok) break;

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
					let times = new List<float>();
					let values = new List<float>();
					defer { delete times; delete values; }

					s.ArrayFloat("times", times);
					s.ArrayFloat("values", values);

					int32 componentCount = GetComponentCount(property);
					for (int32 k = 0; k < keyframeCount; k++)
					{
						float time = 0;
						if (k < times.Count)
							time = times[k];

						int32 baseIdx = k * componentCount;
						Vector4 value = .Zero;
						switch (property)
						{
						case .Translation, .Scale:
							if (baseIdx + 2 < values.Count)
								value = .(values[baseIdx], values[baseIdx + 1], values[baseIdx + 2], 0);
						case .Rotation:
							if (baseIdx + 3 < values.Count)
								value = .(values[baseIdx], values[baseIdx + 1],
									values[baseIdx + 2], values[baseIdx + 3]);
						}

						channel.AddKeyframe(time, value);
					}
				}

				s.EndObject();
			}

			s.EndObject();
		}

		s.EndObject();
		return .Ok(clip);
	}

	/// Serialize a list of AnimationClips.
	public static SerializationResult SerializeList(Serializer s, StringView name, List<AnimationClip> clips)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return result;

		if (s.IsWriting)
		{
			int32 count = (int32)clips.Count;
			s.Int32("count", ref count);

			for (int32 i = 0; i < count; i++)
			{
				Serialize(s, scope $"clip{i}", clips[i]);
			}
		}

		s.EndObject();
		return .Ok;
	}

	/// Deserialize a list of AnimationClips.
	public static Result<List<AnimationClip>> DeserializeList(Serializer s, StringView name)
	{
		var result = s.BeginObject(name);
		if (result != .Ok) return .Err;

		let clips = new List<AnimationClip>();

		int32 count = 0;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			if (Deserialize(s, scope $"clip{i}") case .Ok(let clip))
			{
				clips.Add(clip);
			}
		}

		s.EndObject();
		return .Ok(clips);
	}

	private static int32 GetComponentCount(AnimationProperty prop)
	{
		switch (prop)
		{
		case .Translation, .Scale: return 3;
		case .Rotation: return 4;
		}
	}
}
