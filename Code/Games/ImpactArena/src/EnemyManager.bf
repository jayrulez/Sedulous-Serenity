namespace ImpactArena;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Physics;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;
using Sedulous.Physics;

enum EnemyType
{
	Grunt,
	Brute,
	Dasher
}

struct EnemyData
{
	public EntityId Entity;
	public EnemyType Type;
	public int32 Health;
	public float DashTimer;
	public float Radius;
}

class EnemyManager
{
	private Scene mScene;
	private RenderSceneModule mRenderModule;
	private PhysicsSceneModule mPhysicsModule;
	private GPUMeshHandle mSphereMesh;
	private MaterialInstance mGruntMat;
	private MaterialInstance mBruteMat;
	private MaterialInstance mDasherMat;

	private List<EnemyData> mEnemies = new .() ~ delete _;
	private Random mRandom = new .() ~ delete _;

	public int32 AliveCount => (int32)mEnemies.Count;

	public void Initialize(Scene scene, RenderSceneModule renderModule, PhysicsSceneModule physicsModule,
		GPUMeshHandle sphereMesh, MaterialInstance gruntMat, MaterialInstance bruteMat, MaterialInstance dasherMat)
	{
		mScene = scene;
		mRenderModule = renderModule;
		mPhysicsModule = physicsModule;
		mSphereMesh = sphereMesh;
		mGruntMat = gruntMat;
		mBruteMat = bruteMat;
		mDasherMat = dasherMat;
	}

	public void SpawnWave(int32 waveNumber)
	{
		int32 gruntCount = 3 + waveNumber * 2;
		int32 bruteCount = waveNumber / 2;
		int32 dasherCount = waveNumber / 3;

		for (int32 i = 0; i < gruntCount; i++)
			SpawnEnemy(.Grunt);
		for (int32 i = 0; i < bruteCount; i++)
			SpawnEnemy(.Brute);
		for (int32 i = 0; i < dasherCount; i++)
			SpawnEnemy(.Dasher);
	}

	private void SpawnEnemy(EnemyType type)
	{
		float radius;
		int32 health;
		MaterialInstance mat;

		switch (type)
		{
		case .Grunt:
			radius = 0.3f;
			health = 1;
			mat = mGruntMat;
		case .Brute:
			radius = 0.7f;
			health = 3;
			mat = mBruteMat;
		case .Dasher:
			radius = 0.4f;
			health = 1;
			mat = mDasherMat;
		}

		// Spawn at random edge position
		let pos = GetRandomEdgePosition();
		let entity = mScene.CreateEntity();
		var transform = mScene.GetTransform(entity);
		transform.Position = .(pos.X, radius, pos.Y);
		transform.Scale = .(radius * 2, radius * 2, radius * 2);
		mScene.SetTransform(entity, transform);

		let meshHandle = mRenderModule.CreateMeshRenderer(entity);
		if (meshHandle.IsValid)
		{
			mRenderModule.SetMeshData(entity, mSphereMesh, BoundingBox(.(-0.5f, -0.5f, -0.5f), .(0.5f, 0.5f, 0.5f)));
			mRenderModule.SetMeshMaterial(entity, mat);
		}

		var descriptor = PhysicsBodyDescriptor();
		descriptor.BodyType = .Dynamic;
		descriptor.Mass = 0.5f;
		descriptor.LinearDamping = 5.0f;
		descriptor.AngularDamping = 10.0f;
		descriptor.Restitution = 0.3f;
		descriptor.GravityFactor = 0.0f;
		descriptor.AllowedDOFs = .TranslationX | .TranslationZ;
		mPhysicsModule.CreateSphereBody(entity, radius, descriptor);

		var data = EnemyData();
		data.Entity = entity;
		data.Type = type;
		data.Health = health;
		data.DashTimer = 2.0f + (float)mRandom.NextDouble() * 2.0f;
		data.Radius = radius;
		mEnemies.Add(data);
	}

