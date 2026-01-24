using System;
using System.Collections;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Crowd;

/// Manages a crowd of agents performing path following and local avoidance.
/// Call Update() each frame to advance the simulation.
class CrowdManager
{
	private NavMesh mNavMesh;
	private NavMeshQuery mQuery ~ delete _;
	private NavMeshQueryFilter mFilter ~ delete _;
	private CrowdAgent[] mAgents ~ { for (var a in _) delete a; delete _; };
	private int32 mMaxAgents;
	private int32 mActiveAgentCount;
	private ObstacleAvoidanceQuery mAvoidanceQuery ~ delete _;
	private ObstacleAvoidanceParams[4] mAvoidanceParams;

	/// Number of active agents.
	public int32 ActiveAgentCount => mActiveAgentCount;
	/// Maximum number of agents.
	public int32 MaxAgents => mMaxAgents;

	/// Initializes the crowd manager.
	public NavStatus Init(NavMesh navMesh, int32 maxAgents = 128)
	{
		mNavMesh = navMesh;
		mMaxAgents = maxAgents;
		mActiveAgentCount = 0;

		mQuery = new NavMeshQuery();
		mQuery.Init(navMesh);
		mFilter = new NavMeshQueryFilter();
		mAvoidanceQuery = new ObstacleAvoidanceQuery();

		mAgents = new CrowdAgent[maxAgents];
		for (int32 i = 0; i < maxAgents; i++)
			mAgents[i] = new CrowdAgent();

		// Set up default avoidance params per quality level
		mAvoidanceParams[0] = ObstacleAvoidanceParams.Low;
		mAvoidanceParams[1] = ObstacleAvoidanceParams.Low;
		mAvoidanceParams[2] = ObstacleAvoidanceParams.Medium;
		mAvoidanceParams[3] = ObstacleAvoidanceParams.Medium;
		mAvoidanceParams[3].AdaptiveDivs = 7;
		mAvoidanceParams[3].AdaptiveRings = 3;
		mAvoidanceParams[3].AdaptiveDepth = 5;

		return .Success;
	}

	/// Gets an agent by index.
	public CrowdAgent GetAgent(int32 index)
	{
		if (index < 0 || index >= mMaxAgents)
			return null;
		if (!mAgents[index].Active)
			return null;
		return mAgents[index];
	}

	/// Adds a new agent at the given position.
	/// Returns the agent index, or -1 if no slots available.
	public int32 AddAgent(float[3] position, in CrowdAgentParams @params)
	{
		// Find free slot
		int32 idx = -1;
		for (int32 i = 0; i < mMaxAgents; i++)
		{
			if (!mAgents[i].Active)
			{
				idx = i;
				break;
			}
		}
		if (idx < 0) return -1;

		let agent = mAgents[idx];
		agent.Reset();
		agent.Active = true;
		agent.State = .Idle;
		agent.Params = @params;
		agent.Position = position;

		// Find nearest poly
		float[3] extents = .(@params.CollisionQueryRange, @params.Height, @params.CollisionQueryRange);
		PolyRef nearestRef;
		float[3] nearestPoint;
		if (mQuery.FindNearestPoly(position, extents, mFilter, out nearestRef, out nearestPoint) == .Success)
		{
			agent.CurrentPoly = nearestRef;
			agent.Position = nearestPoint;
			agent.Corridor.Reset(nearestRef, nearestPoint);
		}

		mActiveAgentCount++;
		return idx;
	}

	/// Removes an agent from the crowd.
	public void RemoveAgent(int32 index)
	{
		if (index < 0 || index >= mMaxAgents) return;
		if (!mAgents[index].Active) return;

		mAgents[index].Reset();
		mActiveAgentCount--;
	}

	/// Requests an agent to move toward the given target.
	/// Returns true if the request was accepted.
	public bool RequestMoveTarget(int32 agentIndex, PolyRef targetRef, float[3] targetPos)
	{
		if (agentIndex < 0 || agentIndex >= mMaxAgents) return false;
		let agent = mAgents[agentIndex];
		if (!agent.Active) return false;

		agent.TargetRef = targetRef;
		agent.TargetPosition = targetPos;
		agent.MoveRequestState = .Pending;

		return true;
	}

