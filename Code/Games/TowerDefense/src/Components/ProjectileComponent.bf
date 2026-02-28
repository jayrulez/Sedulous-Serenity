namespace TowerDefense.Components;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Foundation.Mathematics;
using TowerDefense.Data;

/// Simple reference class for legacy delegate compatibility.
/// Note: Projectile state is managed by TowerFactory using ProjectileData internally.
class ProjectileComponent
{
	public EntityId TargetId = .Invalid;
	public float Damage;
	public float Speed;

	public this()
	{
	}

	public this(EntityId target, float damage, float speed)
	{
		TargetId = target;
		Damage = damage;
		Speed = speed;
	}
}