	private Vector2 GetRandomEdgePosition()
	{
		float edge = (float)mRandom.NextDouble() * 4.0f;
		float along = ((float)mRandom.NextDouble() - 0.5f) * 2.0f * (Arena.HalfSize - 1.0f);

		if (edge < 1) return .(along, -(Arena.HalfSize - 1.0f));         // North
		if (edge < 2) return .(along, Arena.HalfSize - 1.0f);            // South
		if (edge < 3) return .(-(Arena.HalfSize - 1.0f), along);         // West
		return .(Arena.HalfSize - 1.0f, along);                          // East
	}

	public void Update(Vector3 playerPos, float dt)
	{
		for (int32 i = 0; i < (int32)mEnemies.Count; i++)
		{
			var enemy = ref mEnemies[i];
			let ePos = mScene.GetTransform(enemy.Entity).Position;
			let toPlayer = playerPos - ePos;
			let dist = Vector3(toPlayer.X, 0, toPlayer.Z).Length();

			switch (enemy.Type)
			{
			case .Grunt:
				// Move toward player
				if (dist > 0.5f)
				{
					let dir = Vector3.Normalize(Vector3(toPlayer.X, 0, toPlayer.Z));
					mPhysicsModule.AddForce(enemy.Entity, dir * 8.0f);
				}
			case .Brute:
				// Slow but steady
				if (dist > 1.0f)
				{
					let dir = Vector3.Normalize(Vector3(toPlayer.X, 0, toPlayer.Z));
					mPhysicsModule.AddForce(enemy.Entity, dir * 5.0f);
				}
			case .Dasher:
				enemy.DashTimer -= dt;
				if (enemy.DashTimer <= 0 && dist > 1.0f)
				{
					let dir = Vector3.Normalize(Vector3(toPlayer.X, 0, toPlayer.Z));
					mPhysicsModule.AddImpulse(enemy.Entity, dir * 12.0f);
					enemy.DashTimer = 2.0f + (float)mRandom.NextDouble();
				}
			}
		}
	}

	/// Checks collisions with player, returns damage dealt and removes dead enemies.
	/// Returns list of death positions for effects.
	public float CheckPlayerCollisions(Vector3 playerPos, float playerSpeed, bool playerInvulnerable,
		List<Vector3> deathPositions, List<EnemyType> deathTypes)
	{
		float totalDamage = 0;
		bool playerDashing = playerSpeed > Player.DashSpeedThreshold;

		for (int32 i = (int32)mEnemies.Count - 1; i >= 0; i--)
		{
			let enemy = mEnemies[i];
			let ePos = mScene.GetTransform(enemy.Entity).Position;
			let toEnemy = ePos - playerPos;
			let dist = Vector3(toEnemy.X, 0, toEnemy.Z).Length();
			let contactDist = Player.Radius + enemy.Radius + 0.1f;

			if (dist < contactDist)
			{
				if (playerDashing)
				{
					// Player hits enemy
					var enemyRef = ref mEnemies[i];
					enemyRef.Health--;
					if (enemyRef.Health <= 0)
					{
						deathPositions.Add(ePos);
						deathTypes.Add(enemy.Type);
						DestroyEnemy(i);
					}
					else
					{
						// Knockback surviving enemy
						let knockDir = Vector3.Normalize(Vector3(toEnemy.X, 0, toEnemy.Z));
						mPhysicsModule.AddImpulse(enemy.Entity, knockDir * 15.0f);
					}
				}
				else if (!playerInvulnerable)
				{
					// Enemy hits player
					totalDamage += Player.DamagePerHit;
				}
			}
		}

		return totalDamage;
	}

	private void DestroyEnemy(int32 index)
	{
		let entity = mEnemies[index].Entity;
		mPhysicsModule.DestroyBody(entity);
		mScene.DestroyEntity(entity);
		mEnemies.RemoveAt(index);
	}

	public void ClearAll()
	{
		for (int32 i = (int32)mEnemies.Count - 1; i >= 0; i--)
			DestroyEnemy(i);
	}
}
