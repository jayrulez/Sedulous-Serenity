namespace Sedulous.Engine.Animation;

using Sedulous.Engine.Scenes;
using Sedulous.Resources;
using Sedulous.Serialization;

using static Sedulous.Resources.ResourceSerializerExtensions;

/// Transient serialization data for animation graph components.
/// Only exists during save/load — all runtime data lives in AnimationSceneModule.
struct AnimationGraphComponentData : ISerializableComponentData
{
	[Property]
	public ResourceRef SkeletonRef;
	[Property]
	public bool Active;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.ResourceRef("skeleton", ref SkeletonRef);
		s.Bool("active", ref Active);
		return .Ok;
	}

	public void Dispose() mut
	{
		SkeletonRef.Dispose();
	}
}
