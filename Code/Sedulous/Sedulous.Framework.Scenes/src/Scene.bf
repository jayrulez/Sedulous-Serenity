namespace Sedulous.Framework.Scenes;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Framework.Scenes.Internal;

/// A data-oriented scene containing entities, transforms, and components.
/// The scene is the single source of truth and owns all entity data.
public class Scene : IDisposable
{
	// ========== Entity Storage ==========
	private List<uint32> mGenerations = new .() ~ delete _;
	private List<bool> mEntityActive = new .() ~ delete _;
	private List<int32> mFreeList = new .() ~ delete _;
	private int32 mActiveCount = 0;

	// ========== Transform Storage ==========
	private List<TransformData> mTransforms = new .() ~ delete _;
	private Dictionary<uint32, List<EntityId>> mChildren = new .() ~ DeleteDictionaryAndValues!(_);

	// ========== Component Storage ==========
	private Dictionary<Type, IComponentStorage> mComponentStorages = new .() ~ DeleteDictionaryAndValues!(_);

	// ========== Modules ==========
	private List<ISceneModule> mModules = new .() ~ DeleteContainerAndItems!(_);

	// ========== Deferred Commands ==========
	private List<EntityId> mPendingDestructions = new .() ~ delete _;
	private bool mIsUpdating = false;

	// ========== Scene State ==========
	private String mName ~ delete _;
	private SceneState mState = .Unloaded;

	/// Gets the scene name.
	public StringView Name => mName;

	/// Gets the current scene state.
	public SceneState State => mState;

	/// Gets the number of active entities.
	public int32 EntityCount => mActiveCount;

	/// Creates a new scene with the given name.
	public this(StringView name)
	{
		mName = new String(name);
	}

	/// Disposes the scene and all its resources.
	public void Dispose()
	{
		// Notify modules of destruction
		for (let module in mModules)
			module.OnSceneDestroy(this);

		// Clear all data
		for (let storage in mComponentStorages.Values)
			storage.Clear();

		// Delete children lists before clearing
		for (let list in mChildren.Values)
			delete list;
		mChildren.Clear();
		mTransforms.Clear();
		mGenerations.Clear();
		mEntityActive.Clear();
		mFreeList.Clear();
		mPendingDestructions.Clear();
		mActiveCount = 0;
	}

	// ==================== Entity Management ====================

	/// Creates a new entity with an identity transform.
	public EntityId CreateEntity()
	{
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			// Reuse a freed slot
			index = (uint32)mFreeList.PopBack();
			generation = mGenerations[(int)index];
		}
		else
		{
			// Allocate a new slot
			index = (uint32)mGenerations.Count;
			mGenerations.Add(1);
			mEntityActive.Add(false);
			mTransforms.Add(.());
			generation = 1;
		}

		// Initialize the entity
		mEntityActive[(int)index] = true;
		mTransforms[(int)index] = .();
		mActiveCount++;

