using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Geometry;

namespace Sedulous.Geometry.Resources;

/// Resource manager for SkinnedMeshResource.
/// Note: Direct file loading is not implemented - use ModelLoader and converters instead.
class SkinnedMeshResourceManager : ResourceManager<SkinnedMeshResource>
{
	protected override Result<SkinnedMeshResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		// Skinned mesh loading from file requires model loading (GLTF, etc.)
		// Use Sedulous.Models and Sedulous.Geometry.Tooling for that
		return .Err(.NotSupported);
	}

	protected override Result<SkinnedMeshResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		// Not implemented - use model loaders
		return .Err(.NotSupported);
	}

	public override void Unload(SkinnedMeshResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	/// Registers a pre-created skinned mesh resource.
	public ResourceHandle<SkinnedMeshResource> Register(SkinnedMeshResource resource)
	{
		resource.AddRef();
		return .(resource);
	}
}
