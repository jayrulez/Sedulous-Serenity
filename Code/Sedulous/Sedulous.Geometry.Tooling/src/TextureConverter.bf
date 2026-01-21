using System;
using Sedulous.Models;
using Sedulous.Imaging;
using Sedulous.Renderer;
using System.IO;
using System.IO;
using Sedulous.Renderer.Resources;
using Sedulous.Textures.Resources;

namespace Sedulous.Geometry.Tooling;

/// Converts ModelTexture to TextureResource.
static class TextureConverter
{
	/// Creates a TextureResource from a ModelTexture.
	/// Returns null if the texture has no valid data.
	public static TextureResource Convert(ModelTexture modelTexture)
	{
		if (modelTexture == null)
			return null;

		Image image = null;

		// Check if texture has decoded pixel data
		if (modelTexture.Width > 0 && modelTexture.Height > 0 && modelTexture.HasEmbeddedData)
		{
			let format = ConvertPixelFormat(modelTexture.PixelFormat);
			let srcData = Span<uint8>(modelTexture.GetData(), modelTexture.GetDataSize());
			let data = new uint8[srcData.Length];
			defer delete data;
			srcData.CopyTo(data);
			image = new Image((uint32)modelTexture.Width, (uint32)modelTexture.Height, format, data);
		}

		if (image == null)
			return null;

		let textureRes = new TextureResource(image, true);
		textureRes.Name.Set(modelTexture.Name.IsEmpty ? modelTexture.Uri : modelTexture.Name);
		textureRes.SetupFor3D();

		return textureRes;
	}

	/// Creates a TextureResource from a ModelTexture with fallback to file loading.
	/// Uses the provided ImageLoader for external textures.
	public static TextureResource Convert(ModelTexture modelTexture, ImageLoader imageLoader, StringView basePath)
	{
		if (modelTexture == null)
			return null;

		Image image = null;

		// Check if texture has decoded pixel data
		if (modelTexture.Width > 0 && modelTexture.Height > 0 && modelTexture.HasEmbeddedData)
		{
			let format = ConvertPixelFormat(modelTexture.PixelFormat);
			let srcData = Span<uint8>(modelTexture.GetData(), modelTexture.GetDataSize());
			let data = new uint8[srcData.Length];
			defer delete data;
			srcData.CopyTo(data);
			image = new Image((uint32)modelTexture.Width, (uint32)modelTexture.Height, format, data);
		}
		// Fallback to loading from file if we have a URI
		else if (!modelTexture.Uri.IsEmpty && imageLoader != null)
		{
			let fullPath = scope $"{Directory.GetCurrentDirectory(.. scope .())}/";
			if (!basePath.IsEmpty)
			{
				fullPath.Append(basePath);
				if (!fullPath.EndsWith('/') && !fullPath.EndsWith('\\'))
					fullPath.Append('/');
			}
			fullPath.Append(modelTexture.Uri);
			fullPath.Replace('/', Path.DirectorySeparatorChar);

			if (imageLoader.LoadFromFile(fullPath) case .Ok(var loadInfo))
			{
				defer loadInfo.Dispose();
				image = new Image(loadInfo.Width, loadInfo.Height, loadInfo.Format, loadInfo.Data);
			}
		}

		if (image == null)
			return null;

		let textureRes = new TextureResource(image, true);
		textureRes.Name.Set(modelTexture.Name.IsEmpty ? modelTexture.Uri : modelTexture.Name);
		textureRes.SetupFor3D();

		return textureRes;
	}

	/// Converts TexturePixelFormat to Image.PixelFormat.
	private static Image.PixelFormat ConvertPixelFormat(TexturePixelFormat format)
	{
		switch (format)
		{
		case .R8:    return .R8;
		case .RG8:   return .RG8;
		case .RGB8:  return .RGB8;
		case .RGBA8: return .RGBA8;
		case .BGR8:  return .BGR8;
		case .BGRA8: return .BGRA8;
		default:     return .RGBA8;
		}
	}
}
