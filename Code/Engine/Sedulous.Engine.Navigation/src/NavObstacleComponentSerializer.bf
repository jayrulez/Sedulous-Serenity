namespace Sedulous.Engine.Navigation;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Custom serializer for NavObstacleComponent.
/// Gathers data from NavigationSceneModule's internal storage during write,
/// and creates obstacle instances via module API during read.
class NavObstacleComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "NavObstacleComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let navModule = scene.GetModule<NavigationSceneModule>();
		if (navModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, NavObstacleComponentData data)>();
		for (let instance in ref navModule.ObstacleInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = NavObstacleComponentData();
				data.Radius = instance.Radius;
				data.Height = instance.Height;
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
		let navModule = scene.GetModule<NavigationSceneModule>();

		s.BeginObject(TypeName);
		int32 count = 0;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			int32 entityIdx = 0;
			s.Int32("entity", ref entityIdx);
			var data = NavObstacleComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && navModule != null)
			{
				let entity = loadedEntities[entityIdx];
				navModule.CreateObstacleFromData(entity, data);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
