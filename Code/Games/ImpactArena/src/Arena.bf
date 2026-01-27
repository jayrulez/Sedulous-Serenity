namespace ImpactArena;

using System;
using Sedulous.Mathematics;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Physics;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Resources;
using Sedulous.Materials;
using Sedulous.Physics;

class Arena
{
	public const float HalfSize = 10.0f;
	public const float WallHeight = 1.5f;
	public const float WallThickness = 2.0f;

	private Scene mScene;
	private RenderSceneModule mRenderModule;
	private PhysicsSceneModule mPhysicsModule;

	private EntityId mFloorEntity;
	private EntityId[4] mWallEntities;

	public void Initialize(Scene scene, RenderSceneModule renderModule, PhysicsSceneModule physicsModule,
		StaticMeshResource planeResource, StaticMeshResource cubeResource, MaterialInstance floorMat, MaterialInstance wallMat)
	{
		mScene = scene;
		mRenderModule = renderModule;
		mPhysicsModule = physicsModule;

		CreateFloor(planeResource, floorMat);
		CreateWalls(cubeResource, wallMat);
	}

	private void CreateFloor(StaticMeshResource planeResource, MaterialInstance mat)
	{
		mFloorEntity = mScene.CreateEntity();
		mScene.SetComponent<MeshRendererComponent>(mFloorEntity, .Default);
		var comp = mScene.GetComponent<MeshRendererComponent>(mFloorEntity);
		comp.Mesh = ResourceHandle<StaticMeshResource>(planeResource);
		comp.Material = mat;
		mPhysicsModule.CreatePlaneBody(mFloorEntity, .(0, 1, 0), 0.0f);
	}

	private void CreateWalls(StaticMeshResource cubeResource, MaterialInstance mat)
	{
		// North wall (Z = -HalfSize)
		mWallEntities[0] = CreateWall(cubeResource, mat,
			.(0, WallHeight * 0.5f, -(HalfSize + WallThickness * 0.5f)),
			.(HalfSize + WallThickness, WallHeight * 0.5f, WallThickness * 0.5f));
		// South wall (Z = +HalfSize)
		mWallEntities[1] = CreateWall(cubeResource, mat,
			.(0, WallHeight * 0.5f, HalfSize + WallThickness * 0.5f),
			.(HalfSize + WallThickness, WallHeight * 0.5f, WallThickness * 0.5f));
		// West wall (X = -HalfSize)
		mWallEntities[2] = CreateWall(cubeResource, mat,
			.(-(HalfSize + WallThickness * 0.5f), WallHeight * 0.5f, 0),
			.(WallThickness * 0.5f, WallHeight * 0.5f, HalfSize + WallThickness));
		// East wall (X = +HalfSize)
		mWallEntities[3] = CreateWall(cubeResource, mat,
			.(HalfSize + WallThickness * 0.5f, WallHeight * 0.5f, 0),
			.(WallThickness * 0.5f, WallHeight * 0.5f, HalfSize + WallThickness));
	}

	private EntityId CreateWall(StaticMeshResource cubeResource, MaterialInstance mat, Vector3 position, Vector3 halfExtents)
	{
		let entity = mScene.CreateEntity();
		var transform = mScene.GetTransform(entity);
		transform.Position = position;
		transform.Scale = halfExtents * 2.0f;
		mScene.SetTransform(entity, transform);

		mScene.SetComponent<MeshRendererComponent>(entity, .Default);
		var comp = mScene.GetComponent<MeshRendererComponent>(entity);
		comp.Mesh = ResourceHandle<StaticMeshResource>(cubeResource);
		comp.Material = mat;

		var descriptor = PhysicsBodyDescriptor();
		descriptor.BodyType = .Static;
		descriptor.Layer = 0;
		descriptor.Friction = 0.3f;
		descriptor.Restitution = 0.8f;
		mPhysicsModule.CreateBoxBody(entity, halfExtents, .Static);

		return entity;
	}
}
