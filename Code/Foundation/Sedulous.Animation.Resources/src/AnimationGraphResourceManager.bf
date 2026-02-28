using System;
using System.IO;
using Sedulous.Resources;

namespace Sedulous.Animation.Resources;

/// Resource manager for AnimationGraphResource.
class AnimationGraphResourceManager : ResourceManager<AnimationGraphResource>
{
	protected override Result<AnimationGraphResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		if (path.EndsWith(".animgraph"))
		{
			if (AnimationGraphResource.LoadFromFile(path) case .Ok(let resource))
				return .Ok(resource);
			return .Err(.ReadError);
		}

		return .Err(.NotSupported);
	}

	protected override Result<AnimationGraphResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(AnimationGraphResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}
}
