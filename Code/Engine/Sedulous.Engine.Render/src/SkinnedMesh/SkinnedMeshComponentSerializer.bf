namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Custom serializer for SkinnedMeshComponent.
/// Gathers data from RenderSceneModule's internal storage during write,
/// and creates skinned mesh instances via module API during read.
class SkinnedMeshComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "SkinnedMeshComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let renderModule = scene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return .Ok;

		// Gather skinned mesh instances that correspond to active entities
		let entries = scope List<(int32 entityIdx, SkinnedMeshComponentData data)>();
		for (let instance in ref renderModule.SkinnedMeshInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = SkinnedMeshComponentData();
				data.MeshRef = instance.MeshRef;
				data.MaterialRefs = instance.MaterialRefs;
				data.Enabled = instance.Enabled;
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
		let renderModule = scene.GetModule<RenderSceneModule>();

		s.BeginObject(TypeName);
		int32 count = 0;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			int32 entityIdx = 0;
			s.Int32("entity", ref entityIdx);
			var data = SkinnedMeshComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && renderModule != null)
			{
				let entity = loadedEntities[entityIdx];
				renderModule.CreateSkinnedMeshFromRef(entity, data.MeshRef, data.Enabled);

				for (int32 m = 0; m < data.MaterialRefs.Count; m++)
					renderModule.SetSkinnedMeshMaterialRef(entity, m, data.MaterialRefs[m]);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
