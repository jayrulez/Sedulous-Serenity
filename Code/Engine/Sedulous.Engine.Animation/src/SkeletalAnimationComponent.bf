namespace Sedulous.Engine.Animation;

using System;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Engine.Scenes;
using Sedulous.Resources;
using Sedulous.Serialization;

using static Sedulous.Resources.ResourceSerializerExtensions;

/// Component for entities with skeletal animation.
[Component]
struct SkeletalAnimationComponent : ISerializableComponent
{
	/// The animation player for this entity (runtime, not serialized).
	public AnimationPlayer Player;
	/// The skeleton resource handle (runtime, not serialized).
	public ResourceHandle<SkeletonResource> SkeletonRes;
	/// Serializable reference to the skeleton resource.
	[Property] public ResourceRef SkeletonRef;
	/// The animation clip resource handle (runtime, not serialized).
	public ResourceHandle<AnimationClipResource> AnimationClipRes;
	/// Serializable reference to the animation clip resource.
	[Property] public ResourceRef AnimationClipRef;
	/// Whether the animation is playing.
	[Property] public bool Playing;
	/// Whether the animation should loop.
	[Property] public bool Loop;

	public void Dispose() mut { }

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		if (version >= 2)
		{
			s.ResourceRef("skeleton", ref SkeletonRef);
			s.ResourceRef("animationClip", ref AnimationClipRef);
			s.Bool("loop", ref Loop);
		}
		s.Bool("playing", ref Playing);
		return .Ok;
	}

	public static SkeletalAnimationComponent Default => .() {
		Player = null,
		SkeletonRes = default,
		SkeletonRef = .(),
		AnimationClipRes = default,
		AnimationClipRef = .(),
		Playing = false,
		Loop = true
	};
}
