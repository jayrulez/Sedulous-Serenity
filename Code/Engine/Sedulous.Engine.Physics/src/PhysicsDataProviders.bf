namespace Sedulous.Engine.Physics;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;

extension PhysicsSceneModule
{
	private List<IComponentDataProvider> mDataProviders ~ DeleteContainerAndItems!(_);

	public override void GetDataProviders(List<IComponentDataProvider> outProviders)
	{
		if (mDataProviders == null)
		{
			mDataProviders = new .();
			mDataProviders.Add(new RigidBodyDataProvider(this));
		}
		outProviders.AddRange(mDataProviders);
	}
}

class RigidBodyDataProvider : IComponentDataProvider
{
	private PhysicsSceneModule mModule;
	public this(PhysicsSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Rigid Body"); }
	public Type ComponentType => typeof(RigidBodyComponent);
	public Type DataType => typeof(RigidBodyComponentData);

	public bool HasComponent(EntityId entity)
	{
		return mModule.Bodies.ContainsKey(entity);
	}

	public bool GetComponentData(EntityId entity, void* outData)
	{
		if (!mModule.Bodies.TryGetValue(entity, let body))
			return false;
		var data = (RigidBodyComponentData*)outData;
		data.BodyType = body.BodyType;
		data.Mass = body.Mass;
		data.LinearDamping = body.LinearDamping;
		data.AngularDamping = body.AngularDamping;
		data.Friction = body.Friction;
		data.Restitution = body.Restitution;
		data.GravityFactor = body.GravityFactor;
		data.Enabled = body.Enabled;
		data.ShapeType = body.ShapeType;
		data.HalfExtents = body.HalfExtents;
		return true;
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		if (!mModule.Bodies.TryGetValue(entity, var body))
			return;
		let data = (RigidBodyComponentData*)inData;
		body.BodyType = data.BodyType;
		body.Mass = data.Mass;
		body.LinearDamping = data.LinearDamping;
		body.AngularDamping = data.AngularDamping;
		body.Friction = data.Friction;
		body.Restitution = data.Restitution;
		body.GravityFactor = data.GravityFactor;
		body.Enabled = data.Enabled;
		body.ShapeType = data.ShapeType;
		body.HalfExtents = data.HalfExtents;
		mModule.Bodies[entity] = body;
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateBoxBody(entity, .(0.5f, 0.5f, 0.5f)); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyBody(entity); }
}
