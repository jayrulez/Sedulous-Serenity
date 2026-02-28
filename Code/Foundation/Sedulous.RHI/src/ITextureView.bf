namespace Sedulous.RHI;

using System;

/// A view into a texture resource.
interface ITextureView : IDisposable
{
	/// Debug name for tracking resource leaks.
	StringView DebugName { get; }

	/// The texture this view references.
	ITexture Texture { get; }

	/// View dimensionality.
	TextureViewDimension Dimension { get; }

	/// Pixel format.
	TextureFormat Format { get; }

	/// First mip level in the view.
	uint32 BaseMipLevel { get; }

	/// Number of mip levels in the view.
	uint32 MipLevelCount { get; }

	/// First array layer in the view.
	uint32 BaseArrayLayer { get; }

	/// Number of array layers in the view.
	uint32 ArrayLayerCount { get; }
}
