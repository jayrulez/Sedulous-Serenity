namespace Sedulous.Framework.Animation;

using Sedulous.Animation;
using Sedulous.Framework.Scenes;
using Sedulous.Serialization;

/// Component for entities with skeletal animation.
struct SkeletalAnimationComponent : ISerializableComponent
{
	/// The animation player for this entity.
	public AnimationPlayer Player;
	/// The skeleton reference.
	public Skeleton Skeleton;
	/// Whether the animation is playing.
	public bool Playing;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		// TODO: Serialize Player and Skeleton when resource serialization is implemented
		s.Bool("playing", ref Playing);
		return .Ok;
	}

	public static SkeletalAnimationComponent Default => .() {
		Player = null,
		Skeleton = null,
		Playing = false
	};
}
