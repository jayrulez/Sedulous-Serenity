namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;

/// Entry in the texture pool.
struct TexturePoolEntry
{
	/// The GPU texture (null if slot is free).
	public ITexture Texture;

	/// Default texture view (created automatically).
	public ITextureView View;

	/// Current generation counter for this slot.
	public uint32 Generation;

	/// Texture width.
	public uint32 Width;

	/// Texture height.
	public uint32 Height;

	/// Texture depth (for 3D textures) or array layers.
	public uint32 DepthOrLayers;

	/// Texture format.
	public TextureFormat Format;

	/// Texture usage flags.
	public TextureUsage Usage;

	/// Texture dimension (2D, 3D, Cube, etc.).
	public TextureDimension Dimension;

	/// Debug name for the texture.
	public String Name;
}

/// Pool for managing GPU texture resources.
/// Uses generation-based handles for safe access.
class TexturePool
{
	private IDevice mDevice;
	private DeferredDeletionQueue mDeletionQueue;
	private List<TexturePoolEntry> mEntries = new .() ~ delete _;
	private List<uint32> mFreeList = new .() ~ delete _;

	/// Gets the number of allocated textures.
	public int AllocatedCount
	{
		get
		{
			int count = 0;
			for (let entry in mEntries)
			{
				if (entry.Texture != null)
					count++;
			}
			return count;
		}
	}

	/// Gets the total number of slots (allocated + free).
	public int TotalSlots => mEntries.Count;

	/// Gets the number of free slots.
	public int FreeSlots => mFreeList.Count;

	public this(IDevice device, DeferredDeletionQueue deletionQueue, int32 initialCapacity = 0)
	{
		mDevice = device;
		mDeletionQueue = deletionQueue;

		if (initialCapacity > 0)
		{
			mEntries.Reserve(initialCapacity);
			mFreeList.Reserve(initialCapacity);
		}
	}

	public ~this()
	{
		// Delete all texture names
		for (var entry in ref mEntries)
		{
			if (entry.Name != null)
				delete entry.Name;
		}
	}

	/// Creates a new 2D GPU texture and returns a handle to it.
	/// @param width Texture width in pixels.
	/// @param height Texture height in pixels.
	/// @param format Texture format.
	/// @param usage Texture usage flags.
	/// @param mipLevels Number of mip levels (0 = full chain).
	/// @param name Optional debug name.
	/// @returns Handle to the created texture, or Invalid on failure.
	public TextureHandle Create2D(
		uint32 width,
		uint32 height,
		TextureFormat format,
		TextureUsage usage,
		uint32 mipLevels = 1,
		StringView name = "")
	{
		var desc = TextureDescriptor.Texture2D(width, height, format, usage, mipLevels);
		return CreateInternal(desc, name);
	}

	/// Creates a new 2D array texture and returns a handle to it.
	public TextureHandle Create2DArray(
		uint32 width,
		uint32 height,
		uint32 arrayLayers,
		TextureFormat format,
		TextureUsage usage,
		uint32 mipLevels = 1,
		StringView name = "")
	{
		var desc = TextureDescriptor.Texture2D(width, height, format, usage, mipLevels);
		desc.ArrayLayerCount = arrayLayers;
		return CreateInternal(desc, name);
	}

	/// Creates a new cube texture and returns a handle to it.
	public TextureHandle CreateCube(
		uint32 size,
		TextureFormat format,
		TextureUsage usage,
		uint32 mipLevels = 1,
		StringView name = "")
	{
		var desc = TextureDescriptor.Cubemap(size, format, usage, mipLevels);
		return CreateInternal(desc, name);
	}

	/// Creates a new 3D texture and returns a handle to it.
	public TextureHandle Create3D(
		uint32 width,
		uint32 height,
		uint32 depth,
		TextureFormat format,
		TextureUsage usage,
		uint32 mipLevels = 1,
		StringView name = "")
	{
		var desc = TextureDescriptor()
		{
			Dimension = .Texture3D,
			Format = format,
			Width = width,
			Height = height,
			Depth = depth,
			MipLevelCount = mipLevels,
			Usage = usage
		};
		return CreateInternal(desc, name);
	}

