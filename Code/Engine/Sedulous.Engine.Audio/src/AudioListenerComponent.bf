namespace Sedulous.Engine.Audio;

using System;
using Sedulous.Engine.Scenes;

/// Thin handle component for entities that serve as the audio listener.
/// All data is owned by AudioSceneModule — this component just holds
/// the internal handle into the module's storage.
[Component]
struct AudioListenerComponent : IComponent
{
	/// Internal handle into the module's data storage. Do not access directly.
	public int32 InternalHandle = -1;

	public bool IsValid => InternalHandle >= 0;

	public void Dispose() mut { }
}
