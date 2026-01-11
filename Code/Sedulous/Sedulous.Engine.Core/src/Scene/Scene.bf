using System;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Resources;

namespace Sedulous.Engine.Core;

/// A scene containing entities and scene-level components.
/// Scenes can be serialized for save/load functionality.
class Scene : ISerializable
{
	private String mName ~ delete _;
	private SceneState mState = .Unloaded;
	private EntityManager mEntityManager ~ delete _;
	private ComponentRegistry mComponentRegistry;
	private Context mContext;
	private List<ISceneComponent> mSceneComponents = new .();
	private Dictionary<Type, ISceneComponent> mSceneComponentMap = new .() ~ delete _;

	public ~this()
	{
		// Call OnDetach on all scene components before deleting them
		// This ensures proper cleanup of GPU resources etc.
		for (let component in mSceneComponents)
		{
			component.OnDetach();
			delete component;
		}
		delete mSceneComponents;
	}

	/// Gets the scene name.
	public StringView Name => mName;

	/// Gets the current scene state.
	public SceneState State => mState;

	/// Gets the entity manager.
	public EntityManager EntityManager => mEntityManager;

	/// Gets the component registry.
	public ComponentRegistry ComponentRegistry => mComponentRegistry;

	/// Gets the context this scene belongs to.
	public Context Context => mContext;

	/// Creates a new scene with the given name.
	public this(StringView name, ComponentRegistry componentRegistry)
	{
		mName = new String(name);
		mEntityManager = new .(this);
		mComponentRegistry = componentRegistry;
	}

	/// Sets the scene name.
	public void SetName(StringView name)
	{
		mName.Set(name);
	}

	/// Creates an entity in this scene.
	public Entity CreateEntity(StringView name)
	{
		return mEntityManager.CreateEntity(name);
	}

	/// Destroys an entity by ID.
	public bool DestroyEntity(EntityId id)
	{
		return mEntityManager.DestroyEntity(id);
	}

	/// Gets an entity by ID.
	public Entity GetEntity(EntityId id)
	{
		return mEntityManager.GetEntity(id);
	}

	/// Adds a scene component (singleton per type).
	/// Returns the component for chaining.
	public T AddSceneComponent<T>(T component) where T : ISceneComponent
	{
		let type = typeof(T);
		if (mSceneComponentMap.ContainsKey(type))
		{
			// Already have this type - replace it
			RemoveSceneComponent<T>();
		}

		mSceneComponents.Add(component);
		mSceneComponentMap[type] = component;
		component.OnAttach(this);
		return component;
	}

	/// Gets a scene component by type.
	/// Returns null if not found.
	public T GetSceneComponent<T>() where T : ISceneComponent, class
	{
		if (mSceneComponentMap.TryGetValue(typeof(T), let component))
			return (T)component;
		return null;
	}

	/// Checks if this scene has a component of the specified type.
	public bool HasSceneComponent<T>() where T : ISceneComponent
	{
		return mSceneComponentMap.ContainsKey(typeof(T));
	}

	/// Removes a scene component by type.
	/// Returns true if a component was removed.
	public bool RemoveSceneComponent<T>() where T : ISceneComponent
	{
		if (mSceneComponentMap.TryGetValue(typeof(T), let component))
		{
			component.OnDetach();
			mSceneComponents.Remove(component);
			mSceneComponentMap.Remove(typeof(T));
			delete component;
			return true;
		}
		return false;
	}

	/// Sets the scene state.
	public void SetState(SceneState newState)
	{
		if (mState == newState)
			return;

		let oldState = mState;
		mState = newState;

		for (let component in mSceneComponents)
			component.OnSceneStateChanged(oldState, newState);
	}

	/// Updates the scene.
	public void Update(float deltaTime)
	{
		if (mState != .Active)
			return;

		// Update entity transforms first so scene components have valid world matrices
		mEntityManager.UpdateTransforms();

		// Update scene components (e.g., RenderSceneComponent syncs entity transforms to proxies)
		for (let component in mSceneComponents)
			component.OnUpdate(deltaTime);

		// Update entity components (after transforms are synced to rendering)
		for (let entity in mEntityManager)
			entity.Update(deltaTime);
	}

	// ISerializable implementation

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// Serialize scene name
		result = serializer.String("name", mName);
		if (result != .Ok)
			return result;

		// Serialize entities
		result = SerializeEntities(serializer);
		if (result != .Ok)
			return result;

