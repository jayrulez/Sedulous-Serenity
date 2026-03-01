namespace Sedulous.Engine.Audio;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Resources;
using Sedulous.Serialization;

/// Custom serializer for AudioSourceComponent.
/// Gathers data from AudioSceneModule's internal storage during write,
/// and creates audio source instances via module API during read.
class AudioSourceComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "AudioSourceComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let audioModule = scene.GetModule<AudioSceneModule>();
		if (audioModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, AudioSourceComponentData data)>();
		for (let instance in ref audioModule.SourceInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = AudioSourceComponentData();
				if (instance.ClipRef.IsValid)
					data.ClipRef = ResourceRef(instance.ClipRef.Id, instance.ClipRef.Path);
				data.Volume = instance.Volume;
				data.Pitch = instance.Pitch;
				data.Spatial = instance.Spatial;
				data.Loop = instance.Loop;
				data.AutoPlay = instance.AutoPlay;
				data.MinDistance = instance.MinDistance;
				data.MaxDistance = instance.MaxDistance;
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

		// Clean up ResourceRef copies
		for (var entry in ref entries)
			entry.data.Dispose();

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
			var data = AudioSourceComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && audioModule != null)
			{
				let entity = loadedEntities[entityIdx];
				audioModule.CreateSourceFromData(entity, data);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
