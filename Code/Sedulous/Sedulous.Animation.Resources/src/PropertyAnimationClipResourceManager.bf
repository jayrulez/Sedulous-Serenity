using System;
using System.IO;
using Sedulous.Resources;

namespace Sedulous.Animation.Resources;

/// Resource manager for PropertyAnimationClipResource.
class PropertyAnimationClipResourceManager : ResourceManager<PropertyAnimationClipResource>
{
	protected override Result<PropertyAnimationClipResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		if (path.EndsWith(".propanimation"))
		{
			if (PropertyAnimationClipResource.LoadFromFile(path) case .Ok(let resource))
				return .Ok(resource);
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
}