		return .Ok;
	}

	private SerializationResult SerializeEntities(Serializer serializer)
	{
		if (serializer.IsWriting)
		{
			// Count entities
			int32 count = (int32)mEntityManager.EntityCount;
			var result = serializer.BeginArray("entities", ref count);
			if (result != .Ok)
				return result;

			// Build index map for parent references
			Dictionary<EntityId, int32> entityToIndex = scope .();
			int32 index = 0;
			for (let entity in mEntityManager)
			{
				entityToIndex[entity.Id] = index++;
			}

			// Serialize each entity
			for (let entity in mEntityManager)
			{
				result = serializer.BeginObject(default);
				if (result != .Ok)
					return result;

				// Name
				result = serializer.String("name", scope String(entity.Name));
				if (result != .Ok)
					return result;

				// Transform
				result = SerializeTransform(serializer, entity.Transform);
				if (result != .Ok)
					return result;

				// Parent index (-1 if no parent)
				int32 parentIndex = -1;
				if (entity.ParentId.IsValid)
				{
					if (entityToIndex.TryGetValue(entity.ParentId, let pIdx))
						parentIndex = pIdx;
				}
				result = serializer.Int32("parent", ref parentIndex);
				if (result != .Ok)
					return result;

				// Serialize components
				result = SerializeEntityComponents(serializer, entity);
				if (result != .Ok)
					return result;

				result = serializer.EndObject();
				if (result != .Ok)
					return result;
			}

			return serializer.EndArray();
		}
		else
		{
			// Reading
			int32 count = 0;
			var result = serializer.BeginArray("entities", ref count);
			if (result != .Ok)
				return result;

			// First pass: create entities and store parent indices
			List<int32> parentIndices = scope .(count);
			List<Entity> entities = scope .(count);

			for (int32 i = 0; i < count; i++)
			{
				result = serializer.BeginObject(default);
				if (result != .Ok)
					return result;

				// Name
				String name = scope .();
				result = serializer.String("name", name);
				if (result != .Ok)
					return result;

				let entity = CreateEntity(name);
				entities.Add(entity);

				// Transform
				result = DeserializeTransform(serializer, ref entity.Transform);
				if (result != .Ok)
					return result;

				// Parent index
				int32 parentIndex = -1;
				result = serializer.Int32("parent", ref parentIndex);
				if (result != .Ok)
					return result;
				parentIndices.Add(parentIndex);

				// Deserialize components
				result = DeserializeEntityComponents(serializer, entity);
				if (result != .Ok)
					return result;

				result = serializer.EndObject();
				if (result != .Ok)
					return result;
			}

			// Second pass: set up parent relationships
			for (int32 i = 0; i < count; i++)
			{
				let parentIndex = parentIndices[i];
				if (parentIndex >= 0 && parentIndex < entities.Count)
				{
					mEntityManager.SetParent(entities[i].Id, entities[parentIndex].Id);
				}
			}

			return serializer.EndArray();
		}
	}

	private SerializationResult SerializeTransform(Serializer serializer, Transform transform)
	{
		var result = serializer.BeginObject("transform");
		if (result != .Ok)
			return result;

		// Position
		float[3] pos = .(transform.Position.X, transform.Position.Y, transform.Position.Z);
		result = serializer.FixedFloatArray("position", &pos, 3);
		if (result != .Ok)
			return result;

		// Rotation (as quaternion)
		float[4] rot = .(transform.Rotation.X, transform.Rotation.Y, transform.Rotation.Z, transform.Rotation.W);
		result = serializer.FixedFloatArray("rotation", &rot, 4);
		if (result != .Ok)
			return result;

		// Scale
		float[3] scl = .(transform.Scale.X, transform.Scale.Y, transform.Scale.Z);
		result = serializer.FixedFloatArray("scale", &scl, 3);
		if (result != .Ok)
			return result;

		return serializer.EndObject();
	}

	private SerializationResult DeserializeTransform(Serializer serializer, ref Transform transform)
	{
		var result = serializer.BeginObject("transform");
		if (result != .Ok)
			return result;

		// Position
		float[3] pos = default;
		result = serializer.FixedFloatArray("position", &pos, 3);
		if (result != .Ok)
			return result;
		transform.SetPosition(.(pos[0], pos[1], pos[2]));

		// Rotation
		float[4] rot = default;
		result = serializer.FixedFloatArray("rotation", &rot, 4);
		if (result != .Ok)
			return result;
		transform.SetRotation(.(rot[0], rot[1], rot[2], rot[3]));

		// Scale
		float[3] scl = default;
		result = serializer.FixedFloatArray("scale", &scl, 3);
		if (result != .Ok)
			return result;
		transform.SetScale(.(scl[0], scl[1], scl[2]));

		return serializer.EndObject();
	}

	private SerializationResult SerializeEntityComponents(Serializer serializer, Entity entity)
	{
		int32 count = (int32)entity.Components.Count;
		var result = serializer.BeginArray("components", ref count);
		if (result != .Ok)
			return result;

		for (let component in entity.Components)
		{
			result = serializer.BeginObject(default);
			if (result != .Ok)
				return result;

			// Write type name
			String typeName = scope .();
			mComponentRegistry.GetTypeId(component, typeName);
			result = serializer.String("type", typeName);
			if (result != .Ok)
				return result;

			// Write component data
			result = component.Serialize(serializer);
			if (result != .Ok)
				return result;

			result = serializer.EndObject();
			if (result != .Ok)
				return result;
		}

		return serializer.EndArray();
	}

	private SerializationResult DeserializeEntityComponents(Serializer serializer, Entity entity)
	{
		int32 count = 0;
		var result = serializer.BeginArray("components", ref count);
		if (result != .Ok)
			return result;

		for (int32 i = 0; i < count; i++)
		{
			result = serializer.BeginObject(default);
			if (result != .Ok)
				return result;

			// Read type name
			String typeName = scope .();
			result = serializer.String("type", typeName);
			if (result != .Ok)
				return result;

			// Create component
			let component = mComponentRegistry.Create(typeName);
			if (component != null)
			{
				result = component.Serialize(serializer);
				if (result != .Ok)
				{
					delete component;
					return result;
				}
				entity.AddComponent(component);
			}

			result = serializer.EndObject();
			if (result != .Ok)
				return result;
		}

		return serializer.EndArray();
	}
}
