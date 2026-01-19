namespace Sedulous.Scenes;

/// Interface for scene modules that process components.
/// Modules contain logic and operate on scene-owned data.
/// They do not own entities, manage transforms, or control entity lifetimes.
interface ISceneModule
{
	/// Called when the module is added to a scene.
	void OnSceneCreate(Scene scene);

	/// Called when the scene is being destroyed.
	void OnSceneDestroy(Scene scene);

	/// Called at the beginning of each frame, before Update.
	void OnBeginFrame(Scene scene, float deltaTime);

	/// Called during the main update phase.
	/// This is where modules should process their components.
	void Update(Scene scene, float deltaTime);

	/// Called at the end of each frame, after transform hierarchy updates.
	/// World matrices are valid at this point.
	void OnEndFrame(Scene scene);

	/// Called when an entity is about to be destroyed.
	/// Modules should clean up any references to this entity.
	void OnEntityDestroyed(Scene scene, EntityId entity);

	/// Called when the scene state changes.
	void OnSceneStateChanged(Scene scene, SceneState oldState, SceneState newState);
}
