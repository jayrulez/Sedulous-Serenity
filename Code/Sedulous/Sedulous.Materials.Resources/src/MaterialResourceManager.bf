using Sedulous.Resources;
using System;
using System.IO;
namespace Sedulous.Materials.Resources;

class MaterialResourceManager : ResourceManager<MaterialResource>
{
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