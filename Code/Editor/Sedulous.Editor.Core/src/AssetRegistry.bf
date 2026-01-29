namespace Sedulous.Editor.Core;

using System;
using System.Collections;
using System.IO;

/// Information about a registered asset type.
struct AssetTypeInfo
{
	public StringView AssetType;
	public StringView DisplayName;
	public IAssetHandler Handler;
}

/// Central registry for asset type handlers.
class AssetRegistry : IDisposable
{
	private Dictionary<String, IAssetHandler> mHandlersByType = new .() ~ {
		for (let kv in _)
		{
			delete kv.key;
			delete kv.value;
		}
		delete _;
	};

	private Dictionary<String, IAssetHandler> mHandlersByExtension = new .() ~ {
		for (let kv in _)
			delete kv.key;
		delete _;
	};

	public void Dispose()
	{
	}

	/// Register an asset handler.
	public void RegisterHandler(IAssetHandler handler)
	{
		if (handler == null)
			return;

		// Register by type
		let typeKey = new String(handler.AssetType);
		mHandlersByType[typeKey] = handler;

		// Register by extensions
		List<String> extensions = scope .();
		handler.GetExtensions(extensions);

		for (let ext in extensions)
		{
			let extKey = new String(ext);
			mHandlersByExtension[extKey] = handler;
			delete ext;
		}
	}

	/// Unregister an asset handler.
	public void UnregisterHandler(StringView assetType)
	{
		for (let kv in mHandlersByType)
		{
			if (kv.key == assetType)
			{
				let handler = kv.value;

				// Remove extension mappings
				List<String> toRemove = scope .();
				for (let extKv in mHandlersByExtension)
				{
					if (extKv.value == handler)
						toRemove.Add(extKv.key);
				}
				for (let key in toRemove)
				{
					mHandlersByExtension.Remove(key);
					delete key;
				}

				// Remove type mapping
				let key = kv.key;
				mHandlersByType.Remove(kv.key);
				delete key;
				delete handler;
				break;
			}
		}
	}

	/// Get handler for asset type.
	public IAssetHandler GetHandler(StringView assetType)
	{
		for (let kv in mHandlersByType)
		{
			if (kv.key == assetType)
				return kv.value;
		}
		return null;
	}

	/// Get handler by file extension.
	public IAssetHandler GetHandlerForExtension(StringView pathOrExtension)
	{
		// Extract extension from path if needed
		String ext = scope .();
		if (pathOrExtension.Contains('.'))
		{
			Path.GetExtension(pathOrExtension, ext);
		}
		else
		{
			ext.Set(pathOrExtension);
		}

		// Normalize extension (ensure starts with .)
		if (!ext.StartsWith('.'))
			ext.Insert(0, ".");

		for (let kv in mHandlersByExtension)
		{
			if (kv.key.Equals(ext, .OrdinalIgnoreCase))
				return kv.value;
		}

		return null;
	}

	/// Check if an asset type is registered.
	public bool HasHandler(StringView assetType)
	{
		return GetHandler(assetType) != null;
	}

	/// Check if a file extension is supported.
	public bool SupportsExtension(StringView @extension)
	{
		return GetHandlerForExtension(@extension) != null;
	}

	/// Enumerate all registered asset types.
	public void GetAssetTypes(List<AssetTypeInfo> outTypes)
	{
		for (let kv in mHandlersByType)
		{
			outTypes.Add(.()
			{
				AssetType = kv.key,
				DisplayName = kv.value.DisplayName,
				Handler = kv.value
			});
		}
	}

	/// Get number of registered handlers.
	public int HandlerCount => mHandlersByType.Count;

	/// Load an asset from file using the appropriate handler.
	public Result<IAsset> LoadAsset(StringView path)
	{
		let handler = GetHandlerForExtension(path);
		if (handler == null)
			return .Err;

		return handler.Load(path);
	}

	/// Create a new asset of the specified type.
	public Result<IAsset> CreateAsset(StringView assetType, StringView name)
	{
		let handler = GetHandler(assetType);
		if (handler == null)
			return .Err;

		return handler.CreateNew(name);
	}
}