		return EntityId(index, generation);
	}

	/// Queues an entity for destruction.
	/// If called during an update, destruction is deferred to the end of the frame.
	/// Otherwise, destruction happens immediately.
	public void DestroyEntity(EntityId entity)
	{
		if (!IsValid(entity))
			return;

		if (mIsUpdating)
		{
			// Defer destruction until end of frame
			if (!mPendingDestructions.Contains(entity))
				mPendingDestructions.Add(entity);
		}
		else
		{
			DestroyEntityImmediate(entity);
		}
	}

	/// Checks if an entity ID is valid (exists and generation matches).
	public bool IsValid(EntityId entity)
	{
		if (!entity.IsValid || entity.Index >= mGenerations.Count)
			return false;
		return mGenerations[(int)entity.Index] == entity.Generation &&
			mEntityActive[(int)entity.Index];
	}

	/// Internal: destroys an entity immediately.
	private void DestroyEntityImmediate(EntityId entity)
	{
		if (!IsValid(entity))
			return;

		let index = (int)entity.Index;

		// Notify modules
		for (let module in mModules)
			module.OnEntityDestroyed(this, entity);

		// Recursively destroy children
		if (mChildren.TryGetValue(entity.Index, let children))
		{
			// Copy list since we're modifying it
			let childrenCopy = scope List<EntityId>();
			childrenCopy.AddRange(children);
			for (let childId in childrenCopy)
				DestroyEntityImmediate(childId);

			delete children;
			mChildren.Remove(entity.Index);
		}

		// Detach from parent
		let parentId = mTransforms[index].Parent;
		if (parentId.IsValid && mChildren.TryGetValue(parentId.Index, let parentChildren))
			parentChildren.Remove(entity);

		// Remove all components
		for (let storage in mComponentStorages.Values)
			storage.OnEntityDestroyed(entity);

		// Mark as inactive and increment generation for next use
		mEntityActive[index] = false;
		mGenerations[index]++;
		mFreeList.Add((int32)entity.Index);
		mActiveCount--;
	}

	// ==================== Transform Management ====================

	/// Gets the local transform for an entity.
	public Transform GetTransform(EntityId entity)
	{
		Runtime.Assert(IsValid(entity), "Invalid entity");
		return mTransforms[(int)entity.Index].Local;
	}

	/// Gets a pointer to the local transform (null if invalid).
	public Transform* GetTransformPtr(EntityId entity)
	{
		if (!IsValid(entity))
			return null;
		return &mTransforms[(int)entity.Index].Local;
	}

	/// Sets the local position.
	public void SetPosition(EntityId entity, Vector3 position)
	{
		if (!IsValid(entity))
			return;
		ref TransformData data = ref mTransforms[(int)entity.Index];
		data.Local.Position = position;
		MarkTransformDirty(ref data, entity);
	}

	/// Sets the local rotation.
	public void SetRotation(EntityId entity, Quaternion rotation)
	{
		if (!IsValid(entity))
			return;
		ref TransformData data = ref mTransforms[(int)entity.Index];
		data.Local.Rotation = rotation;
		MarkTransformDirty(ref data, entity);
	}

	/// Sets the local scale.
	public void SetScale(EntityId entity, Vector3 scale)
	{
		if (!IsValid(entity))
			return;
		ref TransformData data = ref mTransforms[(int)entity.Index];
		data.Local.Scale = scale;
		MarkTransformDirty(ref data, entity);
	}

	/// Sets the full local transform.
	public void SetTransform(EntityId entity, Transform transform)
	{
		if (!IsValid(entity))
			return;
		ref TransformData data = ref mTransforms[(int)entity.Index];
		data.Local = transform;
		MarkTransformDirty(ref data, entity);
	}

	/// Marks a transform and its children as dirty.
	private void MarkTransformDirty(ref TransformData data, EntityId entity)
	{
		data.LocalDirty = true;
		data.WorldDirty = true;
		PropagateWorldDirty(entity);
	}

	/// Gets the cached world matrix (valid after transform update phase).
	public Matrix GetWorldMatrix(EntityId entity)
	{
		Runtime.Assert(IsValid(entity), "Invalid entity");
		return mTransforms[(int)entity.Index].WorldMatrix;
	}

	/// Gets the cached local matrix.
	public Matrix GetLocalMatrix(EntityId entity)
	{
		Runtime.Assert(IsValid(entity), "Invalid entity");
		return mTransforms[(int)entity.Index].LocalMatrix;
	}

	/// Sets the parent of an entity. Pass EntityId.Invalid to make it a root entity.
	public void SetParent(EntityId entity, EntityId parent)
	{
		if (!IsValid(entity))
			return;

		// Can't parent to self
		if (entity == parent)
			return;

		// Can't parent to invalid entity (unless making root)
		if (parent.IsValid && !IsValid(parent))
			return;

		let index = (int)entity.Index;
		let oldParent = mTransforms[index].Parent;

		// No change
		if (oldParent == parent)
			return;

		// Remove from old parent's children
		if (oldParent.IsValid && mChildren.TryGetValue(oldParent.Index, let oldChildren))
			oldChildren.Remove(entity);

		// Set new parent
		mTransforms[index].Parent = parent;
		mTransforms[index].WorldDirty = true;

		// Add to new parent's children
		if (parent.IsValid)
		{
			if (!mChildren.TryGetValue(parent.Index, let children))
			{
				let newList = new List<EntityId>();
				mChildren[parent.Index] = newList;
				newList.Add(entity);
			}
			else
			{
				children.Add(entity);
			}
		}

		PropagateWorldDirty(entity);
	}

	/// Gets the parent of an entity.
	public EntityId GetParent(EntityId entity)
	{
		if (!IsValid(entity))
			return .Invalid;
		return mTransforms[(int)entity.Index].Parent;
	}

	/// Gets the children of an entity.
	public void GetChildren(EntityId entity, List<EntityId> outChildren)
	{
		outChildren.Clear();
		if (!IsValid(entity))
			return;
		if (mChildren.TryGetValue(entity.Index, let children))
			outChildren.AddRange(children);
	}

	/// Checks if an entity has any children.
	public bool HasChildren(EntityId entity)
	{
		if (!IsValid(entity))
			return false;
		if (mChildren.TryGetValue(entity.Index, let children))
			return children.Count > 0;
		return false;
	}

	/// Propagates world dirty flag to all children.
	private void PropagateWorldDirty(EntityId entity)
	{
		if (!mChildren.TryGetValue(entity.Index, let children))
			return;

		for (let childId in children)
		{
			if (IsValid(childId))
			{
				mTransforms[(int)childId.Index].WorldDirty = true;
				PropagateWorldDirty(childId);
			}
		}
	}

	/// Updates all transform hierarchies.
	private void UpdateTransformHierarchy()
	{
		// Update root entities first (those with no parent)
		for (int i = 0; i < mEntityActive.Count; i++)
		{
			if (!mEntityActive[i])
				continue;

			if (!mTransforms[i].Parent.IsValid)
			{
				UpdateEntityTransform((uint32)i, .Identity);
			}
		}
	}

	/// Recursively updates transform for an entity and its children.
	private void UpdateEntityTransform(uint32 index, Matrix parentWorld)
	{
		ref TransformData data = ref mTransforms[(int)index];

		// Update local matrix if dirty
		if (data.LocalDirty)
		{
			data.LocalMatrix = data.Local.ToMatrix();
			data.LocalDirty = false;
		}

		// Update world matrix if dirty or has parent
		if (data.WorldDirty)
		{
			if (data.Parent.IsValid)
				data.WorldMatrix = data.LocalMatrix * parentWorld;
			else
				data.WorldMatrix = data.LocalMatrix;
			data.WorldDirty = false;
		}

		// Update children
		if (mChildren.TryGetValue(index, let children))
		{
			for (let childId in children)
			{
				if (IsValid(childId))
					UpdateEntityTransform(childId.Index, data.WorldMatrix);
			}
		}
	}

	// ==================== Component Management ====================

	/// Gets or creates storage for a component type.
	private ComponentStorage<T> GetStorage<T>() where T : struct
	{
		let type = typeof(T);
		if (mComponentStorages.TryGetValue(type, let storage))
			return (ComponentStorage<T>)storage;

		let newStorage = new ComponentStorage<T>();
		mComponentStorages[type] = newStorage;
		return newStorage;
	}

	/// Adds or replaces a component on an entity.
	public void SetComponent<T>(EntityId entity, T component) where T : struct
	{
		if (!IsValid(entity))
			return;
		GetStorage<T>().Set(entity, component);
	}

	/// Gets a pointer to a component (null if entity doesn't have it).
	public T* GetComponent<T>(EntityId entity) where T : struct
	{
		if (!IsValid(entity))
			return null;
		return GetStorage<T>().Get(entity);
	}

	/// Gets a reference to a component (asserts if not found).
	public ref T GetComponentRef<T>(EntityId entity) where T : struct
	{
		Runtime.Assert(IsValid(entity), "Invalid entity");
		return ref GetStorage<T>().GetRef(entity);
	}

	/// Checks if an entity has a component.
	public bool HasComponent<T>(EntityId entity) where T : struct
	{
		if (!IsValid(entity))
			return false;
		let type = typeof(T);
		if (!mComponentStorages.TryGetValue(type, let storage))
			return false;
		return storage.Has(entity);
	}

	/// Removes a component from an entity.
	public void RemoveComponent<T>(EntityId entity) where T : struct
	{
		if (!IsValid(entity))
			return;
		let type = typeof(T);
		if (mComponentStorages.TryGetValue(type, let storage))
			storage.Remove(entity);
	}

	/// Returns an enumerator over all entities with a specific component.
	public ComponentStorage<T>.ComponentEnumerator Query<T>() where T : struct
	{
		return GetStorage<T>().GetEnumerator();
	}

	// ==================== Module Management ====================

	/// Adds a module to the scene.
	public void AddModule(ISceneModule module)
	{
		mModules.Add(module);
		module.OnSceneCreate(this);
	}

	/// Gets a module by type.
	public T GetModule<T>() where T : class, ISceneModule
	{
		let targetType = typeof(T);
		for (let module in mModules)
		{
			let moduleType = module.GetType();
			if (moduleType == targetType || moduleType.IsSubtypeOf(targetType))
				return (T)module;
		}
		return null;
	}

	/// Removes a module from the scene.
	public bool RemoveModule<T>() where T : class, ISceneModule
	{
		let targetType = typeof(T);
		for (int i = 0; i < mModules.Count; i++)
		{
			let module = mModules[i];
			let moduleType = module.GetType();
			if (moduleType == targetType || moduleType.IsSubtypeOf(targetType))
			{
				module.OnSceneDestroy(this);
				mModules.RemoveAt(i);
				delete module;
				return true;
			}
		}
		return false;
	}

	// ==================== Update Lifecycle ====================

	/// Calls FixedUpdate on all modules for deterministic simulation.
	/// Should be called from a fixed timestep loop (may be called multiple times per frame).
	public void FixedUpdate(float fixedDeltaTime)
	{
		if (mState != .Active)
			return;

		for (let module in mModules)
			module.FixedUpdate(this, fixedDeltaTime);
	}

	/// Updates the scene for one frame.
	/// Follows deterministic order: BeginFrame -> Update -> EndFrame
	/// Call PostUpdate separately after all subsystems have completed their Update phase.
	public void Update(float deltaTime)
	{
		if (mState != .Active)
			return;

		mIsUpdating = true;

		// 1. Modules.OnBeginFrame
		for (let module in mModules)
			module.OnBeginFrame(this, deltaTime);

		// 2. Modules.Update
		for (let module in mModules)
			module.Update(this, deltaTime);

		// 3. Modules.OnEndFrame
		for (let module in mModules)
			module.OnEndFrame(this);
	}

	/// Post-update phase called after all subsystems have completed their Update.
	/// Updates transform hierarchy, calls module PostUpdate, and processes deferred destructions.
	public void PostUpdate(float deltaTime)
	{
		if (mState != .Active)
			return;

		// 1. Scene updates transform hierarchy (local -> world)
		UpdateTransformHierarchy();

		// 2. Modules.PostUpdate - world matrices are now valid
		for (let module in mModules)
			module.PostUpdate(this, deltaTime);

		mIsUpdating = false;

		// 3. Process deferred entity destructions
		ProcessDeferredDestructions();
	}

	/// Processes queued entity destructions.
	private void ProcessDeferredDestructions()
	{
		for (let entityId in mPendingDestructions)
			DestroyEntityImmediate(entityId);
		mPendingDestructions.Clear();
	}

	/// Sets the scene state.
	public void SetState(SceneState newState)
	{
		if (mState == newState)
			return;

		let oldState = mState;
		mState = newState;

		for (let module in mModules)
			module.OnSceneStateChanged(this, oldState, newState);
	}

	// ==================== Entity Iteration ====================

	/// Delegate for entity iteration.
	public delegate void EntityCallback(EntityId entity);

	/// Iterates over all active entities.
	public void ForEachEntity(EntityCallback callback)
	{
		for (int i = 0; i < mEntityActive.Count; i++)
		{
			if (mEntityActive[i])
			{
				let id = EntityId((uint32)i, mGenerations[i]);
				callback(id);
			}
		}
	}
}
