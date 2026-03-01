namespace Sedulous.Engine.Animation;

using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Transient serialization data for property animation components.
/// Only exists during save/load — all runtime data lives in AnimationSceneModule.
struct PropertyAnimationComponentData : ISerializableComponentData
{
	public bool Playing;
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

	public void Dispose() mut { }
}
