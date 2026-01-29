namespace Sedulous.Editor.Core;

using System;
using System.IO;

/// Base class for all editor assets.
abstract class Asset : IAsset, IDisposable
{
	protected Guid mAssetId;
	protected String mName = new .() ~ delete _;
	protected String mPath = new .() ~ delete _;
	protected bool mIsDirty;

	/// Unique asset identifier.
	public Guid AssetId => mAssetId;

	/// Asset name.
	public String Name => mName;

	/// Asset type identifier (must be overridden).
	public abstract StringView AssetType { get; }

	/// File path relative to project root.
	public String Path => mPath;

	/// Whether the asset has unsaved changes.
	public bool IsDirty => mIsDirty;

	/// Creates a new asset with a new ID.
	public this()
	{
		mAssetId = Guid.Create();
	}

	/// Creates an asset with a specific ID (for loading).
	public this(Guid assetId)
	{
		mAssetId = assetId;
	}

	public virtual void Dispose()
	{
	}

	/// Mark the asset as modified.
	public void MarkDirty()
	{
		mIsDirty = true;
	}

	/// Clear dirty flag (after save).
	public void ClearDirty()
	{
		mIsDirty = false;
	}

	/// Load asset from file.
	public abstract Result<void> Load(StringView path);

	/// Save asset to file.
	public virtual Result<void> Save(StringView path = default)
	{
		let savePath = path.IsEmpty ? mPath : scope String(path);
		if (savePath.IsEmpty)
			return .Err;

		if (SaveInternal(savePath) case .Err)
			return .Err;

		if (!path.IsEmpty)
			mPath.Set(path);

		ClearDirty();
		return .Ok;
	}

	/// Internal save implementation (must be overridden).
	protected abstract Result<void> SaveInternal(StringView path);

	/// Create default/empty asset data.
	public abstract void CreateDefault();

	/// Set the asset name.
	public void SetName(StringView name)
	{
		mName.Set(name);
	}

	/// Set the asset path.
	public void SetPath(StringView path)
	{
		mPath.Set(path);

		// Extract name from path if not set
		if (mName.IsEmpty)
		{
			let fileName = System.IO.Path.GetFileNameWithoutExtension(path, .. scope .());
			mName.Set(fileName);
		}
	}
}
