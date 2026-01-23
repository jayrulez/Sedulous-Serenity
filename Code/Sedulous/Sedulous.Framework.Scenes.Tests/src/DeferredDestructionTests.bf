namespace Sedulous.Framework.Scenes.Tests;

using System;
using Sedulous.Framework.Scenes;

/// Module that destroys an entity during update to test deferred destruction.
class DestructionTestModule : SceneModule
{
	public EntityId EntityToDestroy = .Invalid;
	public bool WasEntityValidDuringUpdate = false;

	public override void Update(Scene scene, float deltaTime)
	{
		if (EntityToDestroy.IsValid)
		{
			scene.DestroyEntity(EntityToDestroy);
			// Entity should still be valid during update (deferred destruction)
			WasEntityValidDuringUpdate = scene.IsValid(EntityToDestroy);
		}
	}
}

/// Module that creates entities during update.
class CreationTestModule : SceneModule
{
	public EntityId CreatedEntity = .Invalid;
	public bool ShouldCreate = false;

	public override void Update(Scene scene, float deltaTime)
	{
		if (ShouldCreate)
		{
			CreatedEntity = scene.CreateEntity();
			ShouldCreate = false;
		}
	}
}

class DeferredDestructionTests
{
	[Test]
	public static void TestDestructionDeferredDuringUpdate()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new DestructionTestModule();
		scene.AddModule(module);

		let entity = scene.CreateEntity();
		module.EntityToDestroy = entity;

		scene.SetState(.Active);
		scene.Update(0.016f);

		// During update, entity was still valid
		Test.Assert(module.WasEntityValidDuringUpdate);

		// Deferred destructions are processed in PostUpdate
		scene.PostUpdate(0.016f);

		// After PostUpdate, entity is destroyed
		Test.Assert(!scene.IsValid(entity));
	}

	[Test]
	public static void TestMultipleDestructionsDuringUpdate()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let e1 = scene.CreateEntity();
		let e2 = scene.CreateEntity();
		let e3 = scene.CreateEntity();

		// Module that destroys multiple entities
		EntityId[3] entitiesToDestroy = .(e1, e2, e3);
		let module = new MultiDestructionModule(entitiesToDestroy);
		scene.AddModule(module);

		Test.Assert(scene.EntityCount == 3);

		scene.SetState(.Active);
		scene.Update(0.016f);
		scene.PostUpdate(0.016f);

		// All entities destroyed after PostUpdate
		Test.Assert(scene.EntityCount == 0);
		Test.Assert(!scene.IsValid(e1));
		Test.Assert(!scene.IsValid(e2));
		Test.Assert(!scene.IsValid(e3));
	}

	[Test]
	public static void TestDestructionOutsideUpdateIsImmediate()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();

		// Destroy outside of update
		scene.DestroyEntity(entity);

		// Should be immediately destroyed
		Test.Assert(!scene.IsValid(entity));
		Test.Assert(scene.EntityCount == 0);
	}

	[Test]
	public static void TestCreationDuringUpdate()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let module = new CreationTestModule();
		module.ShouldCreate = true;
		scene.AddModule(module);

		Test.Assert(scene.EntityCount == 0);

		scene.SetState(.Active);
		scene.Update(0.016f);

		// Entity should be created and valid
		Test.Assert(module.CreatedEntity.IsValid);
		Test.Assert(scene.IsValid(module.CreatedEntity));
		Test.Assert(scene.EntityCount == 1);
	}

	[Test]
	public static void TestDestroyAndRecreateInSameFrame()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();

		// Module that destroys entity, then recreation module creates new one
		let destroyModule = new DestructionTestModule();
		destroyModule.EntityToDestroy = entity;

		let createModule = new CreationTestModule();
		createModule.ShouldCreate = true;

		scene.AddModule(destroyModule);
		scene.AddModule(createModule);

		scene.SetState(.Active);
		scene.Update(0.016f);
		scene.PostUpdate(0.016f);

		// Original entity destroyed
		Test.Assert(!scene.IsValid(entity));

		// New entity created (may or may not reuse the same index due to deferred destruction)
		Test.Assert(scene.IsValid(createModule.CreatedEntity));
	}

	[Test]
	public static void TestComponentsAccessibleDuringDeferredDestruction()
	{
		let scene = scope Scene("Test");
		defer scene.Dispose();

		let entity = scene.CreateEntity();
		scene.SetComponent<HealthComponent>(entity, .() { Current = 100, Max = 100 });

		let module = new ComponentAccessModule();
		module.EntityToCheck = entity;
		scene.AddModule(module);

		// Queue destruction
		let destroyModule = new DestructionTestModule();
		destroyModule.EntityToDestroy = entity;
		scene.AddModule(destroyModule);

		scene.SetState(.Active);
		scene.Update(0.016f);

		// Component was accessible during the frame
		Test.Assert(module.ComponentWasAccessible);
	}
}

/// Module that destroys multiple entities.
class MultiDestructionModule : SceneModule
{
	private EntityId[3] mEntitiesToDestroy;

	public this(EntityId[3] entities)
	{
		mEntitiesToDestroy = entities;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		for (let e in mEntitiesToDestroy)
		{
			if (e.IsValid)
				scene.DestroyEntity(e);
		}
	}
}

/// Module that checks if a component is accessible.
class ComponentAccessModule : SceneModule
{
	public EntityId EntityToCheck = .Invalid;
	public bool ComponentWasAccessible = false;

	public override void OnBeginFrame(Scene scene, float deltaTime)
	{
		if (EntityToCheck.IsValid)
		{
			let health = scene.GetComponent<HealthComponent>(EntityToCheck);
			ComponentWasAccessible = (health != null);
		}
	}
}
