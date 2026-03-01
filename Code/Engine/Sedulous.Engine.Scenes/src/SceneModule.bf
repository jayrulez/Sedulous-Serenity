namespace Sedulous.Engine.Scenes;

using System.Collections;
using Sedulous.Core.Mathematics;

/// Base class providing empty implementations for ISceneModule.
/// Inherit from this class and override only the methods you need.
abstract class SceneModule : ISceneModule
{
	/// Collects data providers for the editor inspector. Override to expose component data.
	public virtual void GetDataProviders(List<IComponentDataProvider> outProviders) { }

	/// Called when the module is added to a scene.
	public virtual void OnSceneCreate(Scene scene) { }

	/// Called when the scene is being destroyed.
	public virtual void OnSceneDestroy(Scene scene) { }

	/// Called at the beginning of each frame.
	public virtual void OnBeginFrame(Scene scene, float deltaTime) { }

	/// Called at a fixed timestep for deterministic simulation.
	public virtual void FixedUpdate(Scene scene, float fixedDeltaTime) { }

	/// Called during the main update phase.
	public virtual void Update(Scene scene, float deltaTime) { }

	/// Called at the end of the update phase.
	public virtual void OnEndFrame(Scene scene) { }

	/// Called after transform hierarchy updates, when world matrices are valid.
	public virtual void PostUpdate(Scene scene, float deltaTime) { }

	/// Called when an entity is about to be destroyed.
	public virtual void OnEntityDestroyed(Scene scene, EntityId entity) { }

	/// Called when the scene state changes.
	public virtual void OnSceneStateChanged(Scene scene, SceneState oldState, SceneState newState) { }

	/// Called when an entity's world transform has changed.
	public virtual void OnEntityTransformChanged(Scene scene, EntityId entity, in Matrix worldMatrix) { }
}
