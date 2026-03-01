namespace Sedulous.Engine.Navigation;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Transient serialization data for NavObstacleComponent.
/// Only exists during save/load — not stored at runtime.
struct NavObstacleComponentData
{
	[Property]
	public float Radius;
	[Property]
	public float Height;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Float("radius", ref Radius);
		s.Float("height", ref Height);
		return .Ok;
	}

	public void Dispose() mut { }
}