	/// Requests an agent to move to a world position (finds nearest poly automatically).
	public bool RequestMovePosition(int32 agentIndex, float[3] targetPos)
	{
		if (agentIndex < 0 || agentIndex >= mMaxAgents) return false;
		let agent = mAgents[agentIndex];
		if (!agent.Active) return false;

		float[3] extents = .(agent.Params.CollisionQueryRange, agent.Params.Height, agent.Params.CollisionQueryRange);
		PolyRef targetRef;
		float[3] nearestPoint;
		if (mQuery.FindNearestPoly(targetPos, extents, mFilter, out targetRef, out nearestPoint) != .Success)
			return false;

		return RequestMoveTarget(agentIndex, targetRef, nearestPoint);
	}

	/// Advances the crowd simulation by dt seconds.
	/// This is the main update loop: processes move requests, plans paths,
	/// computes steering, applies avoidance, and integrates positions.
	public void Update(float dt)
	{
		if (dt <= 0) return;

		// Phase 1: Process move requests
		ProcessMoveRequests();

		// Phase 2: Update corridor positions and find neighbors
		for (int32 i = 0; i < mMaxAgents; i++)
		{
			let agent = mAgents[i];
			if (!agent.Active || agent.State == .Invalid) continue;

			UpdateAgentPosition(agent);
			FindNeighbors(agent, i);
		}

		// Phase 3: Compute desired velocity (steering toward target)
		for (int32 i = 0; i < mMaxAgents; i++)
		{
			let agent = mAgents[i];
			if (!agent.Active || agent.State != .Walking) continue;

			ComputeDesiredVelocity(agent);
		}

		// Phase 4: Apply obstacle avoidance
		for (int32 i = 0; i < mMaxAgents; i++)
		{
			let agent = mAgents[i];
			if (!agent.Active || agent.State != .Walking) continue;

			if (agent.Params.UpdateFlags.HasFlag(.ObstacleAvoidance))
			{
				ApplyAvoidance(agent, i);
			}
			else
			{
				agent.Velocity = agent.DesiredVelocity;
			}
		}

		// Phase 5: Apply separation
		for (int32 i = 0; i < mMaxAgents; i++)
		{
			let agent = mAgents[i];
			if (!agent.Active || agent.State != .Walking) continue;

			if (agent.Params.UpdateFlags.HasFlag(.Separation))
				ApplySeparation(agent, i);
		}

		// Phase 6: Integrate constrained to navmesh
		for (int32 i = 0; i < mMaxAgents; i++)
		{
			let agent = mAgents[i];
			if (!agent.Active || agent.State != .Walking) continue;

			// Clamp speed
			float speed = Math.Sqrt(agent.Velocity[0] * agent.Velocity[0] + agent.Velocity[2] * agent.Velocity[2]);
			if (speed > agent.Params.MaxSpeed && speed > 0.0001f)
			{
				float scale = agent.Params.MaxSpeed / speed;
				agent.Velocity[0] *= scale;
				agent.Velocity[2] *= scale;
			}

			if (speed < 0.0001f)
			{
				CheckArrival(agent);
				continue;
			}

			// Compute desired position
			float[3] desiredPos;
			desiredPos[0] = agent.Position[0] + agent.Velocity[0] * dt;
			desiredPos[1] = agent.Position[1] + agent.Velocity[1] * dt;
			desiredPos[2] = agent.Position[2] + agent.Velocity[2] * dt;

			// Move along navmesh surface (constrained, won't cross wall edges)
			if (agent.CurrentPoly.IsValid)
			{
				float[3] resultPos;
				let visited = scope List<PolyRef>();
				if (mQuery.MoveAlongSurface(agent.CurrentPoly, agent.Position, desiredPos,
					mFilter, out resultPos, visited) == .Success)
				{
					agent.Position = resultPos;
					// Update current poly to the last visited
					if (visited.Count > 0)
						agent.CurrentPoly = visited[visited.Count - 1];
				}
			}

			// Check if reached target
			CheckArrival(agent);
		}
	}

	/// Processes pending move requests by computing paths.
	private void ProcessMoveRequests()
	{
		for (int32 i = 0; i < mMaxAgents; i++)
		{
			let agent = mAgents[i];
			if (!agent.Active) continue;
			if (agent.MoveRequestState != .Pending) continue;

			if (!agent.CurrentPoly.IsValid || !agent.TargetRef.IsValid)
			{
				agent.MoveRequestState = .Failed;
				continue;
			}

			// Compute path
			let path = scope List<PolyRef>();
			let status = mQuery.FindPath(agent.CurrentPoly, agent.TargetRef,
				agent.Position, agent.TargetPosition, mFilter, path);

			if (status.Succeeded && path.Count > 0)
			{
				agent.Corridor.SetCorridor(agent.TargetPosition, path);
				agent.MoveRequestState = .Valid;
				agent.State = .Walking;
			}
			else
			{
				agent.MoveRequestState = .Failed;
			}
		}
	}

