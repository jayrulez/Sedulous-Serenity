namespace Sedulous.Editor.Core;

using System;
using System.Collections;
using Sedulous.Foundation.Core;

/// Manages open asset documents.
class DocumentManager : IDisposable
{
	private List<IAssetDocument> mDocuments = new .() ~ DeleteContainerAndDisposeItems!(_);
	private IAssetDocument mActiveDocument;
	private AssetRegistry mAssetRegistry;

	// Events
	private EventAccessor<delegate void(IAssetDocument)> mDocumentOpened = new .() ~ delete _;
	private EventAccessor<delegate void(IAssetDocument)> mDocumentClosed = new .() ~ delete _;
	private EventAccessor<delegate void(IAssetDocument)> mActiveDocumentChanged = new .() ~ delete _;
	private EventAccessor<delegate void(IAssetDocument)> mDocumentDirtyChanged = new .() ~ delete _;

	/// Currently active document.
	public IAssetDocument ActiveDocument => mActiveDocument;

	/// Number of open documents.
	public int DocumentCount => mDocuments.Count;

	/// All open documents.
	public List<IAssetDocument>.Enumerator OpenDocuments => mDocuments.GetEnumerator();

	/// Event fired when a document is opened.
	public EventAccessor<delegate void(IAssetDocument)> DocumentOpened => mDocumentOpened;

	/// Event fired when a document is closed.
	public EventAccessor<delegate void(IAssetDocument)> DocumentClosed => mDocumentClosed;

	/// Event fired when the active document changes.
	public EventAccessor<delegate void(IAssetDocument)> ActiveDocumentChanged => mActiveDocumentChanged;

	/// Event fired when a document's dirty state changes.
	public EventAccessor<delegate void(IAssetDocument)> DocumentDirtyChanged => mDocumentDirtyChanged;

	public this(AssetRegistry assetRegistry)
	{
		mAssetRegistry = assetRegistry;
	}

	public void Dispose()
	{
	}

	/// Open an asset for editing.
	public Result<IAssetDocument> Open(IAsset asset)
	{
		if (asset == null)
			return .Err;

		// Check if already open
		for (let doc in mDocuments)
		{
			if (doc.Asset.AssetId == asset.AssetId)
			{
				SetActive(doc);
				return doc;
			}
		}

		// Create document via asset registry
		if (mAssetRegistry == null)
			return .Err;

		let handler = mAssetRegistry.GetHandler(asset.AssetType);
		if (handler == null)
			return .Err;

		if (handler.CreateDocument(asset) case .Ok(let document))
		{
			mDocuments.Add(document);
			mDocumentOpened.[Friend]Invoke(document);
			SetActive(document);
			return document;
		}

		return .Err;
	}

	/// Open asset by path.
	public Result<IAssetDocument> OpenPath(StringView path)
	{
		if (mAssetRegistry == null)
			return .Err;

		// Check if already open by path
		for (let doc in mDocuments)
		{
			if (doc.Asset.Path == path)
			{
				SetActive(doc);
				return doc;
			}
		}

		// Load asset via registry
		let handler = mAssetRegistry.GetHandlerForExtension(path);
		if (handler == null)
			return .Err;

		if (handler.Load(path) case .Ok(let asset))
		{
			return Open(asset);
		}

		return .Err;
	}

	/// Close a document.
	/// Returns true if closed, false if cancelled.
	public bool Close(IAssetDocument document)
	{
		if (document == null)
			return true;

		// Allow document to cancel closing
		if (!document.OnClosing())
			return false;

		// Remove from list
		let index = mDocuments.IndexOf(document);
		if (index < 0)
			return true;

		mDocuments.RemoveAt(index);

		// Update active document if needed
		if (mActiveDocument == document)
		{
			if (mDocuments.Count > 0)
			{
				// Activate the previous document, or the first one
				let newIndex = Math.Min(index, mDocuments.Count - 1);
				SetActive(mDocuments[newIndex]);
			}
			else
			{
				mActiveDocument = null;
				mActiveDocumentChanged.[Friend]Invoke(null);
			}
		}

		mDocumentClosed.[Friend]Invoke(document);
		delete document;

		return true;
	}

	/// Close all documents.
	/// Returns true if all closed, false if any cancelled.
	public bool CloseAll()
	{
		// Close in reverse order
		while (mDocuments.Count > 0)
		{
			if (!Close(mDocuments.Back))
				return false;
		}
		return true;
	}

	/// Close all documents except the specified one.
	public bool CloseAllExcept(IAssetDocument exceptDocument)
	{
		List<IAssetDocument> toClose = scope .();
		for (let doc in mDocuments)
		{
			if (doc != exceptDocument)
				toClose.Add(doc);
		}

		for (let doc in toClose)
		{
			if (!Close(doc))
				return false;
		}
		return true;
	}

	/// Set active document.
	public void SetActive(IAssetDocument document)
	{
		if (mActiveDocument == document)
			return;

		// Deactivate previous
		if (mActiveDocument != null)
			mActiveDocument.OnDeactivate();

		mActiveDocument = document;

		// Activate new
		if (mActiveDocument != null)
			mActiveDocument.OnActivate();

		mActiveDocumentChanged.[Friend]Invoke(mActiveDocument);
	}

	/// Save active document.
	public Result<void> SaveActive()
	{
		if (mActiveDocument == null)
			return .Err;

		return mActiveDocument.Save();
	}

	/// Save all dirty documents.
	public Result<void> SaveAll()
	{
		for (let doc in mDocuments)
		{
			if (doc.IsDirty)
			{
				if (doc.Save() case .Err)
					return .Err;
			}
		}
		return .Ok;
	}

	/// Check if any documents have unsaved changes.
	public bool HasUnsavedChanges()
	{
		for (let doc in mDocuments)
		{
			if (doc.IsDirty)
				return true;
		}
		return false;
	}

	/// Get document by asset ID.
	public IAssetDocument GetByAssetId(Guid assetId)
	{
		for (let doc in mDocuments)
		{
			if (doc.Asset.AssetId == assetId)
				return doc;
		}
		return null;
	}

	/// Get document at index.
	public IAssetDocument GetAt(int index)
	{
		if (index >= 0 && index < mDocuments.Count)
			return mDocuments[index];
		return null;
	}

	/// Get index of document.
	public int IndexOf(IAssetDocument document)
	{
		return mDocuments.IndexOf(document);
	}
}
