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
		// Handle .texture binary files (saved by TextureResource.SaveToFile)
		if (path.EndsWith(".texture"))
		{
			if (TextureResource.LoadFromFile(path) case .Ok(let resource))
			{
				resource.AddRef(); // Manager's ownership ref — released in Unload
				return .Ok(resource);
			}
			return .Err(.ReadError);
		}

		// Load standard image files via ImageLoaderFactory
		if (ImageLoaderFactory.LoadImage(path) case .Ok(let image))
		{
			let resource = new TextureResource(image, true);
			resource.Name.Set(path);
			resource.SetupFor3D();  // Default setup
			resource.AddRef(); // Manager's ownership ref — released in Unload
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
			resource.AddRef(); // Manager's ownership ref — released in Unload
			return .Ok(resource);
		}

		return .Err(.NotSupported);
	}

	public override void Unload(TextureResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	protected override Result<void, ResourceLoadError> ReloadResource(TextureResource resource, StringView path)
	{
		if (path.EndsWith(".texture"))
		{
			// Reload .texture binary file — mirrors LoadFromFile logic
			if (TextureResource.LoadFromFile(path) case .Ok(let reloaded))
			{
				// Transfer data from reloaded into existing resource
				resource.SetImage(reloaded.[Friend]mImage, true);
				reloaded.[Friend]mOwnsImage = false; // Prevent double-delete
				resource.Name.Set(reloaded.Name);
				resource.MinFilter = reloaded.MinFilter;
				resource.MagFilter = reloaded.MagFilter;
				resource.WrapU = reloaded.WrapU;
				resource.WrapV = reloaded.WrapV;
				resource.WrapW = reloaded.WrapW;
				resource.GenerateMipmaps = reloaded.GenerateMipmaps;
				resource.Anisotropy = reloaded.Anisotropy;
				delete reloaded;
				return .Ok;
			}
			return .Err(.ReadError);
		}

		// Reload standard image files via ImageLoaderFactory
		if (ImageLoaderFactory.LoadImage(path) case .Ok(let image))
		{
			resource.SetImage(image, true);
			return .Ok;
		}

		return .Err(.NotFound);
	}
}
