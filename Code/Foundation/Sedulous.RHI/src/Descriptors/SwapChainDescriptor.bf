using System;
namespace Sedulous.RHI;

/// Describes a swap chain.
struct SwapChainDescriptor
{
	/// Width in pixels.
	public uint32 Width;
	/// Height in pixels.
	public uint32 Height;
	/// Pixel format.
	public TextureFormat Format;
	/// How the swap chain images will be used.
	public TextureUsage Usage;
	/// Presentation mode.
	public PresentMode PresentMode;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Width = 800;
		Height = 600;
		Format = .BGRA8Unorm;
		Usage = .RenderTarget;
		PresentMode = .Fifo;
		Label = default;
	}

	public this(uint32 width, uint32 height, TextureFormat format = .BGRA8Unorm, PresentMode presentMode = .Fifo)
	{
		Width = width;
		Height = height;
		Format = format;
		Usage = .RenderTarget;
		PresentMode = presentMode;
		Label = default;
	}
}
