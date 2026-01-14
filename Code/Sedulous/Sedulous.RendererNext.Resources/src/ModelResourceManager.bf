namespace Sedulous.RendererNext.Resources;

using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Models;
using Sedulous.Models.GLTF;

/// Resource manager for ModelResource.
/// Supports loading GLTF/GLB files.
class ModelResourceManager : ResourceManager<ModelResource>
{
	protected override Result<ModelResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		// Check file extension
		String ext = scope .();
		Path.GetExtension(path, ext);

		if (ext.Equals(".gltf", .OrdinalIgnoreCase) || ext.Equals(".glb", .OrdinalIgnoreCase))
		{
			// Load GLTF/GLB
			let model = new Model();
			let loader = scope GltfLoader();

			if (loader.Load(path, model) == .Ok)
			{
				let resource = new ModelResource(model, true);
				resource.Name.Set(path);
				return .Ok(resource);
			}

			delete model;
			return .Err(.InvalidFormat);
		}

		return .Err(.NotSupported);
	}

	protected override Result<ModelResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		// GLTF loading from memory not supported
		return .Err(.NotSupported);
	}

	public override void Unload(ModelResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}
}
