using System;
namespace Sedulous.RHI;

/// Describes a texture to be created.
struct TextureDescriptor
{
	/// Texture dimensionality.
	public TextureDimension Dimension;
	/// Pixel format.
	public TextureFormat Format;
	/// Width in texels.
	public uint32 Width;
	/// Height in texels (1 for 1D textures).
	public uint32 Height;
	/// Depth in texels (1 for 1D/2D textures).
	public uint32 Depth;
	/// Number of mip levels (1 for no mipmaps).
	public uint32 MipLevelCount;
	/// Number of array layers (6 for cubemaps).
	public uint32 ArrayLayerCount;
	/// Number of MSAA samples (1 for no MSAA).
	public uint32 SampleCount;
	/// How the texture will be used.
	public TextureUsage Usage;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Dimension = .Texture2D;
		Format = .RGBA8Unorm;
		Width = 1;
		Height = 1;
		Depth = 1;
		MipLevelCount = 1;
		ArrayLayerCount = 1;
		SampleCount = 1;
		Usage = .Sampled;
		Label = default;
	}

	/// Creates a descriptor for a 2D texture.
	public static Self Texture2D(uint32 width, uint32 height, TextureFormat format, TextureUsage usage, uint32 mipLevels = 1)
	{
		Self desc = .();
		desc.Dimension = .Texture2D;
		desc.Format = format;
		desc.Width = width;
		desc.Height = height;
		desc.MipLevelCount = mipLevels;
		desc.Usage = usage;
		return desc;
	}

	/// Creates a descriptor for a cubemap texture.
	public static Self Cubemap(uint32 size, TextureFormat format, TextureUsage usage, uint32 mipLevels = 1)
	{
		Self desc = .();
		desc.Dimension = .Texture2D;
		desc.Format = format;
		desc.Width = size;
		desc.Height = size;
		desc.ArrayLayerCount = 6;
		desc.MipLevelCount = mipLevels;
		desc.Usage = usage;
		return desc;
	}
}
