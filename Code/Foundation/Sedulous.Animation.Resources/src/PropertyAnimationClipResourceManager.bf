using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.OpenDDL;
using Sedulous.Serialization.OpenDDL;

namespace Sedulous.Animation.Resources;

/// Resource manager for PropertyAnimationClipResource.
class PropertyAnimationClipResourceManager : ResourceManager<PropertyAnimationClipResource>
{
	protected override Result<PropertyAnimationClipResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		if (path.EndsWith(".propanimation"))
		{
			if (PropertyAnimationClipResource.LoadFromFile(path) case .Ok(let resource))
			{
				resource.AddRef(); // Manager's ownership ref — released in Unload
				return .Ok(resource);
			}
			return .Err(.ReadError);
		}

		return .Err(.NotSupported);
	}

	protected override Result<PropertyAnimationClipResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(PropertyAnimationClipResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	protected override Result<void, ResourceLoadError> ReloadResource(PropertyAnimationClipResource resource, StringView path)
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
		if (version > PropertyAnimationClipResource.FileVersion)
			return .Err(.InvalidFormat);

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != PropertyAnimationClipResource.FileType)
			return .Err(.InvalidFormat);

		resource.Serialize(reader);
		return .Ok;
	}
}
