namespace Sedulous.Engine.UI;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Custom serializer for WorldUIComponent.
/// Gathers data from UISceneModule's panel list during write,
/// and creates panel instances via module API during read.
class WorldUIComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "WorldUIComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let uiModule = scene.GetModule<UISceneModule>();
		if (uiModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, WorldUIComponentData data)>();
		for (let panel in uiModule.Panels)
		{
			if (entityIndexMap.TryGetValue(panel.Entity.Index, let idx))
			{
				var data = WorldUIComponentData();
				data.Enabled = true;
				data.PixelWidth = panel.PixelWidth;
				data.PixelHeight = panel.PixelHeight;
				data.PanelWidth = panel.PanelWidth;
				data.PanelHeight = panel.PanelHeight;
				data.IsInteractive = panel.IsInteractive;
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
		let uiModule = scene.GetModule<UISceneModule>();

		s.BeginObject(TypeName);
		int32 count = 0;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			int32 entityIdx = 0;
			s.Int32("entity", ref entityIdx);
			var data = WorldUIComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && uiModule != null)
			{
				let entity = loadedEntities[entityIdx];
				uiModule.CreateWorldUIFromData(entity, data);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
