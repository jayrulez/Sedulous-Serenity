using Sedulous.Resources;
using System;
using System.IO;
namespace Sedulous.Materials.Resources;

class MaterialResourceManager : ResourceManager<MaterialResource>
{
	protected override Result<MaterialResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		switch (MaterialResource.LoadFromFile(path))
		{
		case .Ok(let resource):
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
}