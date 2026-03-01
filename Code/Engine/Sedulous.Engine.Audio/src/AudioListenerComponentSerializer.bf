namespace Sedulous.Engine.Audio;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Custom serializer for AudioListenerComponent.
/// Gathers data from AudioSceneModule's internal storage during write,
/// and creates listener instances via module API during read.
class AudioListenerComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "AudioListenerComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let audioModule = scene.GetModule<AudioSceneModule>();
		if (audioModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, AudioListenerComponentData data)>();
		for (let instance in ref audioModule.ListenerInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = AudioListenerComponentData();
				data.Active = instance.ListenerActive;
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
		let audioModule = scene.GetModule<AudioSceneModule>();

		s.BeginObject(TypeName);
		int32 count = 0;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			int32 entityIdx = 0;
			s.Int32("entity", ref entityIdx);
			var data = AudioListenerComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && audioModule != null)
			{
				let entity = loadedEntities[entityIdx];
				audioModule.CreateListenerFromData(entity, data);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
