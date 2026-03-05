using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Animation;
using Sedulous.OpenDDL;
using Sedulous.Serialization.OpenDDL;

namespace Sedulous.Animation.Resources;

/// Resource manager for SkeletonResource.
class SkeletonResourceManager : ResourceManager<SkeletonResource>
{
	protected override Result<SkeletonResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		if (path.EndsWith(".skeleton"))
		{
			if (SkeletonResource.LoadFromFile(path) case .Ok(let resource))
			{
				resource.AddRef(); // Manager's ownership ref — released in Unload
				return .Ok(resource);
			}
			return .Err(.ReadError);
		}

		return .Err(.NotSupported);
	}

	protected override Result<SkeletonResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(SkeletonResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	protected override Result<void, ResourceLoadError> ReloadResource(SkeletonResource resource, StringView path)
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
		if (version > SkeletonResource.FileVersion)
			return .Err(.InvalidFormat);

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != SkeletonResource.FileType)
			return .Err(.InvalidFormat);

		resource.Serialize(reader);
		return .Ok;
	}

	/// Create a skeleton resource from an existing Skeleton.
	/// The resource takes ownership of the skeleton.
	public SkeletonResource CreateFromSkeleton(Skeleton skeleton, StringView name = "")
	{
		let resource = new SkeletonResource(skeleton, true);
		resource.Name.Set(name);
		return resource;
	}
}
