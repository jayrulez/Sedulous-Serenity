using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Geometry;

namespace Sedulous.Geometry.Resources;

/// Resource manager for MeshResource.
/// Note: Direct file loading is not implemented - use ModelLoader and converters instead.
class StaticMeshResourceManager : ResourceManager<StaticMeshResource>
{
	protected override Result<StaticMeshResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		switch (StaticMeshResource.LoadFromFile(path))
		{
		case .Ok(let resource):
			return .Ok(resource);
		case .Err:
			return .Err(.ReadError);
		}
	}

	protected override Result<StaticMeshResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(StaticMeshResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	/// Registers a pre-created mesh resource.
	public ResourceHandle<StaticMeshResource> Register(StaticMeshResource resource)
	{
		resource.AddRef();
		return .(resource);
	}
}
