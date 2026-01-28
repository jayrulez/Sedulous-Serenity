namespace TowerDefense.Components;

using System;
using System.Collections;
using Sedulous.Mathematics;
using TowerDefense.Data;

/// Simple data class for enemy info used in callbacks.
/// Note: Enemy state is managed by EnemyFactory using EnemyData internally.
/// This class exists for compatibility with event delegates that expect enemy info.
class EnemyComponent
{
	/// The enemy definition (stats).
	public EnemyDefinition Definition;

	/// Total distance traveled (for targeting priority).
	public float DistanceTraveled = 0.0f;

	/// Whether this enemy is active (for targeting).
	public bool IsActive = true;

	/// Creates a new EnemyComponent.
	public this()
	{
	}

	/// Creates a new EnemyComponent with the given definition.
	public this(EnemyDefinition definition)
	{
		Definition = definition;
	}
}
