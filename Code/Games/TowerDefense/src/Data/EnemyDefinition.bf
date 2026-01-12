namespace TowerDefense.Data;

using System;
using Sedulous.Mathematics;

/// Definition of an enemy type.
/// Contains stats and visual properties.
struct EnemyDefinition
{
	/// Enemy display name.
	public String Name;

	/// Maximum health points.
	public float MaxHealth;

	/// Movement speed (units per second).
	public float Speed;

	/// Money reward when killed.
	public int32 Reward;

	/// Damage dealt to player when reaching exit.
	public int32 Damage;

	/// Enemy type (Ground or Air).
	public EnemyType Type;

	/// Visual scale multiplier.
	public float Scale;

	/// Color for placeholder rendering.
	public Vector4 Color;

	/// Creates a basic ground enemy definition.
	public static EnemyDefinition BasicTank => .()
	{
		Name = "Basic Tank",
		MaxHealth = 50.0f,
		Speed = 3.0f,
		Reward = 10,
		Damage = 1,
		Type = .Ground,
		Scale = 0.8f,
		Color = .(0.6f, 0.4f, 0.2f, 1.0f)  // Brown
	};

	/// Creates a fast ground enemy definition.
	public static EnemyDefinition FastTank => .()
	{
		Name = "Fast Tank",
		MaxHealth = 30.0f,
		Speed = 5.0f,
		Reward = 15,
		Damage = 1,
		Type = .Ground,
		Scale = 0.6f,
		Color = .(0.2f, 0.6f, 0.2f, 1.0f)  // Green
	};

	/// Creates an armored ground enemy definition.
	public static EnemyDefinition ArmoredTank => .()
	{
		Name = "Armored Tank",
		MaxHealth = 150.0f,
		Speed = 2.0f,
		Reward = 25,
		Damage = 2,
		Type = .Ground,
		Scale = 1.0f,
		Color = .(0.5f, 0.5f, 0.5f, 1.0f)  // Gray
	};

	/// Creates a flying enemy definition.
	public static EnemyDefinition Helicopter => .()
	{
		Name = "Helicopter",
		MaxHealth = 40.0f,
		Speed = 4.0f,
		Reward = 20,
		Damage = 1,
		Type = .Air,
		Scale = 0.7f,
		Color = .(1.0f, 0.9f, 0.2f, 1.0f)  // Yellow (air unit)
	};

	/// Creates a boss enemy definition.
	public static EnemyDefinition BossTank => .()
	{
		Name = "Boss Tank",
		MaxHealth = 500.0f,
		Speed = 1.5f,
		Reward = 100,
		Damage = 5,
		Type = .Ground,
		Scale = 1.5f,
		Color = .(0.8f, 0.2f, 0.2f, 1.0f)  // Red
	};
}
