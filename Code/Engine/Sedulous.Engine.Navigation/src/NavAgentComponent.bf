namespace Sedulous.Engine.Navigation;

using System;
using Sedulous.Engine.Scenes;

/// Thin handle component for entities with navigation agents.
/// All data is owned by NavigationSceneModule — this component just holds
/// the internal handle into the module's storage.
[Component]
struct NavAgentComponent : IComponent
{
	/// Internal handle into the module's data storage. Do not access directly.
	public int32 InternalHandle = -1;

	public bool IsValid => InternalHandle >= 0;

	public void Dispose() mut { }
}
