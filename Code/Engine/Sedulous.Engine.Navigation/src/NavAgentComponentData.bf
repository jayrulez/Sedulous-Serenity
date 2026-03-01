namespace Sedulous.Engine.Navigation;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Transient serialization data for NavAgentComponent.
/// Only exists during save/load — not stored at runtime.
struct NavAgentComponentData
{
	[Property]
	public bool SyncToTransform;
	[Property]
	public float Radius;
	[Property]
	public float Height;
	[Property]
	public float MaxAcceleration;
	[Property]
	public float MaxSpeed;
	[Property]
	public float CollisionQueryRange;
	[Property]
	public float PathOptimizationRange;
	[Property]
	public float SeparationWeight;
	[Property]
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
