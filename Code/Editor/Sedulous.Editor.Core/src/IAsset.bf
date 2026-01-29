namespace Sedulous.Editor.Core;

using System;

/// Interface for all editor assets.
/// Assets are editable source data that can be transformed to runtime resources.
interface IAsset
{
	/// Unique asset identifier (persistent across sessions).
	Guid AssetId { get; }

	/// Asset name (typically filename without extension).
	String Name { get; }

	/// Asset type identifier (e.g., "scene", "material", "mesh").
	StringView AssetType { get; }

	/// File path relative to project root.
	String Path { get; }

	/// Whether the asset has unsaved changes.
	bool IsDirty { get; }

	/// Mark the asset as modified.
	void MarkDirty();

	/// Clear dirty flag (after save).
	void ClearDirty();

	/// Save asset to file.
	Result<void> Save(StringView path = default);
}
