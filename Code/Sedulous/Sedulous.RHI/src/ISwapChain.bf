namespace Sedulous.RHI;

using System;

/// A swap chain for presenting rendered images to a surface.
interface ISwapChain : IDisposable
{
	/// Pixel format of the swap chain images.
	TextureFormat Format { get; }

	/// Width of the swap chain images in pixels.
	uint32 Width { get; }

	/// Height of the swap chain images in pixels.
	uint32 Height { get; }

	/// Gets the current back buffer texture.
	ITexture CurrentTexture { get; }

	/// Gets a view of the current back buffer texture.
	ITextureView CurrentTextureView { get; }

	/// Acquires the next image from the swap chain.
	Result<void> AcquireNextImage();

	/// Presents the current image to the surface.
	Result<void> Present();

	/// Resizes the swap chain.
	Result<void> Resize(uint32 width, uint32 height);
}
