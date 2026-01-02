using System;
namespace Sedulous.RHI;

/// Describes a view into a texture.
struct TextureViewDescriptor
{
	/// View dimensionality.
	public TextureViewDimension Dimension;
	/// Pixel format (must be compatible with texture format).
	public TextureFormat Format;
	/// First mip level to include.
	public uint32 BaseMipLevel;
	/// Number of mip levels to include.
	public uint32 MipLevelCount;
	/// First array layer to include.
	public uint32 BaseArrayLayer;
	/// Number of array layers to include.
	public uint32 ArrayLayerCount;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Dimension = .Texture2D;
		Format = .RGBA8Unorm;
		BaseMipLevel = 0;
		MipLevelCount = 1;
		BaseArrayLayer = 0;
		ArrayLayerCount = 1;
		Label = default;
	}
}
