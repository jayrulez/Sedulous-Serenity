namespace TowerDefense.Components;

using System;
using Sedulous.Engine.Core;
using Sedulous.Foundation.Core;
using Sedulous.Serialization;
using TowerDefense.Data;

/// Component that gives an entity health and damage handling.
class HealthComponent : IEntityComponent
{
	private Entity mEntity;

	/// Maximum health points.
	public float MaxHealth = 100.0f;

	/// Current health points.
	public float CurrentHealth = 100.0f;

	/// Whether the entity is dead.
	public bool IsDead => CurrentHealth <= 0;

	/// Health as a percentage (0.0 to 1.0).
	public float HealthPercent => MaxHealth > 0 ? Math.Clamp(CurrentHealth / MaxHealth, 0.0f, 1.0f) : 0.0f;

	// Event accessors
	private EventAccessor<DamageDelegate> mOnDamaged = new .() ~ delete _;
	private EventAccessor<SimpleDelegate> mOnDeath = new .() ~ delete _;

	/// Event fired when damage is taken.
	public EventAccessor<DamageDelegate> OnDamaged => mOnDamaged;

	/// Event fired when health reaches zero.
	public EventAccessor<SimpleDelegate> OnDeath => mOnDeath;

	/// Creates a new HealthComponent with specified max health.
	public this(float maxHealth = 100.0f)
	{
		MaxHealth = maxHealth;
		CurrentHealth = maxHealth;
	}

	/// Takes damage, reducing current health.
	public void TakeDamage(float amount)
	{
		if (IsDead || amount <= 0)
			return;

		CurrentHealth = Math.Max(0.0f, CurrentHealth - amount);
		mOnDamaged.[Friend]Invoke(amount);

		if (IsDead)
		{
			mOnDeath.[Friend]Invoke();
		}
	}

	/// Heals the entity by the specified amount.
	public void Heal(float amount)
	{
		if (IsDead || amount <= 0)
			return;

		CurrentHealth = Math.Min(MaxHealth, CurrentHealth + amount);
	}

	/// Resets health to maximum.
	public void Reset()
	{
		CurrentHealth = MaxHealth;
	}

	// ==================== IEntityComponent Implementation ====================

	public void OnAttach(Entity entity)
	{
		mEntity = entity;
	}

	public void OnDetach()
	{
		mEntity = null;
	}

	public void OnUpdate(float deltaTime)
	{
		// Health doesn't need per-frame updates
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		result = serializer.Float("maxHealth", ref MaxHealth);
		if (result != .Ok)
			return result;

		result = serializer.Float("currentHealth", ref CurrentHealth);
		if (result != .Ok)
			return result;

		return .Ok;
	}
}
