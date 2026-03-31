namespace Sedulous.UI;

using System;

/// Reusable momentum/inertia physics for scroll flings.
/// Value-type struct — no allocation.
public struct MomentumHelper
{
	public float VelocityX;
	public float VelocityY;
	public float Friction;
	public float StopThreshold;

	public this()
	{
		VelocityX = 0;
		VelocityY = 0;
		Friction = 5.0f;
		StopThreshold = 0.5f;
	}

	public this(float friction, float stopThreshold)
	{
		VelocityX = 0;
		VelocityY = 0;
		Friction = friction;
		StopThreshold = stopThreshold;
	}

	/// Apply an impulse (additive).
	public void ApplyImpulse(float vx, float vy) mut
	{
		VelocityX += vx;
		VelocityY += vy;
	}

	/// Set velocity directly.
	public void SetVelocity(float vx, float vy) mut
	{
		VelocityX = vx;
		VelocityY = vy;
	}

	/// Stop all momentum immediately.
	public void Stop() mut
	{
		VelocityX = 0;
		VelocityY = 0;
	}

	/// Whether momentum is active (non-zero velocity).
	public bool IsActive => Math.Abs(VelocityX) > StopThreshold || Math.Abs(VelocityY) > StopThreshold;

	/// Update momentum for this frame. Returns (dx, dy) position delta.
	public (float dx, float dy) Update(float deltaTime) mut
	{
		if (!IsActive)
		{
			VelocityX = 0;
			VelocityY = 0;
			return (0f, 0f);
		}

		// Exponential decay
		float decay = 1.0f - Math.Min(Friction * deltaTime, 1.0f);
		VelocityX *= decay;
		VelocityY *= decay;

		// Snap to zero below threshold
		if (Math.Abs(VelocityX) < StopThreshold) VelocityX = 0;
		if (Math.Abs(VelocityY) < StopThreshold) VelocityY = 0;

		float dx = VelocityX * deltaTime;
		float dy = VelocityY * deltaTime;
		return (dx, dy);
	}
}
