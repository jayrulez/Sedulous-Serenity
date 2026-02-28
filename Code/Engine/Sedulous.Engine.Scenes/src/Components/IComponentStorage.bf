namespace Sedulous.Engine.Scenes;

/// Marker interface for component storage containers.
/// Each component type has its own storage instance managed by the scene.
interface IComponentStorage
{
	/// Removes the component for the given entity if it exists.
	void Remove(EntityId entity);

	/// Disposes the component (calls IDisposable.Dispose) and then removes it.
	void DisposeAndRemove(EntityId entity);

	/// Checks if the entity has this component.
	bool Has(EntityId entity);

	/// Called when an entity is destroyed to clean up its component.
	void OnEntityDestroyed(EntityId entity);

	/// Clears all components from this storage.
	void Clear();

	/// Gets the number of components in this storage.
	int Count { get; }

	/// Gets a raw pointer to the component data for an entity (null if not present).
	/// For internal/tool use only — prefer the generic GetComponent<T> API.
	void* GetRaw(EntityId entity);

	/// Sets a component from raw data. The data pointer must point to valid data of the correct type.
	/// For internal/tool use only — prefer the generic SetComponent<T> API.
	void SetRaw(EntityId entity, void* data);

	/// Adds a default-initialized component for an entity.
	/// For internal/tool use only.
	void AddDefault(EntityId entity);
}
