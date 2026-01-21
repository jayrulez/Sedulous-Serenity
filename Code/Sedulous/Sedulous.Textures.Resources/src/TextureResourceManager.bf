using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Imaging;

namespace Sedulous.Textures.Resources;

/// Resource manager for TextureResource.
class TextureResourceManager : ResourceManager<TextureResource>
{
	private ImageLoader mImageLoader;

	public this(ImageLoader imageLoader)
	{
		mImageLoader = imageLoader;
	}

	protected override Result<TextureResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		if (mImageLoader == null)
			return .Err(.NotSupported);

		// Load image using the image loader
		if (mImageLoader.LoadFromFile(path) case .Ok(var loadInfo))
		{
			// Create Image from loaded data - Image constructor copies the data
			let image = new Image(loadInfo.Width, loadInfo.Height, loadInfo.Format, loadInfo.Data);
			loadInfo.Dispose();

			let resource = new TextureResource(image, true);
			resource.Name.Set(path);
			resource.SetupFor3D();  // Default setup
			return .Ok(resource);
		}

		return .Err(.NotFound);
	}

	protected override Result<TextureResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		if (mImageLoader == null)
			return .Err(.NotSupported);

		// Read stream into buffer
		let data = new uint8[memory.Length];
		defer delete data;
		memory.TryRead(data);

		if (mImageLoader.LoadFromMemory(data) case .Ok(var loadInfo))
		{
			let image = new Image(loadInfo.Width, loadInfo.Height, loadInfo.Format, loadInfo.Data);
			loadInfo.Dispose();

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
