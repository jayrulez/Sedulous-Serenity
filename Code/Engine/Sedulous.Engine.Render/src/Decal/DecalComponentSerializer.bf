namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Custom serializer for DecalComponent.
/// Reads data from RenderSceneModule's decal instances and proxies during write,
/// and creates decal instances via module API during read.
class DecalComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "DecalComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let renderModule = scene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, DecalComponentData data)>();
		for (let instance in ref renderModule.DecalInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = DecalComponentData();
				data.TextureRef = instance.TextureRef;
				// Read rendering data from proxy
				if (let proxy = renderModule.World?.GetDecal(instance.ProxyHandle))
				{
					data.Scale = proxy.Scale;
					data.Color = proxy.Color;
					data.AngleFadeStart = proxy.AngleFadeStart;
					data.AngleFadeEnd = proxy.AngleFadeEnd;
					data.SortOrder = proxy.SortOrder;
					data.BlendMode = proxy.BlendMode;
					data.Enabled = proxy.IsActive;
				}
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
			var data = DecalComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && renderModule != null)
			{
				let entity = loadedEntities[entityIdx];
				renderModule.CreateDecalFromData(entity, data);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
