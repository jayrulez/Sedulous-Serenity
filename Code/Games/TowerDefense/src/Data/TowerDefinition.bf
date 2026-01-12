namespace TowerDefense.Data;

using System;
using Sedulous.Mathematics;

/// Definition of a tower type.
/// Contains stats, costs, and visual properties.
struct TowerDefinition
{
	/// Tower display name.
	public String Name;

	/// Cost to build this tower.
	public int32 Cost;

	/// Cost to upgrade this tower.
	public int32 UpgradeCost;

	/// Damage per shot.
	public float Damage;

	/// Attack range in world units.
	public float Range;

	/// Shots per second.
	public float FireRate;

	/// Projectile travel speed.
	public float ProjectileSpeed;

	/// What this tower can target.
	public TowerTargetType TargetType;

	/// Visual scale multiplier.
	public float Scale;

	/// Base color for placeholder rendering.
	public Vector4 Color;

	/// Projectile color.
	public Vector4 ProjectileColor;

	/// Cannon Tower - Basic balanced tower.
	public static TowerDefinition Cannon => .()
	{
		Name = "Cannon",
		Cost = 100,
		UpgradeCost = 150,
		Damage = 25.0f,
		Range = 5.0f,
		FireRate = 1.0f,
		ProjectileSpeed = 15.0f,
		TargetType = .Ground,
		Scale = 1.0f,
		Color = .(0.5f, 0.5f, 0.5f, 1.0f),       // Gray
		ProjectileColor = .(0.3f, 0.3f, 0.3f, 1.0f)
	};

	/// Archer Tower - Fast attack, lower damage.
	public static TowerDefinition Archer => .()
	{
		Name = "Archer",
		Cost = 80,
		UpgradeCost = 120,
		Damage = 15.0f,
		Range = 6.0f,
		FireRate = 2.0f,
		ProjectileSpeed = 20.0f,
		TargetType = .Both,
		Scale = 0.9f,
		Color = .(0.4f, 0.6f, 0.3f, 1.0f),       // Green
		ProjectileColor = .(0.6f, 0.4f, 0.2f, 1.0f)
	};

	/// Slow Tower - Slows enemies, low damage.
	public static TowerDefinition SlowTower => .()
	{
		Name = "Frost",
		Cost = 150,
		UpgradeCost = 200,
		Damage = 5.0f,
		Range = 4.0f,
		FireRate = 0.5f,
		ProjectileSpeed = 12.0f,
		TargetType = .Both,
		Scale = 1.0f,
		Color = .(0.3f, 0.5f, 0.8f, 1.0f),       // Blue
		ProjectileColor = .(0.5f, 0.7f, 1.0f, 1.0f)
	};

	/// Splash Tower - Area damage.
	public static TowerDefinition Splash => .()
	{
		Name = "Mortar",
		Cost = 200,
		UpgradeCost = 300,
		Damage = 20.0f,
		Range = 4.5f,
		FireRate = 0.8f,
		ProjectileSpeed = 10.0f,
		TargetType = .Ground,
		Scale = 1.2f,
		Color = .(0.6f, 0.3f, 0.2f, 1.0f),       // Brown/Red
		ProjectileColor = .(0.8f, 0.4f, 0.1f, 1.0f)
	};

	/// Anti-Air Tower - Only targets air.
	public static TowerDefinition AntiAir => .()
	{
		Name = "SAM",
		Cost = 120,
		UpgradeCost = 180,
		Damage = 30.0f,
		Range = 7.0f,
		FireRate = 1.5f,
		ProjectileSpeed = 25.0f,
		TargetType = .Air,
		Scale = 1.0f,
		Color = .(0.7f, 0.7f, 0.2f, 1.0f),       // Yellow
		ProjectileColor = .(1.0f, 0.8f, 0.2f, 1.0f)
	};
}
