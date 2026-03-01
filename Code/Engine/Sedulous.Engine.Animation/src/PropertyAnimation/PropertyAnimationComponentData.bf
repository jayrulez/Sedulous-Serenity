namespace Sedulous.Engine.Animation;

using Sedulous.Engine.Scenes;
using Sedulous.Resources;
using Sedulous.Serialization;
using static Sedulous.Resources.ResourceSerializerExtensions;

/// Transient serialization data for property animation components.
/// Only exists during save/load — all runtime data lives in AnimationSceneModule.
struct PropertyAnimationComponentData : ISerializableComponentData
{
	[Property]
	public ResourceRef ClipRef;
	[Property]
	public bool Playing;
	[Property]
	public float Speed;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.ResourceRef("clip", ref ClipRef);
		s.Bool("playing", ref Playing);
		s.Float("speed", ref Speed);
		return .Ok;
	}

	public void Dispose() mut { ClipRef.Dispose(); }
}
