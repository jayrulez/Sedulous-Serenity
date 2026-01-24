using System;

namespace Sedulous.Navigation.Crowd;

/// Flags controlling crowd agent update behaviors.
enum CrowdAgentUpdateFlags : uint8
{
	/// No special behaviors.
	None = 0,
	/// Anticipate turns to smooth movement.
	AnticipateTurns = 1,
	/// Use obstacle avoidance (velocity obstacles).
	ObstacleAvoidance = 2,
	/// Apply separation force from nearby agents.
	Separation = 4,
	/// Optimize path visibility (shortcut corners).
	OptimizeVisibility = 8,
	/// Optimize path topology (remove unnecessary nodes).
	OptimizeTopology = 16
}