	/// Updates the agent's position on the navmesh corridor.
	private void UpdateAgentPosition(CrowdAgent agent)
	{
		if (!agent.CurrentPoly.IsValid) return;

		// Move position along corridor
		agent.Corridor.MovePosition(agent.Position, mQuery, mFilter);
	}

	/// Finds nearby agents within collision query range.
	private void FindNeighbors(CrowdAgent agent, int32 agentIdx)
	{
		agent.Neighbors.Clear();
		float rangeSq = agent.Params.CollisionQueryRange * agent.Params.CollisionQueryRange;

		for (int32 i = 0; i < mMaxAgents; i++)
		{
			if (i == agentIdx) continue;
			let other = mAgents[i];
			if (!other.Active) continue;

			float distSq = agent.DistanceSqTo(other.Position);
			if (distSq < rangeSq && agent.Neighbors.Count < CrowdAgent.MaxNeighbors)
			{
				CrowdNeighbor n;
				n.AgentIndex = i;
				n.DistanceSq = distSq;
				agent.Neighbors.Add(n);
			}
		}

		// Sort by distance
		agent.Neighbors.Sort(scope (a, b) => a.DistanceSq <=> b.DistanceSq);
	}

	/// Computes the desired velocity toward the next corridor target.
	private void ComputeDesiredVelocity(CrowdAgent agent)
	{
		float[3] target = agent.Corridor.Target;

		float dx = target[0] - agent.Position[0];
		float dz = target[2] - agent.Position[2];
		float dist = Math.Sqrt(dx * dx + dz * dz);

		if (dist < 0.01f)
		{
			agent.DesiredVelocity = default;
			return;
		}

		float speed = Math.Min(agent.Params.MaxSpeed, dist / 0.4f); // Slow down near target
		agent.DesiredVelocity[0] = dx / dist * speed;
		agent.DesiredVelocity[1] = 0;
		agent.DesiredVelocity[2] = dz / dist * speed;
	}

	/// Applies obstacle avoidance to compute actual velocity.
	private void ApplyAvoidance(CrowdAgent agent, int32 agentIdx)
	{
		mAvoidanceQuery.Reset();

		// Add neighbor agents as circle obstacles
		for (let neighbor in agent.Neighbors)
		{
			let other = mAgents[neighbor.AgentIndex];
			mAvoidanceQuery.AddCircle(other.Position, other.Params.Radius,
				other.Velocity, other.DesiredVelocity);
		}

		// Sample velocity
		int32 quality = Math.Min((int32)agent.Params.AvoidanceQuality, 3);
		float[3] resultVel;
		mAvoidanceQuery.SampleVelocityAdaptive(
			agent.Position, agent.Params.Radius, agent.Params.MaxSpeed,
			agent.Velocity, agent.DesiredVelocity,
			mAvoidanceParams[quality], out resultVel);

		agent.Velocity = resultVel;
	}

	/// Applies separation force to avoid clumping.
	private void ApplySeparation(CrowdAgent agent, int32 agentIdx)
	{
		if (agent.Neighbors.Count == 0) return;

		float[3] separation = default;
		float weight = agent.Params.SeparationWeight;

		for (let neighbor in agent.Neighbors)
		{
			let other = mAgents[neighbor.AgentIndex];
			float dx = agent.Position[0] - other.Position[0];
			float dz = agent.Position[2] - other.Position[2];
			float dist = Math.Sqrt(dx * dx + dz * dz);

			float combinedRadius = agent.Params.Radius + other.Params.Radius;
			if (dist < combinedRadius && dist > 0.001f)
			{
				// Push away proportional to overlap
				float overlap = (combinedRadius - dist) / combinedRadius;
				separation[0] += (dx / dist) * overlap * weight;
				separation[2] += (dz / dist) * overlap * weight;
			}
		}

		agent.Velocity[0] += separation[0];
		agent.Velocity[2] += separation[2];
	}

	/// Checks if the agent has reached its target.
	private void CheckArrival(CrowdAgent agent)
	{
		if (agent.State != .Walking) return;
		if (!agent.TargetRef.IsValid) return;

		float dx = agent.TargetPosition[0] - agent.Position[0];
		float dz = agent.TargetPosition[2] - agent.Position[2];
		float distSq = dx * dx + dz * dz;

		// Arrived within agent radius
		if (distSq < agent.Params.Radius * agent.Params.Radius)
		{
			agent.State = .Idle;
			agent.Velocity = default;
			agent.DesiredVelocity = default;
		}
	}
}
