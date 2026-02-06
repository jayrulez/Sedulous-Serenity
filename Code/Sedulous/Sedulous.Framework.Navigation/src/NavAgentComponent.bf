namespace Sedulous.Framework.Navigation;

using Sedulous.Framework.Scenes;
using Sedulous.Serialization;
using recastnavigation_Beef;

/// Component for entities with navigation agents.
/// The AgentIndex references the agent in the CrowdManager owned by NavWorld.
/// Configuration fields mirror CrowdAgentParams for serialization/deserialization.
struct NavAgentComponent : ISerializableComponent
{
	/// Index of this agent in the CrowdManager (runtime-only, not serialized).
	public int32 AgentIndex;
	/// Whether to sync entity transform from the agent position each frame.
	public bool SyncToTransform;
	// Agent configuration (from CrowdAgentParams)
	/// Agent radius.
	public float Radius;
	/// Agent height.
	public float Height;
	/// Maximum acceleration.
	public float MaxAcceleration;
	/// Maximum speed.
	public float MaxSpeed;
	/// Collision query range.
	public float CollisionQueryRange;
	/// Path optimization range.
	public float PathOptimizationRange;
	/// Separation weight for crowd avoidance.
	public float SeparationWeight;
	/// Obstacle avoidance quality type (0-3).
	public uint8 ObstacleAvoidanceType;

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		// AgentIndex is runtime-only (assigned by CrowdManager), skip it
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
			// uint8 serialized as int32
			var oaType = (int32)ObstacleAvoidanceType;
			s.Int32("obstacleAvoidanceType", ref oaType);
			ObstacleAvoidanceType = (uint8)oaType;
		}
		return .Ok;
	}

	public static NavAgentComponent Default => .() {
		AgentIndex = -1,
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

	/// Builds CrowdAgentParams from this component's stored config.
	public CrowdAgentParams ToCrowdAgentParams() =>
		.() {
			Radius = Radius,
			Height = Height,
			MaxAcceleration = MaxAcceleration,
			MaxSpeed = MaxSpeed,
			CollisionQueryRange = CollisionQueryRange,
			PathOptimizationRange = PathOptimizationRange,
			SeparationWeight = SeparationWeight,
			ObstacleAvoidanceType = ObstacleAvoidanceType,
			UpdateFlags = (.)dtCrowdUpdateFlags.DT_CROWD_ANTICIPATE_TURNS |
						  (.)dtCrowdUpdateFlags.DT_CROWD_OBSTACLE_AVOIDANCE |
						  (.)dtCrowdUpdateFlags.DT_CROWD_SEPARATION,
			QueryFilterType = 0,
			UserData = null
		};
}
