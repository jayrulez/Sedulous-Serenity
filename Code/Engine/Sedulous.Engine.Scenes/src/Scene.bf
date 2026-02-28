namespace Sedulous.Engine.Scenes;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Serialization;
using System.Reflection;
using Sedulous.Engine.Scenes.Internal;

using static Sedulous.Core.Mathematics.MathSerializerExtensions;

/// A data-oriented scene containing entities, transforms, and components.
/// The scene is the single source of truth and owns all entity data.
public class Scene : IDisposable, ISerializable
{
	// ========== Entity Storage ==========
	private List<uint32> mGenerations = new .() ~ delete _;
	private List<bool> mEntityActive = new .() ~ delete _;
	private List<int32> mFreeList = new .() ~ delete _;
	private int32 mActiveCount = 0;

	// ========== Transform Storage ==========
	private List<TransformData> mTransforms = new .() ~ delete _;
	private Dictionary<uint32, List<EntityId>> mChildren = new .() ~ DeleteDictionaryAndValues!(_);

	// ========== Entity Names ==========
	private Dictionary<uint32, String> mEntityNames = new .() ~ DeleteDictionaryAndValues!(_);

	// ========== Component Storage ==========
	private Dictionary<Type, IComponentStorage> mComponentStorages = new .() ~ DeleteDictionaryAndValues!(_);

	// ========== Component Serializers ==========
	private List<IComponentSerializer> mComponentSerializers = new .() ~ DeleteContainerAndItems!(_);

	// ========== Missing Component Data ==========
	private List<MissingComponentData> mMissingComponents = new .() ~ DeleteContainerAndItems!(_);

	// ========== Modules ==========
	private List<ISceneModule> mModules = new .() ~ DeleteContainerAndItems!(_);

