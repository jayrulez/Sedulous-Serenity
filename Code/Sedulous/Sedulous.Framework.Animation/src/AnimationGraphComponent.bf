namespace Sedulous.Framework.Animation;

using System;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Framework.Scenes;
using Sedulous.Resources;
using Sedulous.Serialization;

using static Sedulous.Resources.ResourceSerializerExtensions;

/// Component for entities using an animation graph for complex animation blending.
struct AnimationGraphComponent : ISerializableComponent
{
	/// The animation graph player for this entity (runtime, not serialized).
	public AnimationGraphPlayer Player;

	/// The animation graph definition (runtime, not serialized).
	public AnimationGraph Graph;

	/// The skeleton resource handle (runtime, not serialized).
	public ResourceHandle<SkeletonResource> SkeletonRes;

	/// Serializable reference to the skeleton resource.
	public ResourceRef SkeletonRef;

	/// Whether the graph is actively evaluating.
	public bool Active;

	public void Dispose() mut { }

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.ResourceRef("skeleton", ref SkeletonRef);
		s.Bool("active", ref Active);
		return .Ok;
	}

	public static AnimationGraphComponent Default => .() {
		Player = null,
		Graph = null,
		SkeletonRes = default,
		SkeletonRef = .(),
		Active = true
	};
}
