namespace Sedulous.RendererNext;

using System;
using Sedulous.RHI;

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

	/// Texture depth (for 3D textures) or array layers.
	public uint32 DepthOrLayers = 1;

	/// Texture format.
	public TextureFormat Format;

	/// Number of mip levels.
	public uint32 MipLevels = 1;

	/// Texture dimension.
	public TextureDimension Dimension = .Texture2D;

	/// Reference count for resource management.
	private int32 mRefCount = 1;

	public this()
	{
	}

	/// Increments reference count.
	public void AddRef()
	{
		mRefCount++;
	}

	/// Decrements reference count. Returns true if resource should be freed.
	public bool Release()
	{
		mRefCount--;
		return mRefCount <= 0;
	}

	/// Current reference count.
	public int32 RefCount => mRefCount;
}

/// Handle to a GPU texture resource.
struct GPUTextureHandle : IEquatable<GPUTextureHandle>, IHashable
{
	private uint32 mIndex;
	private uint32 mGeneration;

	public static readonly Self Invalid = .(uint32.MaxValue, 0);

	public uint32 Index => mIndex;
	public uint32 Generation => mGeneration;
	public bool IsValid => mIndex != uint32.MaxValue;

	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(Self other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}
