namespace Sedulous.Framework.Scenes;

/// Marker interface for component storage containers.
/// Each component type has its own storage instance managed by the scene.
interface IComponentStorage
{
	/// Removes the component for the given entity if it exists.
	void Remove(EntityId entity);

	/// Checks if the entity has this component.
	bool Has(EntityId entity);

	/// Called when an entity is destroyed to clean up its component.
	void OnEntityDestroyed(EntityId entity);

	/// Clears all components from this storage.
	void Clear();

	/// Gets the number of components in this storage.
	int Count { get; }
}
