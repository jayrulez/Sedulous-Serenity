using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Models;
using Sedulous.Engine.Renderer;

namespace Sedulous.Geometry.Tooling;

/// Converts Model animations to runtime AnimationClip format.
static class AnimationConverter
{
	/// Converts a ModelAnimation to an AnimationClip, remapping bone indices using the provided mapping.
	/// The nodeToBoneMapping converts node indices (from animation channels) to skeleton bone indices.
	public static AnimationClip Convert(ModelAnimation modelAnim, int32[] nodeToBoneMapping)
	{
		if (modelAnim == null)
			return null;

		let clip = new AnimationClip(modelAnim.Name);
		clip.Duration = modelAnim.Duration;

		for (let modelChannel in modelAnim.Channels)
		{
			// Remap target bone from node index to skeleton bone index
			let nodeIdx = modelChannel.TargetBone;
			if (nodeToBoneMapping == null || nodeIdx < 0 || nodeIdx >= nodeToBoneMapping.Count)
				continue;

			let boneIdx = nodeToBoneMapping[nodeIdx];
			if (boneIdx < 0)
				continue;  // This node is not a skin joint, skip

			AnimationProperty property;
			switch (modelChannel.Path)
			{
			case .Translation: property = .Translation;
			case .Rotation: property = .Rotation;
			case .Scale: property = .Scale;
			case .Weights: continue;  // Morph targets not supported yet
			}

			let channel = clip.AddChannel(boneIdx, property);

			switch (modelChannel.Interpolation)
			{
			case .Linear: channel.Interpolation = .Linear;
			case .Step: channel.Interpolation = .Step;
			case .CubicSpline: channel.Interpolation = .CubicSpline;
			}

			for (let keyframe in modelChannel.Keyframes)
				channel.AddKeyframe(keyframe.Time, keyframe.Value);
		}

		return clip;
	}

	/// Converts all animations from a Model, remapping bone indices using the provided mapping.
	/// Caller owns the returned list and its contents.
	public static List<AnimationClip> ConvertAll(Model model, int32[] nodeToBoneMapping)
	{
		if (model == null)
			return null;

		let clips = new List<AnimationClip>();

		for (let modelAnim in model.Animations)
		{
			let clip = Convert(modelAnim, nodeToBoneMapping);
			if (clip != null)
				clips.Add(clip);
		}

		return clips;
	}
}
