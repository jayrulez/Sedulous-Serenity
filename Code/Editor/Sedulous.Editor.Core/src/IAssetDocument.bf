namespace Sedulous.Editor.Core;

using System;
using Sedulous.UI;

/// Interface for asset documents (open assets being edited).
interface IAssetDocument : IDisposable
{
	/// The asset being edited.
	IAsset Asset { get; }

	/// Document unique ID (for tab management).
	Guid DocumentId { get; }

	/// Whether document has unsaved changes.
	bool IsDirty { get; }

	/// Get display title (asset name + dirty indicator).
	void GetTitle(String outTitle);

	/// Create the UI content for this document.
	UIElement CreateContent();

	/// Called when document becomes active (tab selected).
	void OnActivate();

	/// Called when document becomes inactive.
	void OnDeactivate();

	/// Called before closing - return false to cancel.
	bool OnClosing();

	/// Save the document.
	Result<void> Save();

	/// Save to a new path.
	Result<void> SaveAs(StringView path);

	/// Undo last operation.
	void Undo();

	/// Redo last undone operation.
	void Redo();

	/// Whether undo is available.
	bool CanUndo { get; }

	/// Whether redo is available.
	bool CanRedo { get; }
}
