namespace TowerDefense.Data;

using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using TowerDefense.Components;

/// Delegate for enemy exit events.
delegate void EnemyExitDelegate(EnemyComponent enemy);

/// Delegate for enemy killed events.
delegate void EnemyKilledDelegate(Entity enemy, int32 reward);

/// Delegate for damage events.
delegate void DamageDelegate(float damage);

/// Delegate for simple events with no parameters.
delegate void SimpleDelegate();

/// Delegate for tower fire events.
delegate void TowerFireDelegate(TowerComponent tower, Entity target, Vector3 origin);

/// Delegate for projectile hit events.
delegate void ProjectileHitDelegate(Entity projectile, Entity target);
