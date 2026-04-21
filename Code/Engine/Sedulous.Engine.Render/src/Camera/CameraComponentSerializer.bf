namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Custom serializer for CameraComponent.
/// Reads data from RenderSceneModule's camera proxies during write,
/// and creates camera instances via module API during read.
class CameraComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "CameraComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let renderModule = scene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, CameraComponentData data)>();
		for (let instance in ref renderModule.CameraInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = CameraComponentData();
				if (let proxy = renderModule.World?.GetCamera(instance.RenderHandle))
				{
					data.Projection = proxy.Projection;
					data.FieldOfView = proxy.FieldOfView;
					data.AspectRatio = proxy.AspectRatio;
					data.NearPlane = proxy.NearPlane;
					data.FarPlane = proxy.FarPlane;
					data.OrthoWidth = proxy.OrthoWidth;
					data.OrthoHeight = proxy.OrthoHeight;
					data.Priority = proxy.Priority;
					data.Active = true;
					data.IsMainCamera = proxy.IsMainCamera;
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
			var data = CameraComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && renderModule != null)
			{
				let entity = loadedEntities[entityIdx];

				switch (data.Projection)
				{
				case .Perspective:
					renderModule.CreatePerspectiveCamera(entity, data.FieldOfView, data.AspectRatio, data.NearPlane, data.FarPlane);
				case .Orthographic:
					renderModule.CreateOrthographicCamera(entity, data.OrthoWidth, data.OrthoHeight, data.NearPlane, data.FarPlane);
				}

				if (data.IsMainCamera)
					renderModule.SetMainCamera(entity);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
