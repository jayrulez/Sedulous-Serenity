using System;

namespace Sedulous.Navigation.Crowd;

/// Circle obstacle for velocity obstacle sampling.
[CRepr]
struct AvoidanceCircle
{
	public float[3] Position;
	public float Radius;
	public float[3] Velocity;
	public float[3] DesiredVelocity;
}

/// Segment obstacle for velocity obstacle sampling.
[CRepr]
struct AvoidanceSegment
{
	public float[3] P;
	public float[3] Q;
}

/// Implements velocity obstacle (VO) sampling for local collision avoidance.
/// Samples velocities around the desired velocity and scores them by
/// collision risk, velocity preference, and smoothness.
class ObstacleAvoidanceQuery
{
	private AvoidanceCircle[32] mCircles;
	private int32 mCircleCount;
	private AvoidanceSegment[32] mSegments;
	private int32 mSegmentCount;

	/// Resets all obstacles for a new query.
	public void Reset()
	{
		mCircleCount = 0;
		mSegmentCount = 0;
	}

	/// Adds a circular obstacle (another agent).
	public void AddCircle(float[3] position, float radius, float[3] velocity, float[3] desiredVelocity)
	{
		if (mCircleCount >= 32) return;
		ref AvoidanceCircle c = ref mCircles[mCircleCount++];
		c.Position = position;
		c.Radius = radius;
		c.Velocity = velocity;
		c.DesiredVelocity = desiredVelocity;
	}

	/// Adds a wall segment obstacle.
	public void AddSegment(float[3] p, float[3] q)
	{
		if (mSegmentCount >= 32) return;
		ref AvoidanceSegment s = ref mSegments[mSegmentCount++];
		s.P = p;
		s.Q = q;
	}

	/// Samples velocities adaptively around the desired velocity and returns
	/// the best avoidance velocity.
	public bool SampleVelocityAdaptive(
		float[3] position, float radius, float maxSpeed,
		float[3] currentVelocity, float[3] desiredVelocity,
		in ObstacleAvoidanceParams @params,
		out float[3] resultVelocity)
	{
		resultVelocity = desiredVelocity;

		if (mCircleCount == 0 && mSegmentCount == 0)
			return true; // No obstacles, use desired velocity directly

		float bestScore = float.MaxValue;
		float[3] bestVel = desiredVelocity;

		// Adaptive sampling: sample in rings around desired velocity
		int32 divs = (int32)@params.AdaptiveDivs;
		int32 rings = (int32)@params.AdaptiveRings;
		int32 depth = (int32)@params.AdaptiveDepth;

		if (divs < 2) divs = 2;
		if (rings < 1) rings = 1;
		if (depth < 1) depth = 1;

		float[3] center = desiredVelocity;
		float sampleRadius = maxSpeed;

		for (int32 d = 0; d < depth; d++)
		{
			// Sample points in rings
			for (int32 r = 0; r <= rings; r++)
			{
				float ringRadius = (r == 0) ? 0 : (sampleRadius * (float)r / (float)rings);

				int32 samplesInRing = (r == 0) ? 1 : divs;
				for (int32 s = 0; s < samplesInRing; s++)
				{
					float angle = (float)s / (float)samplesInRing * Math.PI_f * 2.0f;
					float[3] sampleVel;
					if (r == 0)
					{
						sampleVel = center;
					}
					else
					{
						sampleVel[0] = center[0] + Math.Cos(angle) * ringRadius;
						sampleVel[1] = 0;
						sampleVel[2] = center[2] + Math.Sin(angle) * ringRadius;
					}

					// Clamp to max speed
					float speed = Math.Sqrt(sampleVel[0] * sampleVel[0] + sampleVel[2] * sampleVel[2]);
					if (speed > maxSpeed && speed > 0.0001f)
					{
						float scale = maxSpeed / speed;
						sampleVel[0] *= scale;
						sampleVel[2] *= scale;
					}

					float score = ScoreVelocity(position, radius, sampleVel,
						currentVelocity, desiredVelocity, @params);

					if (score < bestScore)
					{
						bestScore = score;
						bestVel = sampleVel;
					}
				}
			}

			// For next depth iteration, narrow the search around best
			center = bestVel;
			sampleRadius *= 0.5f;
		}

		resultVelocity = bestVel;
		return bestScore < float.MaxValue;
	}

