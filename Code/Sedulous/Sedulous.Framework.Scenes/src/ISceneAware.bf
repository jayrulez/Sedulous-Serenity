namespace Sedulous.Framework.Scenes;

/// Interface for subsystems that want to receive scene lifecycle notifications.
/// Subsystems that implement this interface will be notified when scenes are
/// created or destroyed by the SceneSubsystem.
public interface ISceneAware
{
	/// Called when a new scene is created.
	/// Use this to add scene-specific modules or components.
	void OnSceneCreated(Scene scene);

	/// Called when a scene is being destroyed.
	/// Use this for any subsystem-level cleanup related to the scene.
	void OnSceneDestroyed(Scene scene);
}
