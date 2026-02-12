namespace Sedulous.Framework.Animation;

using Sedulous.Framework.Scenes;
using Sedulous.Serialization;

/// Component for entities with property animation.
struct PropertyAnimationComponent : ISerializableComponent
{
	/// The property animation player for this entity (runtime, not serialized).
	public PropertyAnimationPlayer Player;
	/// Whether the animation is playing.
	public bool Playing;
	/// Playback speed multiplier.
	public float Speed;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Bool("playing", ref Playing);
		s.Float("speed", ref Speed);
		return .Ok;
	}

	public static PropertyAnimationComponent Default => .() {
		Player = null,
		Playing = false,
		Speed = 1.0f
	};
}