	// ========== Module Settings ==========
	private Dictionary<Type, ISerializable> mModuleSettings = new .() ~ { for (let v in _.Values) delete v; delete _; };
	private static List<Type> sSettingsTypes ~ delete _;

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
		CreateModuleSettings();
		RegisterDiscoveredSerializers();
	}

	/// Parameterless constructor for deserialization.
	public this()
	{
		mName = new String();
		CreateModuleSettings();
		RegisterDiscoveredSerializers();
	}

	// ==================== Serialization ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		int32 sceneVersion = SerializationVersion;
		s.Int32("sceneVersion", ref sceneVersion);

		s.String("sceneName", mName);

		// Entities + transforms + hierarchy + components + modules
		if (s.IsWriting)
		{
			let entityIndexMap = scope Dictionary<uint32, int32>();
			SerializeEntitiesWrite(s, entityIndexMap);
			SerializeComponentsWrite(s, entityIndexMap);
			SerializeModulesWrite(s);
		}
		else
		{
			let loadedEntities = scope List<EntityId>();
			SerializeEntitiesRead(s, loadedEntities);
			SerializeComponentsRead(s, loadedEntities);
			SerializeModulesRead(s);
		}

		return .Ok;
	}

	private void SerializeEntitiesWrite(Serializer s, Dictionary<uint32, int32> outEntityIndexMap)
	{
		int32 entityCount = mActiveCount;
		s.Int32("entityCount", ref entityCount);

		// Build mapping from slot index to serialized index
		int32 serializedIndex = 0;
		for (int i = 0; i < mEntityActive.Count; i++)
		{
			if (mEntityActive[i])
			{
				outEntityIndexMap[(uint32)i] = serializedIndex;
				serializedIndex++;
			}
		}

		s.BeginObject("entities");
		serializedIndex = 0;
		for (int i = 0; i < mEntityActive.Count; i++)
		{
			if (!mEntityActive[i])
				continue;

			s.BeginObject(scope $"e{serializedIndex}");

			// Name
			let nameStr = scope String();
			if (mEntityNames.TryGetValue((uint32)i, let name))
				nameStr.Set(name);
			s.String("name", nameStr);

			// Transform
			var position = mTransforms[i].Local.Position;
			var rotation = mTransforms[i].Local.Rotation;
			var scale = mTransforms[i].Local.Scale;
			s.Vector3("position", ref position);
			s.Quaternion("rotation", ref rotation);
			s.Vector3("scale", ref scale);

			// Parent reference
			let parentId = mTransforms[i].Parent;
			int32 parentIndex = -1;
			if (parentId.IsValid && outEntityIndexMap.TryGetValue(parentId.Index, let mappedIndex))
				parentIndex = mappedIndex;
			s.Int32("parent", ref parentIndex);

			s.EndObject();
			serializedIndex++;
		}
		s.EndObject();
	}

	private void SerializeEntitiesRead(Serializer s, List<EntityId> outLoadedEntities)
	{
		int32 entityCount = 0;
		s.Int32("entityCount", ref entityCount);

		let parentIndices = scope List<int32>();

		s.BeginObject("entities");
		for (int32 i = 0; i < entityCount; i++)
		{
			s.BeginObject(scope $"e{i}");

			// Name
			let nameStr = scope String();
			s.String("name", nameStr);

			// Transform
			var position = Vector3.Zero;
			var rotation = Quaternion.Identity;
			var scale = Vector3(1, 1, 1);
			s.Vector3("position", ref position);
			s.Quaternion("rotation", ref rotation);
			s.Vector3("scale", ref scale);

			// Parent reference
			int32 parentIndex = -1;
			s.Int32("parent", ref parentIndex);

			s.EndObject();

			// Create entity and apply data
			let entity = CreateEntity();
			SetTransform(entity, .(position, rotation, scale));
			if (!nameStr.IsEmpty)
				SetName(entity, nameStr);

			outLoadedEntities.Add(entity);
			parentIndices.Add(parentIndex);
		}
		s.EndObject();

		// Second pass: resolve parent references
		for (int i = 0; i < outLoadedEntities.Count; i++)
		{
			let parentIdx = parentIndices[i];
			if (parentIdx >= 0 && parentIdx < outLoadedEntities.Count)
				SetParent(outLoadedEntities[i], outLoadedEntities[parentIdx]);
		}
	}

	private void SerializeComponentsWrite(Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		if (mComponentSerializers.Count == 0 && mMissingComponents.Count == 0)
			return;
		s.BeginObject("components");
		for (let serializer in mComponentSerializers)
			serializer.Write(this, s, entityIndexMap);

		// Write preserved unknown component data
		for (let missingData in mMissingComponents)
		{
			let missingSerializer = scope MissingComponentSerializer(missingData);
			missingSerializer.Write(this, s, entityIndexMap);
		}
		s.EndObject();
	}

	private void SerializeComponentsRead(Serializer s, List<EntityId> loadedEntities)
	{
		if (!s.HasField("components"))
			return;
		s.BeginObject("components");

		// Read known components
		for (let serializer in mComponentSerializers)
		{
			if (s.HasField(serializer.TypeName))
				serializer.Read(this, s, loadedEntities);
		}

		// Discover and preserve unknown component types
		let allFieldNames = scope List<String>();
		s.GetFieldNames(allFieldNames);
		defer { for (let name in allFieldNames) delete name; }

		for (let fieldName in allFieldNames)
		{
			bool known = false;
			for (let serializer in mComponentSerializers)
			{
				if (serializer.TypeName == fieldName)
				{
					known = true;
					break;
				}
			}

			if (!known)
			{
				let missingData = new MissingComponentData(fieldName);
				let missingSerializer = scope MissingComponentSerializer(missingData);
				missingSerializer.Read(this, s, loadedEntities);
				mMissingComponents.Add(missingData);
			}
		}

		s.EndObject();
	}

	private void SerializeModulesWrite(Serializer s)
	{
		if (mModuleSettings.Count == 0)
			return;

		s.BeginObject("modules");
		for (let (type, settings) in mModuleSettings)
		{
			if (type.GetCustomAttribute<ModuleSettingsAttribute>() case .Ok(let attr))
			{
				s.BeginObject(attr.Name);
				settings.Serialize(s);
				s.EndObject();
			}
		}
		s.EndObject();
	}

	private void SerializeModulesRead(Serializer s)
	{
		if (!s.HasField("modules"))
			return;

		s.BeginObject("modules");
		for (let (type, settings) in mModuleSettings)
		{
			if (type.GetCustomAttribute<ModuleSettingsAttribute>() case .Ok(let attr))
			{
				if (s.HasField(attr.Name))
				{
					s.BeginObject(attr.Name);
					settings.Serialize(s);
					s.EndObject();
				}
			}
		}
		s.EndObject();
	}

	// ==================== Module Settings ====================

	/// Discovers all types with [ModuleSettings] attribute. Called once.
	private static void DiscoverSettingsTypes()
	{
		if (sSettingsTypes != null)
			return;

		sSettingsTypes = new List<Type>();
		for (let type in Type.Types)
		{
			if (type.IsObject && type.HasCustomAttribute<ModuleSettingsAttribute>())
				sSettingsTypes.Add(type);
		}
	}

	/// Creates instances of all discovered [ModuleSettings] types.
	private void CreateModuleSettings()
	{
		DiscoverSettingsTypes();
		for (let type in sSettingsTypes)
		{
			if (type.CreateObject() case .Ok(let obj))
			{
				if (let serializable = obj as ISerializable)
					mModuleSettings[type] = serializable;
				else
					delete obj;
			}
		}
	}

	/// Gets the discovered settings types (for editor reflection).
	public static List<Type> SettingsTypes
	{
		get
		{
			DiscoverSettingsTypes();
			return sSettingsTypes;
		}
	}

	/// Gets module settings by type.
	public T GetModuleSettings<T>() where T : class, ISerializable
	{
		if (mModuleSettings.TryGetValue(typeof(T), let settings))
			return (T)settings;
		return null;
	}

	/// Gets module settings by runtime type.
	public ISerializable GetModuleSettings(Type type)
	{
		if (mModuleSettings.TryGetValue(type, let settings))
			return settings;
		return null;
	}

	// ==================== Component Serializer Auto-Discovery ====================

	private static List<Type> sSerializableComponentTypes ~ delete _;

	/// Discovers all struct types with [Component] that implement ISerializableComponent. Called once.
	private static void DiscoverSerializableComponentTypes()
	{
		if (sSerializableComponentTypes != null)
			return;

		sSerializableComponentTypes = new List<Type>();
		for (let type in Type.Types)
		{
			if (type.IsStruct && type.HasCustomAttribute<ComponentAttribute>() && type.ImplementsInterface(typeof(ISerializableComponent)))
				sSerializableComponentTypes.Add(type);
		}
	}

	/// Registers serializers for all discovered [Component] + ISerializableComponent types.
	/// Calls the comptime-generated __CreateSerializer() factory method on each type.
	private void RegisterDiscoveredSerializers()
	{
		DiscoverSerializableComponentTypes();
		for (let type in sSerializableComponentTypes)
		{
			for (let method in type.GetMethods(.Static | .Public))
			{
				if (method.Name == "__CreateSerializer")
				{
					if (method.Invoke(Variant()) case .Ok(var result))
					{
						let obj = result.Get<Object>();
						if (let serializer = obj as IComponentSerializer)
							RegisterComponentSerializer(serializer);
						else if (obj != null)
							delete obj;
					}
					break;
				}
			}
		}
	}

	/// Registers a component serializer for type T.
	/// Call this before serializing/deserializing to enable component roundtripping.
	/// Duplicate registrations (same type name) are silently ignored.
	public void RegisterComponentSerializer<T>() where T : struct, ISerializableComponent
	{
		let typeName = scope String();
		typeof(T).GetName(typeName);
		for (let existing in mComponentSerializers)
		{
			if (existing.TypeName == typeName)
				return;
		}
		mComponentSerializers.Add(new ComponentSerializer<T>());
	}

	/// Registers a custom component serializer.
	/// Duplicate registrations (same type name) are silently ignored; the duplicate is deleted.
	public void RegisterComponentSerializer(IComponentSerializer serializer)
	{
		for (let existing in mComponentSerializers)
		{
			if (existing.TypeName == serializer.TypeName)
			{
				delete serializer;
				return;
			}
		}
		mComponentSerializers.Add(serializer);
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

		// Remove name
		if (mEntityNames.TryGetValue(entity.Index, let entityName))
		{
			delete entityName;
			mEntityNames.Remove(entity.Index);
		}

		// Remove all components
		for (let storage in mComponentStorages.Values)
			storage.OnEntityDestroyed(entity);

		// Mark as inactive and increment generation for next use
		mEntityActive[index] = false;
		mGenerations[index]++;
		mFreeList.Add((int32)entity.Index);
		mActiveCount--;
	}

	// ==================== Entity Names ====================

	/// Sets the name of an entity. Pass empty string to remove the name.
	public void SetName(EntityId entity, StringView name)
	{
		if (!IsValid(entity))
			return;

		if (name.IsEmpty)
		{
			if (mEntityNames.TryGetValue(entity.Index, let existing))
			{
				delete existing;
				mEntityNames.Remove(entity.Index);
			}
			return;
		}

		if (mEntityNames.TryGetValue(entity.Index, let existing))
		{
			existing.Set(name);
		}
		else
		{
			mEntityNames[entity.Index] = new String(name);
		}
	}

	/// Gets the name of an entity. Returns empty StringView if unnamed.
	public StringView GetName(EntityId entity)
	{
		if (!IsValid(entity))
			return default;
		if (mEntityNames.TryGetValue(entity.Index, let name))
			return name;
		return default;
	}

	/// Finds the first entity with the given name.
	public EntityId FindByName(StringView name)
	{
		for (let (index, entityName) in mEntityNames)
		{
			if (entityName == name && mEntityActive[(int)index])
				return EntityId(index, mGenerations[(int)index]);
		}
		return .Invalid;
	}

	/// Finds all entities with the given name.
	public void FindAllByName(StringView name, List<EntityId> results)
	{
		for (let (index, entityName) in mEntityNames)
		{
			if (entityName == name && mEntityActive[(int)index])
				results.Add(EntityId(index, mGenerations[(int)index]));
		}
	}

	/// Finds an entity by hierarchical path (e.g. "Parent/Child/Grandchild").
	public EntityId FindByPath(StringView path)
	{
		EntityId current = .Invalid;

		for (let segment in path.Split('/'))
		{
			if (segment.IsEmpty)
				continue;

			if (!current.IsValid)
			{
				// Search root entities (no parent)
				bool found = false;
				for (let (index, entityName) in mEntityNames)
				{
					if (entityName == segment && mEntityActive[(int)index] &&
						!mTransforms[(int)index].Parent.IsValid)
					{
						current = EntityId(index, mGenerations[(int)index]);
						found = true;
						break;
					}
				}
				if (!found)
					return .Invalid;
			}
			else
			{
				// Search children of current entity
				bool found = false;
				if (mChildren.TryGetValue(current.Index, let children))
				{
					for (let childId in children)
					{
						if (IsValid(childId) && mEntityNames.TryGetValue(childId.Index, let childName) && childName == segment)
						{
							current = childId;
							found = true;
							break;
						}
					}
				}
				if (!found)
					return .Invalid;
			}
		}

		return current;
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
	private ComponentStorage<T> GetStorage<T>() where T : struct, IComponent
	{
		let type = typeof(T);
		if (mComponentStorages.TryGetValue(type, let storage))
			return (ComponentStorage<T>)storage;

		let newStorage = new ComponentStorage<T>();
		mComponentStorages[type] = newStorage;
		return newStorage;
	}

	/// Adds or replaces a component on an entity.
	public void SetComponent<T>(EntityId entity, T component) where T : struct, IComponent
	{
		if (!IsValid(entity))
			return;
		GetStorage<T>().Set(entity, component);
	}

	/// Gets a pointer to a component (null if entity doesn't have it).
	public T* GetComponent<T>(EntityId entity) where T : struct, IComponent
	{
		if (!IsValid(entity))
			return null;
		return GetStorage<T>().Get(entity);
	}

	/// Gets a reference to a component (asserts if not found).
	public ref T GetComponentRef<T>(EntityId entity) where T : struct, IComponent
	{
		Runtime.Assert(IsValid(entity), "Invalid entity");
		return ref GetStorage<T>().GetRef(entity);
	}

	/// Checks if an entity has a component.
	public bool HasComponent<T>(EntityId entity) where T : struct, IComponent
	{
		if (!IsValid(entity))
			return false;
		let type = typeof(T);
		if (!mComponentStorages.TryGetValue(type, let storage))
			return false;
		return storage.Has(entity);
	}

	/// Removes a component from an entity.
	public void RemoveComponent<T>(EntityId entity) where T : struct, IComponent
	{
		if (!IsValid(entity))
			return;
		let type = typeof(T);
		if (mComponentStorages.TryGetValue(type, let storage))
			storage.Remove(entity);
	}

	/// Returns an enumerator over all entities with a specific component.
	public ComponentStorage<T>.ComponentEnumerator Query<T>() where T : struct, IComponent
	{
		return GetStorage<T>().GetEnumerator();
	}

	// ==================== Runtime Type Component Access ====================

	/// Checks if an entity has a component of the given runtime type.
	public bool HasComponent(EntityId entity, Type type)
	{
		if (!IsValid(entity))
			return false;
		if (!mComponentStorages.TryGetValue(type, let storage))
			return false;
		return storage.Has(entity);
	}

	/// Gets a raw pointer to a component by runtime type (null if not present).
	public void* GetComponentRaw(EntityId entity, Type type)
	{
		if (!IsValid(entity))
			return null;
		if (!mComponentStorages.TryGetValue(type, let storage))
			return null;
		return storage.GetRaw(entity);
	}

	/// Sets a component from raw data by runtime type.
	public void SetComponentRaw(EntityId entity, Type type, void* data)
	{
		if (!IsValid(entity))
			return;
		if (mComponentStorages.TryGetValue(type, let storage))
			storage.SetRaw(entity, data);
	}

	/// Removes a component by runtime type, disposing owned resources first.
	public void RemoveComponent(EntityId entity, Type type)
	{
		if (!IsValid(entity))
			return;
		if (mComponentStorages.TryGetValue(type, let storage))
			storage.DisposeAndRemove(entity);
	}

	/// Adds a default-initialized component by runtime type.
	/// Creates the storage if it doesn't exist yet.
	public void AddDefaultComponent(EntityId entity, Type type)
	{
		if (!IsValid(entity))
			return;

		if (!mComponentStorages.TryGetValue(type, var storage))
		{
			// Create storage using comptime-generated __CreateStorage() factory
			for (let method in type.GetMethods(.Static | .Public))
			{
				if (method.Name == "__CreateStorage")
				{
					if (method.Invoke(Variant()) case .Ok(var result))
					{
						let obj = result.Get<Object>();
						if (let newStorage = obj as IComponentStorage)
						{
							mComponentStorages[type] = newStorage;
							storage = newStorage;
						}
					}
					break;
				}
			}
		}

		if (storage != null)
			storage.AddDefault(entity);
	}

	/// Gets all component types that have storage registered in this scene.
	public Dictionary<Type, IComponentStorage>.KeyEnumerator GetComponentTypes()
	{
		return mComponentStorages.Keys;
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
