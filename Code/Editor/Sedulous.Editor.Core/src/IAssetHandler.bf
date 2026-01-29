namespace Sedulous.Editor.Core;

using System;
using Sedulous.Drawing;
using System.Collections;

/// Interface for asset type handlers.
/// Each editor module provides handlers for its supported asset types.
interface IAssetHandler : IDisposable
{
	/// Asset type identifier (e.g., "scene", "material").
	StringView AssetType { get; }

	/// File extensions this handler supports (e.g., ".scene", ".scn").
	void GetExtensions(List<String> outExtensions);

	/// Display name for UI.
	StringView DisplayName { get; }

	/// Icon for asset browser (optional, may be null).
	IImageData Icon { get; }

	/// Create a new empty asset.
	Result<IAsset> CreateNew(StringView name);

	/// Load asset from file.
	Result<IAsset> Load(StringView path);

	/// Save asset to file.
	Result<void> Save(IAsset asset, StringView path);

	/// Create a document for editing this asset.
	Result<IAssetDocument> CreateDocument(IAsset asset);

	/// Get the transformer for this asset type (may be null if no transform needed).
	IAssetTransformer Transformer { get; }

	/// Check if this handler supports the given file extension.
	bool SupportsExtension(StringView @extension);
}

/// Base class for asset handlers with common functionality.
abstract class AssetHandler : IAssetHandler
{
	protected List<String> mExtensions = new .() ~ DeleteContainerAndItems!(_);
	protected IAssetTransformer mTransformer;

	public abstract StringView AssetType { get; }
	public abstract StringView DisplayName { get; }
	public virtual IImageData Icon => null;
	public IAssetTransformer Transformer => mTransformer;

	public virtual void Dispose()
	{
		if (mTransformer != null)
			delete mTransformer;
	}

	public void GetExtensions(List<String> outExtensions)
	{
		for (let ext in mExtensions)
			outExtensions.Add(new String(ext));
	}

	public bool SupportsExtension(StringView @extension)
	{
		for (let ext in mExtensions)
		{
			if (ext.Equals(@extension, .OrdinalIgnoreCase))
				return true;
		}
		return false;
	}

	public abstract Result<IAsset> CreateNew(StringView name);
	public abstract Result<IAsset> Load(StringView path);
	public abstract Result<void> Save(IAsset asset, StringView path);
	public abstract Result<IAssetDocument> CreateDocument(IAsset asset);

	/// Add a supported file extension.
	protected void AddExtension(StringView @extension)
	{
		mExtensions.Add(new String(@extension));
	}

	/// Set the transformer for this asset type.
	protected void SetTransformer(IAssetTransformer transformer)
	{
		if (mTransformer != null)
			delete mTransformer;
		mTransformer = transformer;
	}
}
