namespace Sedulous.RHI;

using System;

/// A GPU texture resource.
interface ITexture : IDisposable
{
	/// Debug name for tracking resource leaks.
	StringView DebugName { get; }

	/// Texture dimensionality.
	TextureDimension Dimension { get; }

	/// Pixel format.
	TextureFormat Format { get; }

	/// Width in texels.
	uint32 Width { get; }

	/// Height in texels.
	uint32 Height { get; }

	/// Depth in texels (for 3D textures).
	uint32 Depth { get; }

	/// Number of mip levels.
	uint32 MipLevelCount { get; }

	/// Number of array layers.
	uint32 ArrayLayerCount { get; }

	/// Number of MSAA samples.
	uint32 SampleCount { get; }

	/// Usage flags.
	TextureUsage Usage { get; }
}
