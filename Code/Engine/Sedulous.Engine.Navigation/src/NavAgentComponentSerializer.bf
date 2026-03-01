namespace Sedulous.Engine.Navigation;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Custom serializer for NavAgentComponent.
/// Gathers data from NavigationSceneModule's internal storage during write,
/// and creates agent instances via module API during read.
class NavAgentComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "NavAgentComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let navModule = scene.GetModule<NavigationSceneModule>();
		if (navModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, NavAgentComponentData data)>();
		for (let instance in ref navModule.AgentInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = NavAgentComponentData();
				data.SyncToTransform = instance.SyncToTransform;
				data.Radius = instance.Radius;
				data.Height = instance.Height;
				data.MaxAcceleration = instance.MaxAcceleration;
				data.MaxSpeed = instance.MaxSpeed;
				data.CollisionQueryRange = instance.CollisionQueryRange;
				data.PathOptimizationRange = instance.PathOptimizationRange;
				data.SeparationWeight = instance.SeparationWeight;
				data.ObstacleAvoidanceType = instance.ObstacleAvoidanceType;
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
			var data = NavAgentComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && navModule != null)
			{
				let entity = loadedEntities[entityIdx];
				navModule.CreateAgentFromData(entity, data);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
