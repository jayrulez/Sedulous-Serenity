using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.OpenDDL;
using Sedulous.Serialization.OpenDDL;

namespace Sedulous.Animation.Resources;

/// Resource manager for AnimationClipResource.
class AnimationClipResourceManager : ResourceManager<AnimationClipResource>
{
	protected override Result<AnimationClipResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		if (path.EndsWith(".animation"))
		{
			if (AnimationClipResource.LoadFromFile(path) case .Ok(let resource))
			{
				resource.AddRef(); // Manager's ownership ref — released in Unload
				return .Ok(resource);
			}
			return .Err(.ReadError);
		}

		return .Err(.NotSupported);
	}

	protected override Result<AnimationClipResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(AnimationClipResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	protected override Result<void, ResourceLoadError> ReloadResource(AnimationClipResource resource, StringView path)
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
		if (version > AnimationClipResource.FileVersion)
			return .Err(.InvalidFormat);

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != AnimationClipResource.FileType)
			return .Err(.InvalidFormat);

		resource.Serialize(reader);
		return .Ok;
	}
}
