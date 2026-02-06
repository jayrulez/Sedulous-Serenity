namespace Sedulous.Resources;

using System;
using System.Collections;
using System.Threading;

/// Default implementation of IResourceRegistry using in-memory dictionaries.
/// Thread-safe via Monitor. Can be populated programmatically or from a manifest.
class ResourceRegistry : IResourceRegistry
{
	private Monitor mMonitor = new .() ~ delete _;
	private Dictionary<Guid, String> mIdToPath = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<String, Guid> mPathToId = new .() ~ delete _; // Keys shared with mIdToPath values

	/// Registers a resource mapping (GUID <-> path).
	/// Replaces any existing mapping for the same GUID.
	public void Register(Guid id, StringView path)
	{
		using (mMonitor.Enter())
		{
			// Remove old mapping if exists
			if (mIdToPath.TryGetValue(id, let existingPath))
			{
				mPathToId.Remove(existingPath);
				delete existingPath;
				mIdToPath.Remove(id);
			}

			let pathStr = new String(path);
			mIdToPath[id] = pathStr;
			mPathToId[pathStr] = id; // Shares the same String object
		}
	}

	/// Unregisters a resource mapping by GUID.
	public void Unregister(Guid id)
	{
		using (mMonitor.Enter())
		{
			if (mIdToPath.TryGetValue(id, let path))
			{
				mPathToId.Remove(path);
				delete path;
				mIdToPath.Remove(id);
			}
		}
	}

	/// Gets the number of registered mappings.
	public int Count
	{
		get
		{
			using (mMonitor.Enter())
				return mIdToPath.Count;
		}
	}

	public bool TryResolvePath(Guid id, String outPath)
	{
		using (mMonitor.Enter())
		{
			if (mIdToPath.TryGetValue(id, let path))
			{
				outPath.Set(path);
				return true;
			}
			return false;
		}
	}

	public bool TryResolveId(StringView path, out Guid outId)
	{
		using (mMonitor.Enter())
		{
			for (let kv in mPathToId)
			{
				if (StringView(kv.key) == path)
				{
					outId = kv.value;
					return true;
				}
			}
			outId = .();
			return false;
		}
	}
}
