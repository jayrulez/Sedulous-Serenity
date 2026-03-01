namespace Sedulous.Engine.Animation;

using Sedulous.Engine.Scenes;
using Sedulous.Resources;
using Sedulous.Serialization;

using static Sedulous.Resources.ResourceSerializerExtensions;

/// Transient serialization data for skeletal animation components.
/// Only exists during save/load — all runtime data lives in AnimationSceneModule.
struct SkeletalAnimationComponentData : ISerializableComponentData
{
	[Property] public ResourceRef SkeletonRef;
	[Property] public ResourceRef AnimationClipRef;
	[Property] public bool Playing;
	[Property] public bool Loop;

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

	public void Dispose() mut
	{
		SkeletonRef.Dispose();
		AnimationClipRef.Dispose();
	}
}
