namespace Sedulous.Framework.Scenes;

using System;

/// Marks a class as module settings that are auto-discovered and managed by Scene.
/// Settings instances are created automatically when a Scene is constructed,
/// and their data persists in .scene files.
/// The name parameter is used as the serialization key in the file.
/// The displayName parameter is used as the category label in the editor inspector.
[AttributeUsage(.Class, .ReflectAttribute, ReflectUser = .NonStaticFields | .Constructors | .All, AlwaysIncludeUser = .AssumeInstantiated)]
struct ModuleSettingsAttribute : Attribute
{
	public String Name;
	public String DisplayName;

	public this(String name, String displayName)
	{
		Name = name;
		DisplayName = displayName;
	}
}
