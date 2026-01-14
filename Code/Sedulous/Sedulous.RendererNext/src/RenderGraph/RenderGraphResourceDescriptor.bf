namespace Sedulous.RendererNext;

using System;
using Sedulous.RHI;

/// Descriptor for a render graph texture resource.
struct RenderGraphTextureDescriptor
{
	public uint32 Width;
	public uint32 Height;
	public uint32 Depth;
	public uint32 MipLevels;
	public uint32 ArraySize;
	public TextureFormat Format;
	public TextureUsage Usage;
	public TextureDimension Dimension;
	public uint32 SampleCount;

	/// Creates a 2D texture descriptor.
	public static Self Texture2D(uint32 width, uint32 height, TextureFormat format, TextureUsage usage = .RenderTarget | .Sampled)
	{
		return .()
		{
			Width = width,
			Height = height,
			Depth = 1,
			MipLevels = 1,
			ArraySize = 1,
			Format = format,
			Usage = usage,
			Dimension = .Texture2D,
			SampleCount = 1
		};
	}

	/// Creates a depth texture descriptor.
	public static Self Depth(uint32 width, uint32 height, TextureFormat format = .Depth24PlusStencil8)
	{
		return .()
		{
			Width = width,
			Height = height,
			Depth = 1,
			MipLevels = 1,
			ArraySize = 1,
			Format = format,
			Usage = .RenderTarget | .Sampled,
			Dimension = .Texture2D,
			SampleCount = 1
		};
	}
}

/// Descriptor for a render graph buffer resource.
struct RenderGraphBufferDescriptor
{
	public uint64 Size;
	public BufferUsage Usage;
	public uint32 StructureByteStride;

	/// Creates a uniform buffer descriptor.
	public static Self Uniform(uint64 size)
	{
		return .()
		{
			Size = size,
			Usage = .Uniform | .CopyDst,
			StructureByteStride = 0
		};
	}

	/// Creates a storage buffer descriptor.
	public static Self Storage(uint64 size, uint32 stride = 0)
	{
		return .()
		{
			Size = size,
			Usage = .Storage | .CopyDst,
			StructureByteStride = stride
		};
	}
}
