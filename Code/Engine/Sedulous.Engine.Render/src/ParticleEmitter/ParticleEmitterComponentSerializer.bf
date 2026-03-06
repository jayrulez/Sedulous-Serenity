namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Custom serializer for ParticleEmitterComponent.
/// Reads data from RenderSceneModule's particle proxies during write,
/// and creates particle instances via module API during read.
class ParticleEmitterComponentSerializer : IComponentSerializer
{
	public StringView TypeName => "ParticleEmitterComponent";

	public SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap)
	{
		let renderModule = scene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return .Ok;

		let entries = scope List<(int32 entityIdx, ParticleEmitterComponentData data)>();
		for (let instance in ref renderModule.ParticleEmitterInstances)
		{
			if (!instance.Active)
				continue;
			if (entityIndexMap.TryGetValue(instance.Entity.Index, let idx))
			{
				var data = ParticleEmitterComponentData();
				if (let proxy = renderModule.World?.GetParticleEmitter(instance.ProxyHandle))
				{
					data.Backend = proxy.Backend;
					data.SimulationSpace = proxy.SimulationSpace;
					data.BlendMode = proxy.BlendMode;
					data.RenderMode = proxy.RenderMode;
					data.MaxParticles = proxy.MaxParticles;
					data.SpawnRate = proxy.SpawnRate;
					data.ParticleLifetime = proxy.ParticleLifetime;
					data.BurstCount = proxy.BurstCount;
					data.BurstInterval = proxy.BurstInterval;
					data.BurstCycles = proxy.BurstCycles;
					data.StartSize = proxy.StartSize;
					data.EndSize = proxy.EndSize;
					data.StartColor = proxy.StartColor;
					data.EndColor = proxy.EndColor;
					data.InitialVelocity = proxy.InitialVelocity;
					data.VelocityRandomness = proxy.VelocityRandomness;
					data.GravityMultiplier = proxy.GravityMultiplier;
					data.Drag = proxy.Drag;
					data.VelocityInheritance = proxy.VelocityInheritance;
					data.SoftParticleDistance = proxy.SoftParticleDistance;
					data.StretchFactor = proxy.StretchFactor;
					data.SortParticles = proxy.SortParticles;
					data.Lit = proxy.Lit;
					data.AtlasColumns = proxy.AtlasColumns;
					data.AtlasRows = proxy.AtlasRows;
					data.AtlasFPS = proxy.AtlasFPS;
					data.AtlasLoop = proxy.AtlasLoop;
					data.SizeOverLifetime = proxy.SizeOverLifetime;
					data.ColorOverLifetime = proxy.ColorOverLifetime;
					data.SpeedOverLifetime = proxy.SpeedOverLifetime;
					data.AlphaOverLifetime = proxy.AlphaOverLifetime;
					data.RotationSpeedOverLifetime = proxy.RotationSpeedOverLifetime;
					data.ForceModules = proxy.ForceModules;
					data.LODStartDistance = proxy.LODStartDistance;
					data.LODCullDistance = proxy.LODCullDistance;
					data.LODMinRateMultiplier = proxy.LODMinRateMultiplier;
					data.LifetimeVarianceMin = proxy.LifetimeVarianceMin;
					data.LifetimeVarianceMax = proxy.LifetimeVarianceMax;
					data.Trail = proxy.Trail;
					data.Shape = proxy.Shape;
					data.SubEmitterOnly = proxy.SubEmitterOnly;
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
			var data = ParticleEmitterComponentData();
			data.Serialize(s);

			if (entityIdx >= 0 && entityIdx < loadedEntities.Count && renderModule != null)
			{
				let entity = loadedEntities[entityIdx];
				renderModule.CreateParticleEmitterFromData(entity, data);
			}

			data.Dispose();
			s.EndObject();
		}
		s.EndObject();
		return .Ok;
	}
}
