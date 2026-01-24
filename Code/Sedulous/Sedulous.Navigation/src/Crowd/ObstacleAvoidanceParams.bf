using System;

namespace Sedulous.Navigation.Crowd;

/// Parameters controlling the obstacle avoidance velocity sampling.
[CRepr]
struct ObstacleAvoidanceParams
{
	/// Desired velocity weight (how much to prefer the desired direction).
	public float VelBias;
	/// Weight for desired velocity vs. current velocity.
	public float WeightDesVel;
	/// Weight for current velocity preference.
	public float WeightCurVel;
	/// Weight for side (perpendicular) preference.
	public float WeightSide;
	/// Weight for time-of-impact (collision avoidance urgency).
	public float WeightToi;
	/// Horizontal time horizon for obstacle avoidance.
	public float HorizTime;
	/// Number of adaptive sampling divisions (per ring).
	public uint8 AdaptiveDivs;
	/// Number of adaptive sampling rings.
	public uint8 AdaptiveRings;
	/// Depth of adaptive sampling detail.
	public uint8 AdaptiveDepth;

	/// Default parameters for quality level 0 (low).
	public static ObstacleAvoidanceParams Low
	{
		get
		{
			ObstacleAvoidanceParams p = .();
			p.VelBias = 0.4f;
			p.WeightDesVel = 2.0f;
			p.WeightCurVel = 0.75f;
			p.WeightSide = 0.75f;
			p.WeightToi = 2.5f;
			p.HorizTime = 2.5f;
			p.AdaptiveDivs = 5;
			p.AdaptiveRings = 2;
			p.AdaptiveDepth = 1;
			return p;
		}
	}

	/// Default parameters for quality level 2 (medium-high).
	public static ObstacleAvoidanceParams Medium
	{
		get
		{
			ObstacleAvoidanceParams p = .();
			p.VelBias = 0.5f;
			p.WeightDesVel = 2.0f;
			p.WeightCurVel = 0.75f;
			p.WeightSide = 0.75f;
			p.WeightToi = 2.5f;
			p.HorizTime = 2.5f;
			p.AdaptiveDivs = 7;
			p.AdaptiveRings = 2;
			p.AdaptiveDepth = 3;
			return p;
		}
	}
}
