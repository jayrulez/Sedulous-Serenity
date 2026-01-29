namespace Sedulous.Editor.Core;

using System;
using System.Collections;
using System.IO;

/// Asset entry in the database.
class AssetEntry
{
	/// Asset ID.
	public Guid AssetId;

	/// Asset path (relative to project root).
	public String Path = new .() ~ delete _;

	/// Asset type identifier.
	public String AssetType = new .() ~ delete _;

	/// Asset name.
	public String Name = new .() ~ delete _;

	/// Last modified time.
	public DateTime LastModified;

	/// Whether asset is loaded.
	public bool IsLoaded;

	/// Loaded asset (may be null if not loaded).
	public IAsset Asset;
}

/// Database of assets in a project.
class AssetDatabase : IDisposable
{
	private Dictionary<Guid, AssetEntry> mEntriesById = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	private Dictionary<String, AssetEntry> mEntriesByPath = new .() ~ {
		for (let kv in _)
			delete kv.key;
		delete _;
	};

	private String mProjectRoot = new .() ~ delete _;
	private List<String> mAssetFolders = new .() ~ DeleteContainerAndItems!(_);
	private AssetRegistry mRegistry;

	/// Event fired when an asset is added.
	public Event<delegate void(AssetEntry)> OnAssetAdded ~ _.Dispose();

	/// Event fired when an asset is removed.
	public Event<delegate void(AssetEntry)> OnAssetRemoved ~ _.Dispose();

	/// Event fired when an asset is modified.
	public Event<delegate void(AssetEntry)> OnAssetModified ~ _.Dispose();

	/// Number of assets in database.
	public int AssetCount => mEntriesById.Count;

	public this(AssetRegistry registry)
	{
		mRegistry = registry;
	}

	public void Dispose()
	{
	}

	/// Initialize with project root and asset folders.
	public void Initialize(StringView projectRoot, List<String> assetFolders)
	{
		mProjectRoot.Set(projectRoot);

		mAssetFolders.Clear();
		for (let folder in assetFolders)
			mAssetFolders.Add(new String(folder));
	}

	/// Scan project for all assets.
	public void Refresh()
	{
		// Mark all existing entries as potentially stale
		HashSet<Guid> foundIds = scope .();

		// Scan each asset folder
		for (let folder in mAssetFolders)
		{
			let fullPath = scope String();
			Path.InternalCombine(fullPath, mProjectRoot, folder);

			if (Directory.Exists(fullPath))
				ScanDirectory(fullPath, folder, foundIds);
		}

		// Remove entries that no longer exist
		List<Guid> toRemove = scope .();
		for (let kv in mEntriesById)
		{
			if (!foundIds.Contains(kv.key))
				toRemove.Add(kv.key);
		}

		for (let id in toRemove)
			RemoveEntry(id);
	}

	private void ScanDirectory(StringView absolutePath, StringView relativePath, HashSet<Guid> foundIds)
	{
		// Scan files
		for (let entry in Directory.EnumerateFiles(absolutePath))
		{
			let fileName = entry.GetFileName(.. scope .());
			let filePath = scope String();
			Path.InternalCombine(filePath, relativePath, fileName);

			// Check if we have a handler for this extension
			if (mRegistry.SupportsExtension(fileName))
			{
				let existingEntry = GetEntryByPath(filePath);
				if (existingEntry != null)
				{
					foundIds.Add(existingEntry.AssetId);
					// TODO: Check modification time and update if needed
				}
				else
				{
					// Create new entry
					let assetEntry = CreateEntry(filePath, fileName);
					if (assetEntry != null)
						foundIds.Add(assetEntry.AssetId);
				}
			}
		}

		// Scan subdirectories
		for (let entry in Directory.EnumerateDirectories(absolutePath))
		{
			let dirName = entry.GetFileName(.. scope .());
			let fullSubPath = scope String();
			Path.InternalCombine(fullSubPath, absolutePath, dirName);

			let relativeSubPath = scope String();
			Path.InternalCombine(relativeSubPath, relativePath, dirName);

			ScanDirectory(fullSubPath, relativeSubPath, foundIds);
		}
	}