	/// Internal method to create a texture from a descriptor.
	private TextureHandle CreateInternal(TextureDescriptor desc, StringView name)
	{
		var desc;
		// Create the GPU texture
		let result = mDevice.CreateTexture(&desc);
		if (result case .Err)
			return .Invalid;

		let texture = result.Value;

		// Create the default view with proper descriptor
		var viewDesc = TextureViewDescriptor()
		{
			Dimension = DimensionToViewDimension(desc.Dimension, desc.ArrayLayerCount),
			Format = desc.Format,
			BaseMipLevel = 0,
			MipLevelCount = desc.MipLevelCount,
			BaseArrayLayer = 0,
			ArrayLayerCount = desc.ArrayLayerCount
		};
		let viewResult = mDevice.CreateTextureView(texture, &viewDesc);
		ITextureView view = null;
		if (viewResult case .Ok(let v))
			view = v;

		// Find or create a slot
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			// Reuse a free slot
			index = mFreeList.PopBack();
			generation = mEntries[index].Generation;

			var entry = ref mEntries[index];
			entry.Texture = texture;
			entry.View = view;
			entry.Width = desc.Width;
			entry.Height = desc.Height;
			entry.DepthOrLayers = desc.Dimension == .Texture3D ? desc.Depth : desc.ArrayLayerCount;
			entry.Format = desc.Format;
			entry.Usage = desc.Usage;
			entry.Dimension = desc.Dimension;
			if (!name.IsEmpty)
			{
				if (entry.Name == null)
					entry.Name = new String(name);
				else
					entry.Name.Set(name);
			}
		}
		else
		{
			// Allocate a new slot
			index = (uint32)mEntries.Count;
			generation = 1;

			TexturePoolEntry entry = .();
			entry.Texture = texture;
			entry.View = view;
			entry.Generation = generation;
			entry.Width = desc.Width;
			entry.Height = desc.Height;
			entry.DepthOrLayers = desc.Dimension == .Texture3D ? desc.Depth : desc.ArrayLayerCount;
			entry.Format = desc.Format;
			entry.Usage = desc.Usage;
			entry.Dimension = desc.Dimension;
			if (!name.IsEmpty)
				entry.Name = new String(name);

			mEntries.Add(entry);
		}

		return .(index, generation);
	}

	/// Gets the texture for a handle.
	/// Returns null if the handle is invalid or the generation doesn't match.
	public ITexture Get(TextureHandle handle)
	{
		if (!handle.HasValidIndex)
			return null;

		if (handle.Index >= (uint32)mEntries.Count)
			return null;

		let entry = mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return null;

		return entry.Texture;
	}

	/// Gets the default texture view for a handle.
	/// Returns null if the handle is invalid or the generation doesn't match.
	public ITextureView GetView(TextureHandle handle)
	{
		if (!handle.HasValidIndex)
			return null;

		if (handle.Index >= (uint32)mEntries.Count)
			return null;

		let entry = mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return null;

		return entry.View;
	}

	/// Checks if a handle is valid (points to an existing texture).
	public bool IsValid(TextureHandle handle)
	{
		return Get(handle) != null;
	}

	/// Gets the dimensions of a texture.
	/// Returns (0, 0, 0) if the handle is invalid.
	public (uint32 width, uint32 height, uint32 depthOrLayers) GetDimensions(TextureHandle handle)
	{
		if (!handle.HasValidIndex || handle.Index >= (uint32)mEntries.Count)
			return (0, 0, 0);

		let entry = mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return (0, 0, 0);

		return (entry.Width, entry.Height, entry.DepthOrLayers);
	}

	/// Gets the format of a texture.
	public TextureFormat GetFormat(TextureHandle handle)
	{
		if (!handle.HasValidIndex || handle.Index >= (uint32)mEntries.Count)
			return .Undefined;

		let entry = mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return .Undefined;

		return entry.Format;
	}

	/// Gets the usage flags of a texture.
	public TextureUsage GetUsage(TextureHandle handle)
	{
		if (!handle.HasValidIndex || handle.Index >= (uint32)mEntries.Count)
			return .None;

		let entry = mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return .None;

		return entry.Usage;
	}

	/// Releases a texture. The texture will be queued for deferred deletion.
	/// The handle becomes invalid after this call.
	public void Release(TextureHandle handle)
	{
		if (!handle.HasValidIndex)
			return;

		if (handle.Index >= (uint32)mEntries.Count)
			return;

		var entry = ref mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return;

		// Queue the view and texture for deferred deletion
		if (entry.View != null)
		{
			mDeletionQueue.QueueTextureView(entry.View);
			entry.View = null;
		}

		if (entry.Texture != null)
		{
			mDeletionQueue.QueueTexture(entry.Texture);
			entry.Texture = null;
		}

		// Increment generation so existing handles become invalid
		entry.Generation++;

		// Add to free list for reuse
		mFreeList.Add(handle.Index);
	}

	/// Immediately destroys all textures without deferring deletion.
	/// Use only during shutdown when the GPU is guaranteed to be idle.
	public void DestroyAll()
	{
		for (var entry in ref mEntries)
		{
			if (entry.View != null)
			{
				delete entry.View;
				entry.View = null;
			}
			if (entry.Texture != null)
			{
				delete entry.Texture;
				entry.Texture = null;
			}
			entry.Generation++;
		}
		mFreeList.Clear();

		// Rebuild free list with all slots
		for (uint32 i = 0; i < (uint32)mEntries.Count; i++)
		{
			mFreeList.Add(i);
		}
	}

	/// Converts TextureDimension to TextureViewDimension based on array layer count.
	private static TextureViewDimension DimensionToViewDimension(TextureDimension dimension, uint32 arrayLayers)
	{
		switch (dimension)
		{
		case .Texture1D:
			return .Texture1D;
		case .Texture2D:
			if (arrayLayers == 6)
				return .TextureCube;
			else if (arrayLayers > 1)
				return .Texture2DArray;
			else
				return .Texture2D;
		case .Texture3D:
			return .Texture3D;
		}
	}
}
