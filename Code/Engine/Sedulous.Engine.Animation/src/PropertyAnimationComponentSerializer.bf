namespace Sedulous.Engine.Animation;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Custom serializer for PropertyAnimationComponent.
/// Gathers data from AnimationSceneModule's internal storage during write,
/// and creates property animation instances via module API during read.
class PropertyAnimationComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "PropertyAnimationComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let animModule = scene.GetModule<AnimationSceneModule>();
		if (animModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, PropertyAnimationComponentData data)>();
		for (let instance in ref animModule.PropertyAnimInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = PropertyAnimationComponentData();
				data.Playing = instance.Playing;
				data.Speed = instance.Speed;
				entries.Add((idx, data));
			}
		}

		s.BeginObject(TypeName);
		int32 count = (int32)entries.Count;
		s.Int32("count", ref count);

		for (int i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			var entityIdx = entries[i].entityIdx;
			s.Int32("entity", ref entityIdx);
			var comp = entries[i].data;
			comp.Serialize(s);
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}

	public SerializationResult Read(Scene scene, Serializer s, List<EntityId> loadedEntities)
	{
		// PropertyAnimationComponent has no resource refs to resolve during deserialization.
		// The actual animation clips are created programmatically at runtime, not serialized.
		// We just read the data to maintain format compatibility.

		s.BeginObject(TypeName);
		int32 count = 0;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			int32 entityIdx = 0;
			s.Int32("entity", ref entityIdx);
			var data = PropertyAnimationComponentData();
			data.Serialize(s);
			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
