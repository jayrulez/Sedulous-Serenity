using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Geometry;

namespace Sedulous.Framework.Renderer;

/// Resource manager for MeshResource.
/// Note: Direct file loading is not implemented - use ModelLoader and converters instead.
class MeshResourceManager : ResourceManager<MeshResource>
{
	protected override Result<MeshResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		// Mesh loading from file requires model loading (GLTF, OBJ, etc.)
		// Use Sedulous.Models and Sedulous.Geometry.Tooling for that
		return .Err(.NotSupported);
	}

	protected override Result<MeshResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		// Not implemented - use model loaders
		return .Err(.NotSupported);
	}

	public override void Unload(MeshResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	/// Registers a pre-created mesh resource.
	public ResourceHandle<MeshResource> Register(MeshResource resource)
	{
		resource.AddRef();
		return .(resource);
	}
}
