namespace Sedulous.Framework.Core.Scenes;

using System;
using System.Collections;

/// Type-safe storage for components of type T.
/// Uses sparse storage with entity index as key for efficient lookup.
/// Tracks generation to detect stale entity references.
class ComponentStorage<T> : IComponentStorage where T : struct
{
	/// Maps entity index to component data.
	private Dictionary<uint32, T> mComponents = new .() ~ delete _;

	/// Maps entity index to generation (for stale detection).
	private Dictionary<uint32, uint32> mGenerations = new .() ~ delete _;

	/// Gets the number of components in this storage.
	public int Count => mComponents.Count;

	/// Adds or replaces a component for an entity.
	public void Set(EntityId entity, T component)
	{
		mComponents[entity.Index] = component;
		mGenerations[entity.Index] = entity.Generation;
	}

	/// Gets a pointer to the component for an entity.
	/// Returns null if entity doesn't have this component or the ID is stale.
	public T* Get(EntityId entity)
	{
		if (mGenerations.TryGetValue(entity.Index, let gen) && gen == entity.Generation)
		{
			if (mComponents.ContainsKey(entity.Index))
				return &mComponents[entity.Index];
		}
		return null;
	}

	/// Gets a reference to the component (asserts if not found).
	public ref T GetRef(EntityId entity)
	{
		Runtime.Assert(Has(entity), "Entity does not have component");
		return ref mComponents[entity.Index];
	}

	/// Checks if an entity has this component with matching generation.
	public bool Has(EntityId entity)
	{
		return mGenerations.TryGetValue(entity.Index, let gen) &&
			gen == entity.Generation &&
			mComponents.ContainsKey(entity.Index);
	}

	/// Removes the component for an entity.
	public void Remove(EntityId entity)
	{
		mComponents.Remove(entity.Index);
		mGenerations.Remove(entity.Index);
	}

	/// Called when an entity is destroyed.
	public void OnEntityDestroyed(EntityId entity)
	{
		Remove(entity);
	}

	/// Clears all components.
	public void Clear()
	{
		mComponents.Clear();
		mGenerations.Clear();
	}

	/// Gets an enumerator over all entities with this component.
	public ComponentEnumerator GetEnumerator()
	{
		return .(this);
	}

	/// Enumerator for iterating over entities with this component.
	public struct ComponentEnumerator : IEnumerator<(EntityId entity, T* component)>
	{
		private Dictionary<uint32, T>.Enumerator mEnumerator;
		private ComponentStorage<T> mStorage;

		public this(ComponentStorage<T> storage)
		{
			mStorage = storage;
			mEnumerator = storage.mComponents.GetEnumerator();
		}

		public Result<(EntityId entity, T* component)> GetNext() mut
		{
			while (mEnumerator.GetNext() case .Ok(let pair))
			{
				if (mStorage.mGenerations.TryGetValue(pair.key, let gen))
				{
					let id = EntityId(pair.key, gen);
					// Get pointer to the value in the dictionary
					if (mStorage.mComponents.ContainsKey(pair.key))
						return .Ok((id, &mStorage.mComponents[pair.key]));
				}
			}
			return .Err;
		}
	}
}
