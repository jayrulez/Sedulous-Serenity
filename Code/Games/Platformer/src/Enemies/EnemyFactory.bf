namespace Platformer.Enemies;

using System;
using System.Collections;
using Sedulous.Foundation.Mathematics;
using Sedulous.Foundation.Logging.Abstractions;
using Sedulous.Engine.Core;
using Sedulous.Engine.Scenes;
using Platformer.Components;
using Platformer.Data;

/// Manages enemy spawning and provides access to enemy data.
class EnemyFactory
{
	private Scene mScene;
	private ILogger mLogger;

	public this(Scene scene, ILogger logger)
	{
		mScene = scene;
		mLogger = logger;
	}

	/// Gets the enemy component for an entity.
	public EnemyComponent* GetEnemy(EntityId entity)
	{
		return mScene.GetComponent<EnemyComponent>(entity);
	}

	/// Kills an enemy (marks as not alive).
	public void KillEnemy(EntityId entity)
	{
		var enemy = mScene.GetComponent<EnemyComponent>(entity);
		if (enemy != null)
		{
			mLogger?.LogDebug("Enemy killed (type={})", enemy.Type);
			enemy.Alive = false;
			mScene.SetComponent<EnemyComponent>(entity, *enemy);

			// Hide the entity by moving it far away
			var transform = mScene.GetTransform(entity);
			transform.Position.Y = -100;
			mScene.SetTransform(entity, transform);
		}
		else
		{
			mLogger?.LogWarning("KillEnemy called on entity with no EnemyComponent");
		}
	}
}
