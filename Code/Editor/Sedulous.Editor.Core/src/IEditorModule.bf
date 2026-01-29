namespace Sedulous.Editor.Core;

using System;

/// Interface for editor modules.
/// Modules register asset handlers and provide specialized editing functionality.
interface IEditorModule
{
	/// Module name for display.
	StringView Name { get; }

	/// Initialize the module (register asset handlers, etc.).
	void Initialize(AssetRegistry registry);

	/// Shutdown the module.
	void Shutdown();
}
