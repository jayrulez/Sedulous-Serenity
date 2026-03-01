namespace Sedulous.Engine.Render;

using System;
using Sedulous.Engine.Scenes;

/// Thin handle component for entities with a static mesh.
/// All data is owned by RenderSceneModule — use module API methods to configure.
[Component]
struct MeshComponent : IComponent
{
	/// Internal handle into the module's data storage. Do not access directly.
	public int32 InternalHandle = -1;

	public bool IsValid => InternalHandle >= 0;

	public void Dispose() mut { }
}
