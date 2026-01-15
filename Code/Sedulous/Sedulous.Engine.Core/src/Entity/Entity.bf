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
	private List<IEntityComponent> mPendingAdditions = new .() ~ delete _;
	private List<IEntityComponent> mPendingRemovals = new .() ~ delete _;
	private bool mIsUpdating = false;

	public ~this()
	{
		// Clean up any pending additions (they never got attached properly)
		for (let component in mPendingAdditions)
			delete component;
		mPendingAdditions.Clear();

		// Pending removals are already in mComponents, so they'll be cleaned up below
		mPendingRemovals.Clear();

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
	/// If called during Update, the addition is deferred until end of frame.
	/// Returns the component for chaining.
	public T AddComponent<T>(T component) where T : IEntityComponent
	{
		if (mIsUpdating)
		{
			// Defer addition until end of update
			mPendingAdditions.Add(component);
		}
		else
		{
			mComponents.Add(component);
			component.OnAttach(this);
		}
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
	/// If called during Update, the removal is deferred until end of frame.
	/// Returns true if a component was found (and will be removed).
	public bool RemoveComponent<T>() where T : IEntityComponent, class, delete
	{
		for (int i = 0; i < mComponents.Count; i++)
		{
			let component = mComponents[i];
			if (component.GetType() == typeof(T) || component.GetType().IsSubtypeOf(typeof(T)))
			{
				if (mIsUpdating)
				{
					// Defer removal until end of update
					if (!mPendingRemovals.Contains(component))
						mPendingRemovals.Add(component);
				}
				else
				{
					component.OnDetach();
					mComponents.RemoveAt(i);
					delete (T)component;
				}
				return true;
			}
		}
		return false;
	}

	/// Gets all components attached to this entity.
	public List<IEntityComponent> Components => mComponents;

	/// Updates all components on this entity.
	/// Component additions/removals during update are deferred until end of frame.
	public void Update(float deltaTime)
	{
		mIsUpdating = true;

		for (let component in mComponents)
		{
			// Skip components pending removal
			if (!mPendingRemovals.Contains(component))
				component.OnUpdate(deltaTime);
		}

		mIsUpdating = false;

		// Process deferred operations
		FlushPendingOperations();
	}

	/// Processes any deferred component additions/removals.
	private void FlushPendingOperations()
	{
		// Process removals first
		for (let component in mPendingRemovals)
		{
			component.OnDetach();
			mComponents.Remove(component);
			delete component;
		}
		mPendingRemovals.Clear();

		// Process additions
		for (let component in mPendingAdditions)
		{
			mComponents.Add(component);
			component.OnAttach(this);
		}
		mPendingAdditions.Clear();
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
