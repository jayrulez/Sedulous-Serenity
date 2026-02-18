namespace Sedulous.Framework.Scenes;

using System;

/// Marks a component field as editor-visible.
/// Only fields with this attribute will appear in the scene editor inspector.
/// Runtime-only fields (ResourceHandle, MaterialInstance, etc.) should not have this.
[AttributeUsage(.Field, .ReflectAttribute)]
struct PropertyAttribute : Attribute
{
}
