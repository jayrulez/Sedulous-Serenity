namespace Sedulous.Engine.Scenes;

using System;
using System.Reflection;

/// Marks a struct as a scene component, enabling runtime reflection and discovery.
/// Component structs decorated with this attribute can be automatically discovered
/// by tools (e.g., scene editors) via Type enumeration, and their fields can be
/// inspected and edited at runtime via reflection.
///
/// For types that also implement ISerializableComponentData, a static factory method
/// (__CreateSerializer) is generated at compile time via IOnTypeInit. Scene uses
/// this to auto-register component serializers without manual per-type calls.
[AttributeUsage(.Struct, .ReflectAttribute, ReflectUser = .All, AlwaysIncludeUser = .AssumeInstantiated | .IncludeAllMethods)]
struct ComponentAttribute : Attribute, IOnTypeInit
{
	[Comptime]
	public void OnTypeInit(Type type, Self* prev)
	{
		// Generate storage factory for all component types
		Compiler.EmitTypeBody(type, """
			[Reflect]
			public static /*IComponentStorage*/Object __CreateStorage()
			{
				return new ComponentStorage<Self>();
			}
		""");

		if (type.ImplementsInterface(typeof(ISerializableComponentData)))
		{
			Compiler.EmitTypeBody(type, """
				[Reflect]
				public static Object __CreateSerializer()
				{
					return new ComponentSerializer<Self>();
				}
			""");
		}
	}
}
