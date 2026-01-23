namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// Trigger event for sub-emitter spawning.
public enum SubEmitterTrigger : uint8
{
	/// Spawn child particles when a parent particle is born.
	OnBirth,

	/// Spawn child particles when a parent particle dies.
	OnDeath
}

/// Configuration for a single sub-emitter entry.
/// References a child emitter that spawns particles in response to parent events.
public struct SubEmitterEntry
{
	/// When to trigger the child emitter.
	public SubEmitterTrigger Trigger;

	/// Handle to the child particle emitter proxy.
	public ParticleEmitterProxyHandle ChildEmitter;

	/// Number of particles to spawn per event.
	public int32 SpawnCount;

	/// Probability of triggering (0-1). 1.0 = always trigger.
	public float Probability;

	/// Whether to spawn at the parent particle's position.
	public bool InheritPosition;

	/// Whether to inherit the parent particle's velocity.
	public bool InheritVelocity;

	/// Whether to inherit the parent particle's color.
	public bool InheritColor;

	/// Fraction of parent velocity to inherit [0, 1].
	public float VelocityInheritFactor;

	/// Creates a default sub-emitter entry (OnDeath, 100% probability, inherits position).
	public static Self Default()
	{
		return .()
		{
			Trigger = .OnDeath,
			ChildEmitter = .Invalid,
			SpawnCount = 1,
			Probability = 1.0f,
			InheritPosition = true,
			InheritVelocity = false,
			InheritColor = false,
			VelocityInheritFactor = 0.5f
		};
	}
}

/// A particle lifecycle event with context for sub-emitter spawning.
public struct ParticleEvent
{
	/// World position where the event occurred.
	public Vector3 Position;

	/// Velocity of the particle at event time.
	public Vector3 Velocity;

	/// Color of the particle at event time.
	public Color Color;
}

/// Maximum number of sub-emitter entries per emitter.
public static class SubEmitterConstants
{
	public const int32 MaxSubEmitters = 4;
	public const int32 MaxEventsPerFrame = 64;
}