	/// Scores a candidate velocity based on collision risk and preference.
	/// Lower score = better velocity.
	private float ScoreVelocity(
		float[3] position, float radius,
		float[3] candidateVel,
		float[3] currentVel, float[3] desiredVel,
		in ObstacleAvoidanceParams @params)
	{
		// Check time-to-collision with each circle
		float minToi = @params.HorizTime;
		for (int32 i = 0; i < mCircleCount; i++)
		{
			float toi = ComputeTimeToCollision(position, radius, candidateVel,
				mCircles[i].Position, mCircles[i].Radius, mCircles[i].Velocity);
			if (toi < minToi)
				minToi = toi;
		}

		// Check time-to-collision with segments
		for (int32 i = 0; i < mSegmentCount; i++)
		{
			float toi = ComputeTimeToSegment(position, radius, candidateVel,
				mSegments[i].P, mSegments[i].Q);
			if (toi < minToi)
				minToi = toi;
		}

		// If immediate collision, penalize heavily
		if (minToi < 0.01f)
			return float.MaxValue;

		// Score components
		float dvx = desiredVel[0] - candidateVel[0];
		float dvz = desiredVel[2] - candidateVel[2];
		float desVelDist = Math.Sqrt(dvx * dvx + dvz * dvz);

		float cvx = currentVel[0] - candidateVel[0];
		float cvz = currentVel[2] - candidateVel[2];
		float curVelDist = Math.Sqrt(cvx * cvx + cvz * cvz);

		// Side score (prefer velocities that don't cut across the desired direction)
		float sideScore = 0;
		float desSpeed = Math.Sqrt(desiredVel[0] * desiredVel[0] + desiredVel[2] * desiredVel[2]);
		if (desSpeed > 0.001f)
		{
			// Cross product gives side preference
			float cross = candidateVel[0] * desiredVel[2] - candidateVel[2] * desiredVel[0];
			sideScore = Math.Abs(cross) / desSpeed;
		}

		// TOI score (prefer velocities with more clearance)
		float toiScore = 1.0f / (0.1f + minToi / @params.HorizTime);

		// Weighted combination
		float score = @params.WeightDesVel * desVelDist +
			@params.WeightCurVel * curVelDist +
			@params.WeightSide * sideScore +
			@params.WeightToi * toiScore;

		return score;
	}

	/// Computes time-to-collision between two moving circles.
	private float ComputeTimeToCollision(
		float[3] posA, float radiusA, float[3] velA,
		float[3] posB, float radiusB, float[3] velB)
	{
		// Relative position and velocity
		float dx = posB[0] - posA[0];
		float dz = posB[2] - posA[2];
		float dvx = velA[0] - velB[0];
		float dvz = velA[2] - velB[2];

		float combinedRadius = radiusA + radiusB;
		float a = dvx * dvx + dvz * dvz;
		float b = -2.0f * (dx * dvx + dz * dvz);
		float c = dx * dx + dz * dz - combinedRadius * combinedRadius;

		if (c < 0) return 0; // Already overlapping

		if (a < 0.0001f) return float.MaxValue; // No relative motion

		float disc = b * b - 4.0f * a * c;
		if (disc < 0) return float.MaxValue; // No collision

		float t = (-b - Math.Sqrt(disc)) / (2.0f * a);
		if (t < 0) return float.MaxValue; // Collision in the past

		return t;
	}

	/// Computes time-to-collision with a wall segment.
	private float ComputeTimeToSegment(
		float[3] position, float radius, float[3] velocity,
		float[3] segP, float[3] segQ)
	{
		// Segment direction
		float sx = segQ[0] - segP[0];
		float sz = segQ[2] - segP[2];
		float segLen = Math.Sqrt(sx * sx + sz * sz);
		if (segLen < 0.001f) return float.MaxValue;

		// Segment normal (perpendicular, pointing left)
		float nx = -sz / segLen;
		float nz = sx / segLen;

		// Distance from agent to segment line
		float dx = position[0] - segP[0];
		float dz = position[2] - segP[2];
		float dist = dx * nx + dz * nz;

		// Velocity component toward the segment
		float velToward = -(velocity[0] * nx + velocity[2] * nz);
		if (velToward <= 0.001f) return float.MaxValue; // Moving away

		float t = (dist - radius) / velToward;
		if (t < 0) return 0; // Already penetrating

		// Check if collision point is within segment bounds
		float hitX = position[0] + velocity[0] * t;
		float hitZ = position[2] + velocity[2] * t;
		float projLen = ((hitX - segP[0]) * sx + (hitZ - segP[2]) * sz) / (segLen * segLen);
		if (projLen < 0 || projLen > 1.0f)
			return float.MaxValue; // Misses segment

		return t;
	}
}
