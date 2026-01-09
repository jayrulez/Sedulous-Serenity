using Sedulous.Serialization;

namespace Sedulous.Engine.Core;

/// Interface for scene-level singleton components.
/// Scene components are attached to the scene itself rather than entities.
/// Examples include Physics, Lighting, Navigation systems.
/// Only one instance of each type can exist per scene.
interface ISceneComponent : ISerializable
{
	/// Called when the component is attached to a scene.
	void OnAttach(Scene scene);

	/// Called when the component is detached from a scene.
	void OnDetach();

	/// Called each frame to update the component.
	void OnUpdate(float deltaTime);

	/// Called when the scene state changes.
	void OnSceneStateChanged(SceneState oldState, SceneState newState);
}
