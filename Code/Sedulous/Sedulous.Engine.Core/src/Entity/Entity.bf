using System;
using System.Collections;

namespace Sedulous.Engine.Core;

/// An entity in the scene with a transform and optional components.
/// Entities form a hierarchy through parent-child relationships.
class Entity
{
	private EntityId mId;
	private Scene mScene;
	private String mName ~ delete _;
	private EntityId mParentId = .Invalid;
	private List<EntityId> mChildIds = new .() ~ delete _;
	private List<IEntityComponent> mComponents = new .();

	public ~this()
	{
		// Call OnDetach on all components before deleting them
		// This ensures proper cleanup (e.g., render proxy removal)
		for (let component in mComponents)
			component.OnDetach();
		DeleteContainerAndItems!(mComponents);
	}

	/// The entity's transform (position, rotation, scale).
	public Transform Transform = .Identity;

	/// Gets the entity's unique identifier.
	public EntityId Id => mId;

	/// Gets the scene this entity belongs to.
	public Scene Scene => mScene;

	/// Gets the entity's name.
	public StringView Name => mName;

	/// Gets or sets the parent entity ID.
	public EntityId ParentId
	{
		get => mParentId;
		set => mParentId = value;
	}

	/// Gets the list of child entity IDs.
	public List<EntityId> ChildIds => mChildIds;

	/// Creates a new entity with the given ID, scene, and name.
	public this(EntityId id, Scene scene, StringView name)
	{
		mId = id;
		mScene = scene;
		mName = new String(name);
	}

	/// Adds a component to this entity.
	/// Returns the component for chaining.
	public T AddComponent<T>(T component) where T : IEntityComponent
	{
		mComponents.Add(component);
		component.OnAttach(this);
		return component;
	}

	/// Gets a component of the specified type.
	/// Returns null if the component is not found.
	public T GetComponent<T>() where T : IEntityComponent, class
	{
		for (let component in mComponents)
		{
			if (component.GetType() == typeof(T) || component.GetType().IsSubtypeOf(typeof(T)))
				return (T)component;
		}
		return null;
	}

	/// Checks if this entity has a component of the specified type.
	public bool HasComponent<T>() where T : IEntityComponent
	{
		for (let component in mComponents)
		{
			if (component.GetType() == typeof(T) || component.GetType().IsSubtypeOf(typeof(T)))
				return true;
		}
		return false;
	}

	/// Removes a component of the specified type.
	/// Returns true if a component was removed.
	public bool RemoveComponent<T>() where T : IEntityComponent, class, delete
	{
		for (int i = 0; i < mComponents.Count; i++)
		{
			let component = mComponents[i];
			if (component.GetType() == typeof(T) || component.GetType().IsSubtypeOf(typeof(T)))
			{
				component.OnDetach();
				mComponents.RemoveAt(i);
				delete (T)component;
				return true;
			}
		}
		return false;
	}

	/// Gets all components attached to this entity.
	public List<IEntityComponent> Components => mComponents;

	/// Updates all components on this entity.
	public void Update(float deltaTime)
	{
		for (let component in mComponents)
			component.OnUpdate(deltaTime);
	}

	/// Sets the entity's name.
	public void SetName(StringView name)
	{
		mName.Set(name);
	}

	/// Adds a child entity ID to this entity's children list.
	public void AddChild(EntityId childId)
	{
		mChildIds.Add(childId);
	}

	/// Removes a child entity ID from this entity's children list.
	public bool RemoveChild(EntityId childId)
	{
		return mChildIds.Remove(childId);
	}
}
