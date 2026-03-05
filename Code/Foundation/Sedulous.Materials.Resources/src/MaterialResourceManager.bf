using Sedulous.Resources;
using System;
using System.IO;
using Sedulous.OpenDDL;
using Sedulous.Serialization.OpenDDL;

namespace Sedulous.Materials.Resources;

class MaterialResourceManager : ResourceManager<MaterialResource>
{
	protected override Result<MaterialResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		switch (MaterialResource.LoadFromFile(path))
		{
		case .Ok(let resource):
			resource.AddRef(); // Manager's ownership ref — released in Unload
			return .Ok(resource);
		case .Err:
			return .Err(.ReadError);
		}
	}

	protected override Result<MaterialResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return default;
	}

	public override void Unload(MaterialResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	protected override Result<void, ResourceLoadError> ReloadResource(MaterialResource resource, StringView path)
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
		if (version > MaterialResource.FileVersion)
			return .Err(.InvalidFormat);

		int32 fileType = 0;
		reader.Int32("fileType", ref fileType);
		if (fileType != MaterialResource.FileType)
			return .Err(.InvalidFormat);

		resource.Serialize(reader);
		return .Ok;
	}
}