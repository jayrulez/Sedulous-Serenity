namespace Sedulous.Engine.Navigation;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;

extension NavigationSceneModule
{
	private List<IComponentDataProvider> mDataProviders ~ DeleteContainerAndItems!(_);

	public override void GetDataProviders(List<IComponentDataProvider> outProviders)
	{
		if (mDataProviders == null)
		{
			mDataProviders = new .();
			mDataProviders.Add(new NavAgentDataProvider(this));
			mDataProviders.Add(new NavObstacleDataProvider(this));
		}
		outProviders.AddRange(mDataProviders);
	}

	public bool HasAgent(EntityId entity)
	{
		return mEntityToAgent.ContainsKey(entity);
	}

	public bool HasObstacle(EntityId entity)
	{
		return mEntityToObstacle.ContainsKey(entity);
	}

	public bool FillAgentComponentData(EntityId entity, NavAgentComponentData* data)
	{
		if (!mEntityToAgent.TryGetValue(entity, let idx)) return false;
		let instance = ref mAgentInstances[idx];
		if (!instance.Active) return false;
		data.SyncToTransform = instance.SyncToTransform;
		data.Radius = instance.Radius;
		data.Height = instance.Height;
		data.MaxAcceleration = instance.MaxAcceleration;
		data.MaxSpeed = instance.MaxSpeed;
		data.CollisionQueryRange = instance.CollisionQueryRange;
		data.PathOptimizationRange = instance.PathOptimizationRange;
		data.SeparationWeight = instance.SeparationWeight;
		data.ObstacleAvoidanceType = instance.ObstacleAvoidanceType;
		return true;
	}

	public void ApplyAgentComponentData(EntityId entity, NavAgentComponentData* data)
	{
		if (!mEntityToAgent.TryGetValue(entity, let idx)) return;
		var instance = ref mAgentInstances[idx];
		if (!instance.Active) return;
		instance.SyncToTransform = data.SyncToTransform;
		instance.Radius = data.Radius;
		instance.Height = data.Height;
		instance.MaxAcceleration = data.MaxAcceleration;
		instance.MaxSpeed = data.MaxSpeed;
		instance.CollisionQueryRange = data.CollisionQueryRange;
		instance.PathOptimizationRange = data.PathOptimizationRange;
		instance.SeparationWeight = data.SeparationWeight;
		instance.ObstacleAvoidanceType = data.ObstacleAvoidanceType;
	}

	public bool FillObstacleComponentData(EntityId entity, NavObstacleComponentData* data)
	{
		if (!mEntityToObstacle.TryGetValue(entity, let idx)) return false;
		let instance = ref mObstacleInstances[idx];
		if (!instance.Active) return false;
		data.Radius = instance.Radius;
		data.Height = instance.Height;
		return true;
	}

	public void ApplyObstacleComponentData(EntityId entity, NavObstacleComponentData* data)
	{
		if (!mEntityToObstacle.TryGetValue(entity, let idx)) return;
		var instance = ref mObstacleInstances[idx];
		if (!instance.Active) return;
		instance.Radius = data.Radius;
		instance.Height = data.Height;
	}
}

class NavAgentDataProvider : IComponentDataProvider
{
	private NavigationSceneModule mModule;
	public this(NavigationSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Nav Agent"); }
	public Type ComponentType => typeof(NavAgentComponent);
	public Type DataType => typeof(NavAgentComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasAgent(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillAgentComponentData(entity, (NavAgentComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplyAgentComponentData(entity, (NavAgentComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateAgentFromData(entity, .()); return true; }
	public void Destroy(EntityId entity) { mModule.RemoveAgent(entity); }
}

class NavObstacleDataProvider : IComponentDataProvider
{
	private NavigationSceneModule mModule;
	public this(NavigationSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Nav Obstacle"); }
	public Type ComponentType => typeof(NavObstacleComponent);
	public Type DataType => typeof(NavObstacleComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasObstacle(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillObstacleComponentData(entity, (NavObstacleComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplyObstacleComponentData(entity, (NavObstacleComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateObstacleFromData(entity, .()); return true; }
	public void Destroy(EntityId entity) { mModule.RemoveObstacle(entity); }
}
