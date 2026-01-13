using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.Engine.Core;

/// Manages entity lifecycle and storage for a scene.
/// Handles index reuse with generation counters to detect stale references.
class EntityManager
{
	private Scene mScene;
	private List<Entity> mEntities = new .() ~ DeleteContainerAndItems!(_);
	private List<uint32> mGenerations = new .() ~ delete _;
	private List<uint32> mFreeIndices = new .() ~ delete _;
	private List<EntityId> mPendingDeletions = new .() ~ delete _;
	private bool mIsUpdating = false;
	private uint32 mNextIndex = 1; // 0 is reserved for invalid

	/// Gets the number of active entities.
	public int EntityCount => mEntities.Count - mFreeIndices.Count - 1; // -1 for reserved index 0

	/// Creates a new EntityManager for the given scene.
	public this(Scene scene)
	{
		mScene = scene;
		// Reserve index 0 (invalid)
		mEntities.Add(null);
		mGenerations.Add(0);
	}

	/// Creates a new entity with the given name.
	public Entity CreateEntity(StringView name)
	{
		uint32 index;
		uint32 generation;

		if (mFreeIndices.Count > 0)
		{
			// Reuse a free index
			index = mFreeIndices.PopBack();
			generation = mGenerations[index];
		}
		else
		{
			// Allocate a new index
			index = mNextIndex++;
			generation = 0;
			mGenerations.Add(generation);
			mEntities.Add(null);
		}

		let id = EntityId(index, generation);
		let entity = new Entity(id, mScene, name);
		mEntities[index] = entity;

		return entity;
	}

	/// Destroys an entity by its ID.
	/// If called during Update, deletion is deferred until end of frame.
	/// Returns true if the entity will be destroyed (or was destroyed immediately).
	public bool DestroyEntity(EntityId id)
	{
		if (!IsValid(id))
			return false;

		// If we're in the middle of updating, defer the deletion
		if (mIsUpdating)
		{
			// Check if already pending
			if (!mPendingDeletions.Contains(id))
				mPendingDeletions.Add(id);
			return true;
		}

		return DestroyEntityImmediate(id);
	}

	/// Immediately destroys an entity (internal use).
	private bool DestroyEntityImmediate(EntityId id)
	{
		if (!IsValid(id))
			return false;

		let entity = mEntities[id.Index];
		if (entity == null)
			return false;

		// Detach from parent
		if (entity.ParentId.IsValid)
		{
			if (let parent = GetEntity(entity.ParentId))
				parent.RemoveChild(id);
		}

		// Destroy children recursively - copy list since DestroyEntity modifies it
		List<EntityId> childrenToDestroy = scope .();
		childrenToDestroy.AddRange(entity.ChildIds);
		for (let childId in childrenToDestroy)
			DestroyEntityImmediate(childId);

		// Clean up entity
		delete entity;
		mEntities[id.Index] = null;

		// Increment generation and mark index as free
		mGenerations[id.Index]++;
		mFreeIndices.Add(id.Index);

		return true;
	}

	/// Flushes all pending entity deletions.
	/// Called automatically at the end of Update.
	public void FlushPendingDeletions()
	{
		for (let id in mPendingDeletions)
			DestroyEntityImmediate(id);
		mPendingDeletions.Clear();
	}

	/// Gets an entity by its ID.
	/// Returns null if the entity doesn't exist or the ID is stale.
	public Entity GetEntity(EntityId id)
	{
		if (!IsValid(id))
			return null;
		return mEntities[id.Index];
	}

	/// Checks if an entity ID is valid (exists and not stale).
	public bool IsValid(EntityId id)
	{
		if (!id.IsValid || id.Index >= mEntities.Count)
			return false;
		return mGenerations[id.Index] == id.Generation && mEntities[id.Index] != null;
	}

	/// Sets the parent of an entity.
	public void SetParent(EntityId childId, EntityId parentId)
	{
		let child = GetEntity(childId);
		if (child == null)
			return;

		// Remove from old parent
		if (child.ParentId.IsValid)
		{
			if (let oldParent = GetEntity(child.ParentId))
				oldParent.RemoveChild(childId);
		}

		// Add to new parent
		child.ParentId = parentId;
		if (parentId.IsValid)
		{
			if (let newParent = GetEntity(parentId))
				newParent.AddChild(childId);
		}
	}

	/// Updates all entity transforms, propagating from roots to children.
	public void UpdateTransforms()
	{
		// First pass: find root entities and update their world matrices
		for (let entity in mEntities)
		{
			if (entity == null)
				continue;

			if (!entity.ParentId.IsValid)
			{
				// Root entity: world matrix equals local matrix
				entity.Transform.UpdateWorldMatrix();
				UpdateChildTransforms(entity);
			}
		}
	}

	/// Recursively updates child entity transforms.
	private void UpdateChildTransforms(Entity parent)
	{
		let parentWorld = parent.Transform.WorldMatrix;

		for (let childId in parent.ChildIds)
		{
			if (let child = GetEntity(childId))
			{
				child.Transform.UpdateWorldMatrix(parentWorld);
				UpdateChildTransforms(child);
			}
		}
	}

	/// Updates all entities.
	/// Entity deletions during update are deferred until end of frame.
	public void Update(float deltaTime)
	{
		UpdateTransforms();

		mIsUpdating = true;
		for (let entity in mEntities)
		{
			// Check entity is still valid (may have been marked for deletion)
			if (entity != null && !mPendingDeletions.Contains(entity.Id))
				entity.Update(deltaTime);
		}
		mIsUpdating = false;

		// Process deferred deletions
		FlushPendingDeletions();
	}

	/// Gets an enumerator over all valid entities.
	public EntityEnumerator GetEnumerator()
	{
		return .(mEntities);
	}

	/// Enumerator for iterating over valid entities.
	public struct EntityEnumerator : IEnumerator<Entity>
	{
		private List<Entity> mEntities;
		private int mIndex;

		public this(List<Entity> entities)
		{
			mEntities = entities;
			mIndex = -1;
		}

		public Result<Entity> GetNext() mut
		{
			while (++mIndex < mEntities.Count)
			{
				if (mEntities[mIndex] != null)
					return .Ok(mEntities[mIndex]);
			}
			return .Err;
		}
	}
}
