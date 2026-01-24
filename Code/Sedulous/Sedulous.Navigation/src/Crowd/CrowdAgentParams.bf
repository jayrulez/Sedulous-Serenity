using System;

namespace Sedulous.Navigation.Crowd;

/// Configuration parameters for a crowd agent.
[CRepr]
struct CrowdAgentParams
{
	/// Agent collision radius.
	public float Radius;
	/// Agent height.
	public float Height;
	/// Maximum acceleration (units/sec²).
	public float MaxAcceleration;
	/// Maximum movement speed (units/sec).
	public float MaxSpeed;
	/// Range to query for nearby agents for collision.
	public float CollisionQueryRange;
	/// Range to optimize path visibility.
	public float PathOptimizationRange;
	/// Weight applied to separation behavior.
	public float SeparationWeight;
	/// Quality of avoidance sampling (0-3, higher = more samples).
	public uint8 AvoidanceQuality;
	/// Flags controlling which update behaviors are enabled.
	public CrowdAgentUpdateFlags UpdateFlags;

	/// Creates default agent parameters suitable for a humanoid character.
	public static CrowdAgentParams Default
	{
		get
		{
			CrowdAgentParams p = .();
			p.Radius = 0.6f;
			p.Height = 2.0f;
			p.MaxAcceleration = 8.0f;
			p.MaxSpeed = 3.5f;
			p.CollisionQueryRange = 12.0f;
			p.PathOptimizationRange = 30.0f;
			p.SeparationWeight = 2.0f;
			p.AvoidanceQuality = 2;
			p.UpdateFlags = .AnticipateTurns | .ObstacleAvoidance | .Separation | .OptimizeVisibility;
			return p;
		}
	}
}
