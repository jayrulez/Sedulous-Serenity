namespace Sedulous.Framework.Scenes;

using System;

/// Marks a struct as a scene component, enabling runtime reflection and discovery.
/// Component structs decorated with this attribute can be automatically discovered
/// by tools (e.g., scene editors) via Type enumeration, and their fields can be
/// inspected and edited at runtime via reflection.
/// ReflectUser = .NonStaticFields causes all instance fields to be reflected automatically.
[AttributeUsage(.Struct, .ReflectAttribute, ReflectUser = .NonStaticFields)]
struct ComponentAttribute : Attribute
{
}
