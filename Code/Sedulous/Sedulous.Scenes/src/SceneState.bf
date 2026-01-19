namespace Sedulous.Scenes;

/// Lifecycle states for a scene.
public enum SceneState
{
	/// Scene is not loaded.
	Unloaded,

	/// Scene is currently loading.
	Loading,

	/// Scene is active and updating.
	Active,

	/// Scene is loaded but paused (not updating).
	Paused,

	/// Scene is currently unloading.
	Unloading
}
