namespace Sedulous.Framework.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Imaging;

/// GPU-side texture with view.
class GPUTexture
{
	/// The underlying GPU texture.
	public ITexture Texture ~ delete _;

	/// Default view for sampling.
	public ITextureView View ~ delete _;

	/// Texture width.
	public uint32 Width;

	/// Texture height.
	public uint32 Height;

	/// Texture format.
	public TextureFormat Format;

	/// Number of mip levels.
	public uint32 MipLevels;

	/// Reference count for resource management.
	public int32 RefCount = 1;

	public this()
	{
	}

	/// Increments reference count.
	public void AddRef()
	{
		RefCount++;
	}

	/// Decrements reference count. Returns true if resource should be freed.
	public bool Release()
	{
		RefCount--;
		return RefCount <= 0;
	}
}

/// Handle to a GPU texture resource.
struct GPUTextureHandle : IEquatable<GPUTextureHandle>, IHashable
{
	private uint32 mIndex;
	private uint32 mGeneration;

	public static readonly Self Invalid = .((uint32)-1, 0);

	public uint32 Index => mIndex;
	public uint32 Generation => mGeneration;
	public bool IsValid => mIndex != (uint32)-1;

	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(GPUTextureHandle other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}
}
