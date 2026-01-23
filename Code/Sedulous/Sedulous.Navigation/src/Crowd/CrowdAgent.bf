using System;
using System.Collections;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Crowd;

/// A single agent in the crowd simulation.
class CrowdAgent
{
	/// Whether this agent slot is active.
	public bool Active;
	/// Current state of the agent.
	public CrowdAgentState State;
	/// Agent configuration parameters.
	public CrowdAgentParams Params;

	/// Current world position.
	public float[3] Position;
	/// Current velocity.
	public float[3] Velocity;
	/// Desired velocity (before avoidance).
	public float[3] DesiredVelocity;
	/// Target position for path following.
	public float[3] TargetPosition;

	/// Current polygon reference the agent is on.
	public PolyRef CurrentPoly;
	/// Target polygon reference.
	public PolyRef TargetRef;

	/// Move request state.
	public MoveRequestState MoveRequestState;

	/// Current corridor (path following).
	public PathCorridor Corridor ~ delete _;
	/// Neighboring agents within collision range.
	public List<CrowdNeighbor> Neighbors = new .() ~ delete _;

	/// Maximum number of neighbors to track.
	public const int32 MaxNeighbors = 8;

	public this()
	{
		Active = false;
		State = .Invalid;
		Position = default;
		Velocity = default;
		DesiredVelocity = default;
		TargetPosition = default;
		CurrentPoly = .Null;
		TargetRef = .Null;
		MoveRequestState = .None;
		Corridor = new PathCorridor();
	}

	/// Resets the agent to its initial state.
	public void Reset()
	{
		Active = false;
		State = .Invalid;
		Position = default;
		Velocity = default;
		DesiredVelocity = default;
		TargetPosition = default;
		CurrentPoly = .Null;
		TargetRef = .Null;
		MoveRequestState = .None;
		Neighbors.Clear();
	}

	/// Integrates velocity to update position.
	public void Integrate(float dt)
	{
		if (State != .Walking) return;

		float speed = Math.Sqrt(Velocity[0] * Velocity[0] + Velocity[2] * Velocity[2]);
		if (speed < 0.0001f) return;

		Position[0] += Velocity[0] * dt;
		Position[1] += Velocity[1] * dt;
		Position[2] += Velocity[2] * dt;
	}

	/// Calculates the distance squared to another position.
	public float DistanceSqTo(float[3] other)
	{
		float dx = Position[0] - other[0];
		float dy = Position[1] - other[1];
		float dz = Position[2] - other[2];
		return dx * dx + dy * dy + dz * dz;
	}
}
