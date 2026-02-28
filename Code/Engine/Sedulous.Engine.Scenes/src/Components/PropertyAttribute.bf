namespace Sedulous.Engine.Scenes;

using System;

/// Hints for the scene editor on which property editor to use.
enum PropertyEditorHint
{
	Default,
	Color
}

/// Marks a component field as editor-visible.
/// Only fields with this attribute will appear in the scene editor inspector.
/// Runtime-only fields (ResourceHandle, MaterialInstance, etc.) should not have this.
[AttributeUsage(.Field, .ReflectAttribute)]
struct PropertyAttribute : Attribute
{
	public PropertyEditorHint Editor;

	public this()
	{
		Editor = .Default;
	}

	public this(PropertyEditorHint editor)
	{
		Editor = editor;
	}
}
