namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Interpolation mode for animation keyframes.
enum AnimationInterpolation
{
	Linear,
	Step,
	CubicSpline
}

/// Type of property being animated.
enum AnimationProperty
{
	Translation,
	Rotation,
	Scale
}

/// A single keyframe in an animation channel.
struct AnimationKeyframe
{
	public float Time;
	public Vector4 Value; // xyz for translation/scale, xyzw for rotation quaternion

	public this(float time, Vector4 value)
	{
		Time = time;
		Value = value;
	}

	public this(float time, Vector3 value)
	{
		Time = time;
		Value = .(value.X, value.Y, value.Z, 0);
	}

	public this(float time, Quaternion value)
	{
		Time = time;
		Value = .(value.X, value.Y, value.Z, value.W);
	}
}

/// An animation channel targeting a specific bone property.
class AnimationChannel
{
	public int32 BoneIndex;
	public AnimationProperty Property;
	public AnimationInterpolation Interpolation = .Linear;
	public List<AnimationKeyframe> Keyframes = new .() ~ delete _;

	public this(int32 boneIndex, AnimationProperty property)
	{
		BoneIndex = boneIndex;
		Property = property;
	}

	/// Adds a keyframe.
	public void AddKeyframe(float time, Vector4 value)
	{
		Keyframes.Add(.(time, value));
	}

	/// Samples the channel at a given time.
	public Vector4 Sample(float time)
	{
		if (Keyframes.Count == 0)
			return .Zero;

		if (Keyframes.Count == 1)
			return Keyframes[0].Value;

		// Clamp to animation bounds
		if (time <= Keyframes[0].Time)
			return Keyframes[0].Value;

		let lastIdx = Keyframes.Count - 1;
		if (time >= Keyframes[lastIdx].Time)
			return Keyframes[lastIdx].Value;

		// Find surrounding keyframes
		int32 i = 0;
		while (i < lastIdx && Keyframes[i + 1].Time < time)
			i++;

		let k0 = Keyframes[i];
		let k1 = Keyframes[i + 1];
		float t = (time - k0.Time) / (k1.Time - k0.Time);

		switch (Interpolation)
		{
		case .Step:
			return k0.Value;

		case .Linear:
			if (Property == .Rotation)
			{
				// Quaternion slerp
				let q0 = Quaternion(k0.Value.X, k0.Value.Y, k0.Value.Z, k0.Value.W);
				let q1 = Quaternion(k1.Value.X, k1.Value.Y, k1.Value.Z, k1.Value.W);
				let result = Quaternion.Slerp(q0, q1, t);
				return .(result.X, result.Y, result.Z, result.W);
			}
			else
			{
				return Vector4.Lerp(k0.Value, k1.Value, t);
			}

		case .CubicSpline:
			// Simplified: use linear for now
			return Vector4.Lerp(k0.Value, k1.Value, t);
		}
	}
}

/// A complete animation clip.
class AnimationClip
{
	public String Name ~ delete _;
	public float Duration;
	public List<AnimationChannel> Channels = new .() ~ DeleteContainerAndItems!(_);

	public this(StringView name)
	{
		Name = new String(name);
	}

	/// Adds a channel to the animation.
	public AnimationChannel AddChannel(int32 boneIndex, AnimationProperty property)
	{
		let channel = new AnimationChannel(boneIndex, property);
		Channels.Add(channel);
		return channel;
	}

	/// Calculates duration from keyframes.
	public void CalculateDuration()
	{
		Duration = 0;
		for (let channel in Channels)
		{
			for (let keyframe in channel.Keyframes)
			{
				if (keyframe.Time > Duration)
					Duration = keyframe.Time;
			}
		}
	}

	/// Samples all channels at a given time and applies to skeleton.
	public void Sample(float time, Skeleton skeleton)
	{
		// Collect TRS values per bone
		var translations = scope Vector3[skeleton.BoneCount];
		var rotations = scope Quaternion[skeleton.BoneCount];
		var scales = scope Vector3[skeleton.BoneCount];
		var hasTranslation = scope bool[skeleton.BoneCount];
		var hasRotation = scope bool[skeleton.BoneCount];
		var hasScale = scope bool[skeleton.BoneCount];

		// Initialize defaults from bind pose
		for (int32 i = 0; i < skeleton.BoneCount; i++)
		{
			skeleton.GetBindPose(i, out translations[i], out rotations[i], out scales[i]);
		}

		// Sample all channels
		for (let channel in Channels)
		{
			if (channel.BoneIndex < 0 || channel.BoneIndex >= skeleton.BoneCount)
				continue;

			let value = channel.Sample(time);

			switch (channel.Property)
			{
			case .Translation:
				translations[channel.BoneIndex] = .(value.X, value.Y, value.Z);
				hasTranslation[channel.BoneIndex] = true;
			case .Rotation:
				rotations[channel.BoneIndex] = Quaternion(value.X, value.Y, value.Z, value.W);
				hasRotation[channel.BoneIndex] = true;
			case .Scale:
				scales[channel.BoneIndex] = .(value.X, value.Y, value.Z);
				hasScale[channel.BoneIndex] = true;
			}
		}

		// Apply to skeleton
		for (int32 i = 0; i < skeleton.BoneCount; i++)
		{
			// Only update bones that have animation data
			if (hasTranslation[i] || hasRotation[i] || hasScale[i])
			{
				skeleton.SetBoneTransform(i, translations[i], rotations[i], scales[i]);
			}
		}
	}
}
