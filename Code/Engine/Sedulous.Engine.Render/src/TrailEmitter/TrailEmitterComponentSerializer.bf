namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Custom serializer for TrailEmitterComponent.
/// Reads data from RenderSceneModule's trail proxies during write,
/// and creates trail instances via module API during read.
class TrailEmitterComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "TrailEmitterComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let renderModule = scene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, TrailEmitterComponentData data)>();
		for (let instance in ref renderModule.TrailEmitterInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = TrailEmitterComponentData();
				if (let proxy = renderModule.World?.GetTrailEmitter(instance.ProxyHandle))
				{
					data.BlendMode = proxy.BlendMode;
					data.MaxPoints = proxy.MaxPoints;
					data.Lifetime = proxy.Lifetime;
					data.WidthStart = proxy.WidthStart;
					data.WidthEnd = proxy.WidthEnd;
					data.MinVertexDistance = proxy.MinVertexDistance;
					data.Color = proxy.Color;
					data.SoftParticleDistance = proxy.SoftParticleDistance;
					data.LayerMask = proxy.LayerMask;
					data.Enabled = proxy.IsEnabled;
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
			var data = TrailEmitterComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && renderModule != null)
			{
				let entity = loadedEntities[entityIdx];
				renderModule.CreateTrailEmitterFromData(entity, data);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
