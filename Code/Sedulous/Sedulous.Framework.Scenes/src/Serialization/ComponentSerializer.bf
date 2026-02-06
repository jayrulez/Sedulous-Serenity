namespace Sedulous.Framework.Scenes;

using System;
using System.Collections;
using Sedulous.Serialization;

/// Generic component serializer that handles reading/writing components of type T.
/// T must be a struct implementing ISerializableComponent.
class ComponentSerializer<T> : IComponentSerializer where T : struct, ISerializableComponent
{
	private String mTypeName ~ delete _;

	public StringView TypeName => mTypeName;

	public this()
	{
		mTypeName = new String();
		typeof(T).GetName(mTypeName);
	}

	public IComponentSerializer CreateNew()
	{
		return new ComponentSerializer<T>();
	}

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		// Collect components with their serialized entity indices
		let entries = scope List<(int32 entityIdx, T component)>();
		for (let (entity, componentPtr) in scene.Query<T>())
		{
			if (entityIndexMap.TryGetValue(entity.Index, let idx))
				entries.Add((idx, *componentPtr));
		}

		s.BeginObject(mTypeName);
		int32 count = (int32)entries.Count;
		s.Int32("count", ref count);

		for (int i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			var entityIdx = entries[i].entityIdx;
			s.Int32("entity", ref entityIdx);
			var comp = entries[i].component;
			comp.Serialize(s);
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}

	public SerializationResult Read(Scene scene, Serializer s, List<EntityId> loadedEntities)
	{
		s.BeginObject(mTypeName);
		int32 count = 0;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			int32 entityIdx = 0;
			s.Int32("entity", ref entityIdx);
			var comp = default(T);
			comp.Serialize(s);
			if (entityIdx >= 0 && entityIdx < loadedEntities.Count)
				scene.SetComponent<T>(loadedEntities[entityIdx], comp);
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
