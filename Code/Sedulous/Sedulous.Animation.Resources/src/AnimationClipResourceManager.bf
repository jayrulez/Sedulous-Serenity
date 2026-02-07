using System;
using System.IO;
using Sedulous.Resources;

namespace Sedulous.Animation.Resources;

/// Resource manager for AnimationClipResource.
class AnimationClipResourceManager : ResourceManager<AnimationClipResource>
{
	protected override Result<AnimationClipResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		if (path.EndsWith(".animation"))
		{
			if (AnimationClipResource.LoadFromFile(path) case .Ok(let resource))
				return .Ok(resource);
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
}
