namespace Sedulous.Engine.UI;

using System;
using Sedulous.Engine.Scenes;

/// Thin handle component for entities with world-space UI panels.
/// All data is owned by UISceneModule — this component just holds
/// the internal handle into the module's storage.
[Component]
struct WorldUIComponent : IComponent
{
	/// Internal handle into the module's data storage. Do not access directly.
	public int32 InternalHandle = -1;

	public bool IsValid => InternalHandle >= 0;

	public void Dispose() mut { }
}
