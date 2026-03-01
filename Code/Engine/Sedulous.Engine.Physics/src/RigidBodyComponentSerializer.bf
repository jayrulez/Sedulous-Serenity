namespace Sedulous.Engine.Physics;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Custom serializer for RigidBodyComponent.
/// Gathers data from PhysicsSceneModule's internal storage during write,
/// and recreates body data via module API during read.
class RigidBodyComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "RigidBodyComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let physicsModule = scene.GetModule<PhysicsSceneModule>();
		if (physicsModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, RigidBodyComponentData data)>();
		for (let (entity, bodyData) in physicsModule.Bodies)
		{
			if (entityIndexMap.TryGetValue(entity.Index, let idx))
			{
				var data = RigidBodyComponentData();
				data.BodyType = bodyData.BodyType;
				data.Mass = bodyData.Mass;
				data.LinearDamping = bodyData.LinearDamping;
				data.AngularDamping = bodyData.AngularDamping;
				data.Friction = bodyData.Friction;
				data.Restitution = bodyData.Restitution;
				data.GravityFactor = bodyData.GravityFactor;
				data.Enabled = bodyData.Enabled;
				data.ShapeType = bodyData.ShapeType;
				data.HalfExtents = bodyData.HalfExtents;
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
		let physicsModule = scene.GetModule<PhysicsSceneModule>();

		s.BeginObject(TypeName);
		int32 count = 0;
		s.Int32("count", ref count);

		for (int32 i = 0; i < count; i++)
		{
			s.BeginObject(scope $"c{i}");
			int32 entityIdx = 0;
			s.Int32("entity", ref entityIdx);
			var data = RigidBodyComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && physicsModule != null)
			{
				let entity = loadedEntities[entityIdx];
				physicsModule.CreateBodyFromData(entity, data);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
