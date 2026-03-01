namespace Sedulous.Engine.Animation;

using System;
using Sedulous.Engine.Scenes;

/// Thin handle component for entities using an animation graph.
/// All data is owned by AnimationSceneModule — this component just holds
/// the internal handle into the module's storage.
[Component]
struct AnimationGraphComponent : IComponent
{
	/// Internal handle into the module's data storage. Do not access directly.
	public int32 InternalHandle = -1;

	public bool IsValid => InternalHandle >= 0;

	public void Dispose() mut { }
}