	private AssetEntry CreateEntry(StringView path, StringView fileName)
	{
		let handler = mRegistry.GetHandlerForExtension(fileName);
		if (handler == null)
			return null;

		let entry = new AssetEntry();
		entry.AssetId = Guid.Create();
		entry.Path.Set(path);
		entry.AssetType.Set(handler.AssetType);
		Path.GetFileNameWithoutExtension(fileName, entry.Name);

		mEntriesById[entry.AssetId] = entry;
		mEntriesByPath[new String(path)] = entry;

		OnAssetAdded.Invoke(entry);

		return entry;
	}

	private void RemoveEntry(Guid assetId)
	{
		if (mEntriesById.TryGetValue(assetId, let entry))
		{
			OnAssetRemoved.Invoke(entry);

			// Remove from path mapping
			for (let kv in mEntriesByPath)
			{
				if (kv.value == entry)
				{
					let key = kv.key;
					mEntriesByPath.Remove(kv.key);
					delete key;
					break;
				}
			}

			// Unload if loaded
			if (entry.Asset != null)
			{
				delete entry.Asset;
				entry.Asset = null;
			}

			mEntriesById.Remove(assetId);
			delete entry;
		}
	}

	/// Get asset entry by path.
	public AssetEntry GetEntryByPath(StringView path)
	{
		for (let kv in mEntriesByPath)
		{
			if (kv.key == path)
				return kv.value;
		}
		return null;
	}

	/// Get asset entry by ID.
	public AssetEntry GetEntryById(Guid assetId)
	{
		if (mEntriesById.TryGetValue(assetId, let entry))
			return entry;
		return null;
	}

	/// Get loaded asset by path (loads if not already loaded).
	public Result<IAsset> GetAsset(StringView path)
	{
		let entry = GetEntryByPath(path);
		if (entry == null)
			return .Err;

		if (entry.Asset != null)
			return entry.Asset;

		// Load the asset
		let fullPath = scope String();
		Path.InternalCombine(fullPath, mProjectRoot, path);

		if (mRegistry.LoadAsset(fullPath) case .Ok(let asset))
		{
			entry.Asset = asset;
			entry.IsLoaded = true;
			return asset;
		}

		return .Err;
	}

	/// Get loaded asset by ID.
	public Result<IAsset> GetAsset(Guid assetId)
	{
		let entry = GetEntryById(assetId);
		if (entry == null)
			return .Err;

		return GetAsset(entry.Path);
	}

	/// Enumerate all asset entries.
	public Dictionary<Guid, AssetEntry>.ValueEnumerator AllEntries => mEntriesById.Values;

	/// Enumerate assets by type.
	public void GetEntriesByType(StringView assetType, List<AssetEntry> outEntries)
	{
		for (let kv in mEntriesById)
		{
			if (kv.value.AssetType == assetType)
				outEntries.Add(kv.value);
		}
	}

	/// Enumerate assets in folder.
	public void GetEntriesInFolder(StringView folderPath, List<AssetEntry> outEntries, bool recursive = false)
	{
		let normalizedFolder = scope String(folderPath);
		if (!normalizedFolder.EndsWith('/') && !normalizedFolder.EndsWith('\\'))
			normalizedFolder.Append('/');

		for (let kv in mEntriesById)
		{
			let entryPath = kv.value.Path;

			if (recursive)
			{
				if (entryPath.StartsWith(normalizedFolder, .OrdinalIgnoreCase))
					outEntries.Add(kv.value);
			}
			else
			{
				// Check if directly in folder (not in subfolder)
				if (entryPath.StartsWith(normalizedFolder, .OrdinalIgnoreCase))
				{
					let remaining = entryPath.Substring(normalizedFolder.Length);
					if (!remaining.Contains('/') && !remaining.Contains('\\'))
						outEntries.Add(kv.value);
				}
			}
		}
	}

	/// Unload an asset from memory.
	public void UnloadAsset(Guid assetId)
	{
		let entry = GetEntryById(assetId);
		if (entry != null && entry.Asset != null)
		{
			delete entry.Asset;
			entry.Asset = null;
			entry.IsLoaded = false;
		}
	}

	/// Unload all assets from memory.
	public void UnloadAll()
	{
		for (let kv in mEntriesById)
		{
			if (kv.value.Asset != null)
			{
				delete kv.value.Asset;
				kv.value.Asset = null;
				kv.value.IsLoaded = false;
			}
		}
	}
}
