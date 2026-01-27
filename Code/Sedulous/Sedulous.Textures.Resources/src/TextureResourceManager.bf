using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Imaging;

namespace Sedulous.Textures.Resources;

/// Resource manager for TextureResource.
/// Uses ImageLoaderFactory to load images.
class TextureResourceManager : ResourceManager<TextureResource>
{
	protected override Result<TextureResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		// Load image using the factory
		if (ImageLoaderFactory.LoadImage(path) case .Ok(let image))
		{
			let resource = new TextureResource(image, true);
			resource.Name.Set(path);
			resource.SetupFor3D();  // Default setup
			return .Ok(resource);
		}

		return .Err(.NotFound);
	}

	protected override Result<TextureResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		// Read stream into buffer
		let data = new uint8[memory.Length];
		defer delete data;
		memory.TryRead(data);

		if (ImageLoaderFactory.LoadImageFromMemory(data) case .Ok(let image))
		{
			let resource = new TextureResource(image, true);
			resource.SetupFor3D();
			return .Ok(resource);
		}

		return .Err(.NotSupported);
	}

	public override void Unload(TextureResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}
}
