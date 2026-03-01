namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Custom serializer for LightComponent.
/// Reads data from RenderSceneModule's light proxies during write,
/// and creates light instances via module API during read.
class LightComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "LightComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let renderModule = scene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return .Ok;

		// Gather light instances that correspond to active entities
		let entries = scope List<(int32 entityIdx, LightComponentData data)>();
		for (let instance in ref renderModule.LightInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = LightComponentData();
				// Read data from proxy
				if (let proxy = renderModule.World?.GetLight(instance.ProxyHandle))
				{
					data.Type = proxy.Type;
					data.Color = proxy.Color;
					data.Intensity = proxy.Intensity;
					data.Range = proxy.Range;
					data.InnerConeAngle = proxy.InnerConeAngle;
					data.OuterConeAngle = proxy.OuterConeAngle;
					data.CastsShadows = proxy.CastsShadows;
					data.ShadowBias = proxy.ShadowBias;
					data.ShadowNormalBias = proxy.ShadowNormalBias;
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
			var data = LightComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && renderModule != null)
			{
				let entity = loadedEntities[entityIdx];

				// Create via module API based on type
				switch (data.Type)
				{
				case .Directional:
					renderModule.CreateDirectionalLight(entity, data.Color, data.Intensity);
				case .Point:
					renderModule.CreatePointLight(entity, data.Color, data.Intensity, data.Range);
				case .Spot:
					renderModule.CreateSpotLight(entity, data.Color, data.Intensity, data.Range, data.InnerConeAngle, data.OuterConeAngle);
				default:
					renderModule.CreatePointLight(entity, data.Color, data.Intensity, data.Range);
				}

				// Set remaining properties via proxy
				if (let proxy = renderModule.GetLightProxy(entity))
				{
					proxy.CastsShadows = data.CastsShadows;
					proxy.ShadowBias = data.ShadowBias;
					proxy.ShadowNormalBias = data.ShadowNormalBias;
					proxy.LayerMask = data.LayerMask;
					if (!data.Enabled)
						proxy.IsEnabled = false;
				}
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
