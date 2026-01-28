namespace TowerDefense.Data;

using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using TowerDefense.Components;

/// Delegate for enemy exit events.
delegate void EnemyExitDelegate(EnemyComponent enemy);

/// Delegate for enemy killed events.
delegate void EnemyKilledDelegate(EntityId enemy, int32 reward);

/// Delegate for damage events.
delegate void DamageDelegate(float damage);

/// Delegate for simple events with no parameters.
delegate void SimpleDelegate();

/// Delegate for tower fire events.
delegate void TowerFireDelegate(TowerDefinition def, EntityId target, Vector3 origin);

/// Delegate for projectile hit events.
delegate void ProjectileHitDelegate(EntityId projectile, EntityId target);

/// Delegate for wave started events.
delegate void WaveStartedDelegate(int32 waveNumber);

/// Delegate for wave completed events.
delegate void WaveCompletedDelegate(int32 waveNumber, int32 bonusReward);

/// Delegate for all waves completed event.
delegate void AllWavesCompletedDelegate();

/// Delegate for spawn enemy request.
delegate void SpawnEnemyDelegate(EnemyPreset enemyType);
