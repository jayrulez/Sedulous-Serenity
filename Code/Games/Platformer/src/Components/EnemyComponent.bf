namespace Platformer.Components;

using System;
using Sedulous.Mathematics;
using Platformer.Data;
using Sedulous.Framework.Scenes;

struct EnemyComponent : IComponent
{
	public void Dispose() mut { }

	/// Enemy type determines behavior.
	public EnemyType Type;
	/// Whether this enemy is alive.
	public bool Alive = true;
	/// Movement direction (+1 right, -1 left).
	public float Direction = 1.0f;
	/// Movement speed.
	public float Speed = 2.0f;
	/// Left patrol boundary (world X).
	public float PatrolLeft;
	/// Right patrol boundary (world X).
	public float PatrolRight;
	/// Base Y position (for flying enemies' sine wave).
	public float BaseY;
	/// Phase timer for sine wave patterns.
	public float Phase = 0;
	/// Chase range for Skull enemies.
	public float ChaseRange = 8.0f;

	public static EnemyComponent Create(EnemyType type, float patrolLeft, float patrolRight, float baseY)
	{
		float speed;
		switch (type)
		{
		case .Slime: speed = 2.0f;
		case .Bee: speed = 2.5f;
		case .Crab: speed = 3.5f;
		case .Skull: speed = 2.0f;
		}

		return .()
		{
			Type = type,
			Alive = true,
			Direction = 1.0f,
			Speed = speed,
			PatrolLeft = patrolLeft,
			PatrolRight = patrolRight,
			BaseY = baseY,
			Phase = 0,
			ChaseRange = 8.0f
		};
	}
}
