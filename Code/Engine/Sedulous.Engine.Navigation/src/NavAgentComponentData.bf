namespace Sedulous.Engine.Navigation;

using System;
using Sedulous.Serialization;

/// Transient serialization data for NavAgentComponent.
/// Only exists during save/load — not stored at runtime.
struct NavAgentComponentData
{
	public bool SyncToTransform;
	public float Radius;
	public float Height;
	public float MaxAcceleration;
	public float MaxSpeed;
	public float CollisionQueryRange;
	public float PathOptimizationRange;
	public float SeparationWeight;
	public uint8 ObstacleAvoidanceType;

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Bool("syncToTransform", ref SyncToTransform);
		if (version >= 2)
		{
			s.Float("radius", ref Radius);
			s.Float("height", ref Height);
			s.Float("maxAcceleration", ref MaxAcceleration);
			s.Float("maxSpeed", ref MaxSpeed);
			s.Float("collisionQueryRange", ref CollisionQueryRange);
			s.Float("pathOptimizationRange", ref PathOptimizationRange);
			s.Float("separationWeight", ref SeparationWeight);
			var oaType = (int32)ObstacleAvoidanceType;
			s.Int32("obstacleAvoidanceType", ref oaType);
			ObstacleAvoidanceType = (uint8)oaType;
		}
		return .Ok;
	}

	public void Dispose() mut { }

	public static NavAgentComponentData Default => .() {
		SyncToTransform = true,
		Radius = 0.6f,
		Height = 2.0f,
		MaxAcceleration = 8.0f,
		MaxSpeed = 3.5f,
		CollisionQueryRange = 12.0f,
		PathOptimizationRange = 30.0f,
		SeparationWeight = 2.0f,
		ObstacleAvoidanceType = 3
	};
}
