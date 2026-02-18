namespace Sedulous.Framework.Scenes;

using System;

/// Base interface for all scene components.
/// Extends IDisposable so components with owned resources (e.g., ResourceRef strings)
/// can clean up properly when removed or when entities are destroyed.
/// Components without owned resources should implement Dispose as a no-op.
interface IComponent : IDisposable
{
}
