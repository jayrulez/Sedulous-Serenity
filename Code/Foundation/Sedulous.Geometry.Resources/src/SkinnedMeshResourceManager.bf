using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Geometry;
using Sedulous.OpenDDL;
using Sedulous.Serialization.OpenDDL;

namespace Sedulous.Geometry.Resources;

/// Resource manager for SkinnedMeshResource.
/// Note: Direct file loading is not implemented - use ModelLoader and converters instead.
class SkinnedMeshResourceManager : ResourceManager<SkinnedMeshResource>
{
	protected override Result<SkinnedMeshResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		switch (SkinnedMeshResource.LoadFromFile(path))
		{
		case .Ok(let resource):
			resource.AddRef(); // Manager's ownership ref — released in Unload
			return .Ok(resource);
		case .Err:
			return .Err(.ReadError);
		}
	}

	protected override Result<SkinnedMeshResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(SkinnedMeshResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	protected override Result<void, ResourceLoadError> ReloadResource(SkinnedMeshResource resource, StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err(.NotFound);

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err(.InvalidFormat);

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != SkinnedMeshResource.BundleFileType && fileType != SkinnedMeshResource.FileType)
			return .Err(.InvalidFormat);

		resource.Serialize(reader);
		return .Ok;
	}

	/// Registers a pre-created skinned mesh resource.
	public ResourceHandle<SkinnedMeshResource> Register(SkinnedMeshResource resource)
	{
		resource.AddRef();
		return .(resource);
	}
}
