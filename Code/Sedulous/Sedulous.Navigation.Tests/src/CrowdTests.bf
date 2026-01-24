using System;
using System.Collections;
using Sedulous.Navigation;
using Sedulous.Navigation.Recast;
using Sedulous.Navigation.Detour;
using Sedulous.Navigation.Crowd;

namespace Sedulous.Navigation.Tests;

/// Tests for crowd simulation: agents, obstacle avoidance, crowd manager.
class CrowdTests
{
	// --- Helper ---

	/// Builds a flat plane navmesh and crowd manager for crowd tests.
	private static void BuildCrowdTestSetup(out NavMesh navMesh, out CrowdManager crowd)
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		navMesh = result.NavMesh;
		crowd = new CrowdManager();
		crowd.Init(navMesh);
	}

	// --- CrowdAgent Tests ---

	[Test]
	public static void TestCrowdAgentConstruction()
	{
		let agent = scope CrowdAgent();
		Test.Assert(!agent.Active, "New agent should be inactive");
		Test.Assert(agent.State == .Invalid, "New agent should be in Invalid state");
		Test.Assert(!agent.CurrentPoly.IsValid, "New agent should have null poly");
		Test.Assert(agent.MoveRequestState == .None, "New agent should have no move request");
	}

	[Test]
	public static void TestCrowdAgentReset()
	{
		let agent = scope CrowdAgent();
		agent.Active = true;
		agent.State = .Walking;
		agent.Position = .(1, 2, 3);
		agent.Velocity = .(4, 5, 6);

		agent.Reset();

		Test.Assert(!agent.Active, "Reset agent should be inactive");
		Test.Assert(agent.State == .Invalid, "Reset agent should be Invalid");
		Test.Assert(agent.Position[0] == 0 && agent.Position[1] == 0 && agent.Position[2] == 0, "Reset agent position should be zero");
		Test.Assert(agent.Velocity[0] == 0 && agent.Velocity[1] == 0 && agent.Velocity[2] == 0, "Reset agent velocity should be zero");
	}

	[Test]
	public static void TestCrowdAgentIntegrate()
	{
		let agent = scope CrowdAgent();
		agent.State = .Walking;
		agent.Position = .(1, 0, 1);
		agent.Velocity = .(2, 0, 3);

		agent.Integrate(0.5f);

		Test.Assert(Math.Abs(agent.Position[0] - 2.0f) < 0.001f, "X should be 1 + 2*0.5 = 2");
		Test.Assert(Math.Abs(agent.Position[2] - 2.5f) < 0.001f, "Z should be 1 + 3*0.5 = 2.5");
	}

	[Test]
	public static void TestCrowdAgentDistanceSq()
	{
		let agent = scope CrowdAgent();
		agent.Position = .(1, 0, 0);

		float[3] other = .(4, 0, 0);
		float distSq = agent.DistanceSqTo(other);
		Test.Assert(Math.Abs(distSq - 9.0f) < 0.001f, "Distance squared should be 9");
	}

	// --- ObstacleAvoidanceQuery Tests ---

	[Test]
	public static void TestAvoidanceQueryReset()
	{
		let query = scope ObstacleAvoidanceQuery();
		float[3] pos = .(0, 0, 0);
		float[3] vel = .(1, 0, 0);
		query.AddCircle(pos, 0.5f, vel, vel);
		query.AddSegment(pos, .(1, 0, 0));

		query.Reset();

		// After reset, sampling with no obstacles should return desired velocity
		float[3] desVel = .(1, 0, 0);
		float[3] resultVel;
		let @params = ObstacleAvoidanceParams.Low;
		bool ok = query.SampleVelocityAdaptive(pos, 0.5f, 3.0f, vel, desVel, @params, out resultVel);
		Test.Assert(ok, "Should succeed with no obstacles after reset");
		Test.Assert(Math.Abs(resultVel[0] - 1.0f) < 0.001f, "Should return desired velocity X");
		Test.Assert(Math.Abs(resultVel[2] - 0.0f) < 0.001f, "Should return desired velocity Z");
	}

	[Test]
	public static void TestAvoidanceQueryNoObstacles()
	{
		let query = scope ObstacleAvoidanceQuery();
		float[3] pos = .(0, 0, 0);
		float[3] curVel = .(1, 0, 0);
		float[3] desVel = .(2, 0, 0);
		float[3] resultVel;

		let @params = ObstacleAvoidanceParams.Low;
		bool ok = query.SampleVelocityAdaptive(pos, 0.5f, 5.0f, curVel, desVel, @params, out resultVel);

		Test.Assert(ok, "Should succeed with no obstacles");
		Test.Assert(Math.Abs(resultVel[0] - desVel[0]) < 0.001f, "Should return desired velocity when no obstacles");
	}

	[Test]
	public static void TestAvoidanceQueryWithObstacle()
	{
		let query = scope ObstacleAvoidanceQuery();
		float[3] agentPos = .(0, 0, 0);
		float[3] agentVel = .(0, 0, 0);
		float[3] desVel = .(3, 0, 0); // Want to go +X

		// Place obstacle directly ahead
		float[3] obsPos = .(3, 0, 0);
		float[3] obsVel = .(0, 0, 0);
		query.AddCircle(obsPos, 1.0f, obsVel, obsVel);

		float[3] resultVel;
		let @params = ObstacleAvoidanceParams.Medium;
		query.SampleVelocityAdaptive(agentPos, 0.5f, 3.5f, agentVel, desVel, @params, out resultVel);

		// The result velocity should differ from the desired (avoidance applied)
		float dx = resultVel[0] - desVel[0];
		float dz = resultVel[2] - desVel[2];
		float diff = Math.Sqrt(dx * dx + dz * dz);
		Test.Assert(diff > 0.01f || Math.Abs(resultVel[2]) > 0.01f,
			"Avoidance should modify velocity when obstacle is ahead");
	}

	// --- CrowdManager Tests ---

	[Test]
	public static void TestCrowdManagerInit()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let crowd = scope CrowdManager();
		let status = crowd.Init(result.NavMesh);

		Test.Assert(status == .Success, "Crowd init should succeed");
		Test.Assert(crowd.MaxAgents == 128, "Default max agents should be 128");
		Test.Assert(crowd.ActiveAgentCount == 0, "Should start with 0 active agents");
	}

	[Test]
	public static void TestCrowdAddAgent()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		float[3] pos = .(0, 0, 0);
		let @params = CrowdAgentParams.Default;
		int32 idx = crowd.AddAgent(pos, @params);

		Test.Assert(idx >= 0, "AddAgent should return valid index");
		Test.Assert(crowd.ActiveAgentCount == 1, "Should have 1 active agent");

		let agent = crowd.GetAgent(idx);
		Test.Assert(agent != null, "Should be able to get agent");
		Test.Assert(agent.Active, "Agent should be active");
		Test.Assert(agent.State == .Idle, "New agent should be idle");
	}

	[Test]
	public static void TestCrowdRemoveAgent()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		float[3] pos = .(0, 0, 0);
		let @params = CrowdAgentParams.Default;
		int32 idx = crowd.AddAgent(pos, @params);

		crowd.RemoveAgent(idx);

		Test.Assert(crowd.ActiveAgentCount == 0, "Should have 0 active agents after removal");
		Test.Assert(crowd.GetAgent(idx) == null, "Removed agent should return null");
	}

	[Test]
	public static void TestCrowdMultipleAgents()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		let @params = CrowdAgentParams.Default;
		int32 idx0 = crowd.AddAgent(.(-2, 0, 0), @params);
		int32 idx1 = crowd.AddAgent(.(0, 0, 0), @params);
		int32 idx2 = crowd.AddAgent(.(2, 0, 0), @params);

		Test.Assert(idx0 >= 0 && idx1 >= 0 && idx2 >= 0, "All agents should be added");
		Test.Assert(idx0 != idx1 && idx1 != idx2, "Agents should have different indices");
		Test.Assert(crowd.ActiveAgentCount == 3, "Should have 3 active agents");
	}

	[Test]
	public static void TestCrowdGetAgentInvalid()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		Test.Assert(crowd.GetAgent(-1) == null, "Negative index should return null");
		Test.Assert(crowd.GetAgent(0) == null, "Unused index should return null");
		Test.Assert(crowd.GetAgent(999) == null, "Out of range index should return null");
	}

	[Test]
	public static void TestCrowdRequestMoveTarget()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		float[3] pos = .(0, 0, 0);
		let @params = CrowdAgentParams.Default;
		int32 idx = crowd.AddAgent(pos, @params);

		float[3] targetPos = .(3, 0, 3);
		bool ok = crowd.RequestMovePosition(idx, targetPos);
		Test.Assert(ok, "Move request should succeed");

		let agent = crowd.GetAgent(idx);
		Test.Assert(agent.MoveRequestState == .Pending, "Move request should be pending");
	}

	[Test]
	public static void TestCrowdRequestMoveInvalidAgent()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		float[3] targetPos = .(3, 0, 3);
		bool ok = crowd.RequestMovePosition(99, targetPos);
		Test.Assert(!ok, "Move request for invalid agent should fail");
	}

	[Test]
	public static void TestCrowdUpdateProcessesMoveRequest()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		float[3] startPos = .(-2, 0, -2);
		let @params = CrowdAgentParams.Default;
		int32 idx = crowd.AddAgent(startPos, @params);

		float[3] targetPos = .(2, 0, 2);
		crowd.RequestMovePosition(idx, targetPos);

		// One update should process the move request
		crowd.Update(0.016f);

		let agent = crowd.GetAgent(idx);
		Test.Assert(agent.MoveRequestState == .Valid || agent.MoveRequestState == .Failed,
			"Move request should be processed after update");
		if (agent.MoveRequestState == .Valid)
			Test.Assert(agent.State == .Walking, "Agent should be walking after valid move request");
	}

	[Test]
	public static void TestCrowdAgentMovesTowardTarget()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		float[3] startPos = .(-2, 0, 0);
		var agentParams = CrowdAgentParams.Default;
		agentParams.UpdateFlags = .None; // Disable avoidance/separation for cleaner test
		int32 idx = crowd.AddAgent(startPos, agentParams);

		float[3] targetPos = .(2, 0, 0);
		crowd.RequestMovePosition(idx, targetPos);

		// Run multiple updates
		for (int32 i = 0; i < 10; i++)
			crowd.Update(0.1f);

		let agent = crowd.GetAgent(idx);
		// Agent should have moved toward the target (X increased)
		Test.Assert(agent.Position[0] > startPos[0] + 0.1f,
			"Agent should move toward target (X should increase)");
	}

	[Test]
	public static void TestCrowdAgentReachesTarget()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		float[3] startPos = .(0, 0, 0);
		var agentParams = CrowdAgentParams.Default;
		agentParams.UpdateFlags = .None;
		agentParams.MaxSpeed = 5.0f;
		int32 idx = crowd.AddAgent(startPos, agentParams);

		// Target very close - agent should arrive quickly
		float[3] targetPos = .(1, 0, 0);
		crowd.RequestMovePosition(idx, targetPos);

		// Run enough updates for agent to reach a close target
		for (int32 i = 0; i < 100; i++)
			crowd.Update(0.05f);

		let agent = crowd.GetAgent(idx);
		Test.Assert(agent.State == .Idle, "Agent should be idle after reaching target");
	}

	[Test]
	public static void TestCrowdAgentSpeedClamped()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		float[3] startPos = .(-3, 0, 0);
		var agentParams = CrowdAgentParams.Default;
		agentParams.UpdateFlags = .None;
		agentParams.MaxSpeed = 2.0f;
		int32 idx = crowd.AddAgent(startPos, agentParams);

		float[3] targetPos = .(3, 0, 0);
		crowd.RequestMovePosition(idx, targetPos);

		crowd.Update(0.1f);

		let agent = crowd.GetAgent(idx);
		float speed = Math.Sqrt(agent.Velocity[0] * agent.Velocity[0] + agent.Velocity[2] * agent.Velocity[2]);
		Test.Assert(speed <= agentParams.MaxSpeed + 0.01f,
			"Agent speed should not exceed MaxSpeed");
	}

	[Test]
	public static void TestCrowdSeparation()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		// Place two agents very close together
		var agentParams = CrowdAgentParams.Default;
		agentParams.UpdateFlags = .Separation;
		agentParams.Radius = 0.5f;
		agentParams.SeparationWeight = 5.0f;

		float[3] pos1 = .(0, 0, 0);
		float[3] pos2 = .(0.3f, 0, 0); // Within combined radius
		int32 idx0 = crowd.AddAgent(pos1, agentParams);
		int32 idx1 = crowd.AddAgent(pos2, agentParams);

		// Give them both a move target so they're walking
		float[3] target = .(0, 0, 3);
		crowd.RequestMovePosition(idx0, target);
		crowd.RequestMovePosition(idx1, target);

		// Run a few updates
		for (int32 i = 0; i < 5; i++)
			crowd.Update(0.05f);

		let agent0 = crowd.GetAgent(idx0);
		let agent1 = crowd.GetAgent(idx1);

		// After separation, agents should have moved apart in X
		float dist = Math.Abs(agent0.Position[0] - agent1.Position[0]);
		Test.Assert(dist > 0.3f, "Separation should push agents apart");
	}

	[Test]
	public static void TestCrowdUpdateZeroDt()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		float[3] pos = .(0, 0, 0);
		let @params = CrowdAgentParams.Default;
		int32 idx = crowd.AddAgent(pos, @params);

		float[3] target = .(3, 0, 0);
		crowd.RequestMovePosition(idx, target);

		// Zero dt should not crash and should not move agent
		crowd.Update(0.0f);

		let agent = crowd.GetAgent(idx);
		Test.Assert(agent.MoveRequestState == .Pending, "Zero dt should not process requests");
	}

	[Test]
	public static void TestCrowdObstacleAvoidance()
	{
		NavMesh navMesh;
		CrowdManager crowd;
		BuildCrowdTestSetup(out navMesh, out crowd);
		defer { delete navMesh; delete crowd; }

		var agentParams = CrowdAgentParams.Default;
		agentParams.UpdateFlags = .ObstacleAvoidance;
		agentParams.Radius = 0.5f;
		agentParams.AvoidanceQuality = 2;

		// Agent A moving +X
		int32 idxA = crowd.AddAgent(.(-3, 0, 0), agentParams);
		crowd.RequestMovePosition(idxA, .(3, 0, 0));

		// Agent B stationary in the path
		crowd.AddAgent(.(0, 0, 0), agentParams);

		// Run updates
		for (int32 i = 0; i < 20; i++)
			crowd.Update(0.05f);

		let agentA = crowd.GetAgent(idxA);
		// Agent A should have moved (not stuck)
		Test.Assert(agentA.Position[0] > -2.5f, "Agent should move even with obstacle");
	}

	[Test]
	public static void TestObstacleAvoidanceParamsLow()
	{
		let p = ObstacleAvoidanceParams.Low;
		Test.Assert(p.AdaptiveDivs == 5, "Low quality should have 5 divs");
		Test.Assert(p.AdaptiveRings == 2, "Low quality should have 2 rings");
		Test.Assert(p.AdaptiveDepth == 1, "Low quality should have 1 depth");
		Test.Assert(p.WeightToi == 2.5f, "WeightToi should be 2.5");
	}

	[Test]
	public static void TestObstacleAvoidanceParamsMedium()
	{
		let p = ObstacleAvoidanceParams.Medium;
		Test.Assert(p.AdaptiveDivs == 7, "Medium quality should have 7 divs");
		Test.Assert(p.AdaptiveRings == 2, "Medium quality should have 2 rings");
		Test.Assert(p.AdaptiveDepth == 3, "Medium quality should have 3 depth");
	}
}
