namespace Platformer.Enemies;

using System;
using Sedulous.Mathematics;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Platformer.Components;
using Platformer.Data;

/// Updates enemy behavior each frame.
class EnemyBehavior
{
	private Scene mScene;

	public this(Scene scene)
	{
		mScene = scene;
	}

	/// Update all enemies for one timestep.
	public void Update(Span<EntityId> enemies, float dt, Vector3 playerPos)
	{
		for (let entity in enemies)
		{
			var enemy = mScene.GetComponent<EnemyComponent>(entity);
			if (enemy == null || !enemy.Alive)
				continue;

			var transform = mScene.GetTransform(entity);
			var pos = transform.Position;

			switch (enemy.Type)
			{
			case .Slime:
				UpdatePatrol(enemy, ref pos, dt);
			case .Crab:
				UpdatePatrol(enemy, ref pos, dt);
			case .Bee:
				UpdateFlyingPatrol(enemy, ref pos, dt);
			case .Skull:
				UpdateChase(enemy, ref pos, dt, playerPos);
			}

			// Update facing direction
			if (enemy.Direction > 0)
				transform.Rotation = Quaternion.Identity;
			else
				transform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), Math.PI_f);

			transform.Position = pos;
			mScene.SetTransform(entity, transform);
			mScene.SetComponent<EnemyComponent>(entity, *enemy);
		}
	}

	private void UpdatePatrol(EnemyComponent* enemy, ref Vector3 pos, float dt)
	{
		pos.X += enemy.Direction * enemy.Speed * dt;

		// Reverse at patrol boundaries
		if (pos.X <= enemy.PatrolLeft)
		{
			pos.X = enemy.PatrolLeft;
			enemy.Direction = 1.0f;
		}
		else if (pos.X >= enemy.PatrolRight)
		{
			pos.X = enemy.PatrolRight;
			enemy.Direction = -1.0f;
		}
	}

	private void UpdateFlyingPatrol(EnemyComponent* enemy, ref Vector3 pos, float dt)
	{
		// Horizontal patrol
		pos.X += enemy.Direction * enemy.Speed * dt;
		if (pos.X <= enemy.PatrolLeft)
		{
			pos.X = enemy.PatrolLeft;
			enemy.Direction = 1.0f;
		}
		else if (pos.X >= enemy.PatrolRight)
		{
			pos.X = enemy.PatrolRight;
			enemy.Direction = -1.0f;
		}

		// Sine wave vertical motion
		enemy.Phase += dt * 3.0f;
		pos.Y = enemy.BaseY + Math.Sin(enemy.Phase) * 1.5f;
	}

	private void UpdateChase(EnemyComponent* enemy, ref Vector3 pos, float dt, Vector3 playerPos)
	{
		float distX = playerPos.X - pos.X;
		float distY = playerPos.Y - pos.Y;
		float dist = Math.Sqrt(distX * distX + distY * distY);

		if (dist < enemy.ChaseRange && dist > 0.1f)
		{
			// Chase player
			float dirX = distX / dist;
			float dirY = distY / dist;
			pos.X += dirX * enemy.Speed * dt;
			pos.Y += dirY * enemy.Speed * dt;
			enemy.Direction = dirX > 0 ? 1.0f : -1.0f;
		}
		else
		{
			// Float in place with gentle bob
			enemy.Phase += dt * 2.0f;
			pos.Y = enemy.BaseY + Math.Sin(enemy.Phase) * 0.5f;
		}
	}

	/// Check if player is stomping on an enemy (player above, moving downward).
	/// Returns true if this is a stomp (player should bounce, enemy should die).
	public static bool IsStompingEnemy(Vector3 playerPos, Vector3 playerVel, Vector3 enemyPos, EnemyType type)
	{
		// Skull cannot be stomped
		if (type == .Skull)
			return false;

		float dx = Math.Abs(playerPos.X - enemyPos.X);
		float dy = playerPos.Y - enemyPos.Y;

		// Player must be above enemy and moving downward
		return dx < 0.6f && dy > 0.2f && dy < 1.2f && playerVel.Y < 0;
	}

	/// Check if player is touching an enemy (overlap for damage).
	public static bool IsTouchingEnemy(Vector3 playerPos, Vector3 enemyPos)
	{
		float dx = Math.Abs(playerPos.X - enemyPos.X);
		float dy = Math.Abs(playerPos.Y - enemyPos.Y);
		return dx < 0.55f && dy < 0.7f;
	}
}
