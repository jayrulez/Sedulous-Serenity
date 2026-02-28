using System;
namespace Sedulous.RHI;

/// Specifies which aspect of a texture to view.
/// For depth/stencil textures, you must choose one aspect for sampled views.
enum TextureAspect
{
	/// All aspects (default for color textures).
	/// For depth/stencil, uses both depth and stencil (valid for attachments).
	All,
	/// Depth aspect only (for sampling depth from depth/stencil textures).
	DepthOnly,
	/// Stencil aspect only (for sampling stencil from depth/stencil textures).
	StencilOnly
}

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
	/// Aspect of the texture to view (for depth/stencil textures).
	/// Use DepthOnly when creating a sampled view of depth/stencil textures.
	public TextureAspect Aspect;
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
		Aspect = .All;
		Label = default;
	}
}
