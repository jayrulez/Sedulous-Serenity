using System;
using System.IO;
using System.Collections;
using Sedulous.Resources;

namespace Sedulous.Engine.Scenes;

/// Resource manager for loading SceneResource files via the ResourceSystem.
class SceneResourceManager : ResourceManager<SceneResource>
{
	protected override Result<SceneResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		let resource = new SceneResource();

		// Scene auto-registers all [Component] serializers in its constructor
		if (resource.Load(path) case .Err)
		{
			delete resource;
			return .Err(.ReadError);
		}

		return .Ok(resource);
	}

	protected override Result<SceneResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(SceneResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}
}
