namespace Sedulous.Engine.Navigation;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Component for entities that represent dynamic navigation obstacles.
/// The ObstacleId references the obstacle in the TileCache owned by NavWorld.
[Component]
struct NavObstacleComponent : ISerializableComponent
{
	/// ID of this obstacle in the TileCache.
	public int32 ObstacleId;
	/// Obstacle cylinder radius.
	public float Radius;
	/// Obstacle cylinder height.
	public float Height;

	public void Dispose() mut { }

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		// ObstacleId is runtime-only (assigned by TileCache), skip it
		s.Float("radius", ref Radius);
		s.Float("height", ref Height);
		return .Ok;
	}

	public static NavObstacleComponent Default => .() {
		ObstacleId = -1,
		Radius = 0,
		Height = 0
	};
}
