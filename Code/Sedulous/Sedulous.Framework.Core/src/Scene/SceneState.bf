namespace Sedulous.Framework.Core;

/// Represents the lifecycle state of a scene.
enum SceneState
{
	/// Scene has been created but not loaded.
	Unloaded,

	/// Scene is currently loading resources and initializing.
	Loading,

	/// Scene is fully loaded and actively updating.
	Active,

	/// Scene is loaded but updates are paused.
	Paused,

	/// Scene is in the process of unloading.
	Unloading
}
