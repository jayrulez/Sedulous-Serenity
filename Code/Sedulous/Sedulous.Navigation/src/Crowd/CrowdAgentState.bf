using System;

namespace Sedulous.Navigation.Crowd;

/// State of a crowd agent.
enum CrowdAgentState : uint8
{
	/// Agent is not active.
	Invalid = 0,
	/// Agent is walking toward its target.
	Walking,
	/// Agent has reached its target and is idle.
	Idle,
	/// Agent is traversing an off-mesh connection.
	OffMeshConnection
}

/// State of a crowd agent's move request.
enum MoveRequestState : uint8
{
	/// No active move request.
	None = 0,
	/// Move request is pending path computation.
	Pending,
	/// Path has been computed and is valid.
	Valid,
	/// Move request failed (no path found).
	Failed
}
