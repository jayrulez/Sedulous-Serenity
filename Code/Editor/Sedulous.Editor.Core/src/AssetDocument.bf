namespace Sedulous.Editor.Core;

using System;
using Sedulous.UI;

/// Base class for asset documents.
abstract class AssetDocument : IAssetDocument
{
	protected IAsset mAsset;
	protected Guid mDocumentId;
	protected CommandHistory mHistory = new .() ~ delete _;
	protected UIElement mContent ~ delete _;
	protected bool mIsActive;

	/// The asset being edited.
	public IAsset Asset => mAsset;

	/// Document unique ID.
	public Guid DocumentId => mDocumentId;

	/// Whether document has unsaved changes.
	public bool IsDirty => mAsset?.IsDirty ?? false;

	/// Whether undo is available.
	public bool CanUndo => mHistory.CanUndo;

	/// Whether redo is available.
	public bool CanRedo => mHistory.CanRedo;

	/// The command history for this document.
	public CommandHistory History => mHistory;

	/// Whether this document is currently active.
	public bool IsActive => mIsActive;

	public this(IAsset asset)
	{
		mAsset = asset;
		mDocumentId = Guid.Create();
	}

	public virtual void Dispose()
	{
	}

	/// Get display title (asset name + dirty indicator).
	public virtual void GetTitle(String outTitle)
	{
		if (mAsset != null)
		{
			outTitle.Set(mAsset.Name);
			if (mAsset.IsDirty)
				outTitle.Append("*");
		}
		else
		{
			outTitle.Set("Untitled");
		}
	}

	/// Create the UI content for this document.
	public UIElement CreateContent()
	{
		if (mContent == null)
			mContent = CreateContentInternal();
		return mContent;
	}

	/// Override to create document-specific UI content.
	protected abstract UIElement CreateContentInternal();

	/// Called when document becomes active.
	public virtual void OnActivate()
	{
		mIsActive = true;
	}

	/// Called when document becomes inactive.
	public virtual void OnDeactivate()
	{
		mIsActive = false;
	}

	/// Called before closing - return false to cancel.
	public virtual bool OnClosing()
	{
		// Default: allow closing (caller should prompt to save if dirty)
		return true;
	}

	/// Save the document.
	public virtual Result<void> Save()
	{
		if (mAsset == null)
			return .Err;

		return mAsset.Save();
	}

	/// Save to a new path.
	public virtual Result<void> SaveAs(StringView path)
	{
		if (mAsset == null)
			return .Err;

		return mAsset.Save(path);
	}

	/// Undo last operation.
	public void Undo()
	{
		mHistory.Undo();
	}

	/// Redo last undone operation.
	public void Redo()
	{
		mHistory.Redo();
	}

	/// Execute a command through this document's history.
	public void ExecuteCommand(ICommand command)
	{
		mHistory.Execute(command);
		mAsset?.MarkDirty();
	}

	/// Begin a compound command.
	public void BeginCompoundCommand(StringView description)
	{
		mHistory.BeginCompound(description);
	}

	/// End a compound command.
	public void EndCompoundCommand()
	{
		mHistory.EndCompound();
	}
}
