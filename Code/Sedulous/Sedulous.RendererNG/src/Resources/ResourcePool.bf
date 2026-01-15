namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;

/// Central resource manager that owns all GPU resource pools.
/// Provides a unified interface for creating and managing GPU resources.
class ResourcePool
{
	private IDevice mDevice;
	private DeferredDeletionQueue mDeletionQueue ~ delete _;
	private BufferPool mBufferPool ~ delete _;
	private TexturePool mTexturePool ~ delete _;

	/// Gets the buffer pool.
	public BufferPool Buffers => mBufferPool;

	/// Gets the texture pool.
	public TexturePool Textures => mTexturePool;

	/// Gets the deferred deletion queue.
	public DeferredDeletionQueue DeletionQueue => mDeletionQueue;

	/// Gets the GPU device.
	public IDevice Device => mDevice;

	/// Resource pool statistics.
	public struct Stats
	{
		public int AllocatedBuffers;
		public int TotalBufferSlots;
		public int FreeBufferSlots;
		public int AllocatedTextures;
		public int TotalTextureSlots;
		public int FreeTextureSlots;
		public int PendingDeletions;
	}

	/// Gets current resource pool statistics.
	public Stats GetStats()
	{
		return .()
		{
			AllocatedBuffers = mBufferPool.AllocatedCount,
			TotalBufferSlots = mBufferPool.TotalSlots,
			FreeBufferSlots = mBufferPool.FreeSlots,
			AllocatedTextures = mTexturePool.AllocatedCount,
			TotalTextureSlots = mTexturePool.TotalSlots,
			FreeTextureSlots = mTexturePool.FreeSlots,
			PendingDeletions = mDeletionQueue.PendingCount
		};
	}

	public this(IDevice device)
	{
		mDevice = device;
		mDeletionQueue = new DeferredDeletionQueue();
		mBufferPool = new BufferPool(device, mDeletionQueue, RenderConfig.INITIAL_BUFFER_POOL_CAPACITY);
		mTexturePool = new TexturePool(device, mDeletionQueue, RenderConfig.INITIAL_TEXTURE_POOL_CAPACITY);
	}

	/// Processes deferred deletions for the current frame.
	/// Should be called once per frame after GPU work is submitted.
	public void ProcessDeletions(uint32 currentFrame)
	{
		mDeletionQueue.ProcessDeletions(currentFrame);
	}

	// === Buffer convenience methods ===

	/// Creates a GPU buffer.
	public BufferHandle CreateBuffer(uint32 size, BufferUsage usage, StringView name = "")
	{
		return mBufferPool.Create(size, usage, name);
	}

	/// Creates a buffer with initial data.
	public BufferHandle CreateBufferWithData<T>(Span<T> data, BufferUsage usage, StringView name = "") where T : struct
	{
		return mBufferPool.CreateWithData(data, usage, name);
	}

	/// Gets the underlying buffer for a handle.
	public IBuffer GetBuffer(BufferHandle handle)
	{
		return mBufferPool.Get(handle);
	}

	/// Releases a buffer (queued for deferred deletion).
	public void ReleaseBuffer(BufferHandle handle)
	{
		mBufferPool.Release(handle);
	}

	// === Texture convenience methods ===

	/// Creates a 2D texture.
	public TextureHandle CreateTexture2D(
		uint32 width,
		uint32 height,
		TextureFormat format,
		TextureUsage usage,
		uint32 mipLevels = 1,
		StringView name = "")
	{
		return mTexturePool.Create2D(width, height, format, usage, mipLevels, name);
	}

	/// Creates a 2D array texture.
	public TextureHandle CreateTexture2DArray(
		uint32 width,
		uint32 height,
		uint32 arrayLayers,
		TextureFormat format,
		TextureUsage usage,
		uint32 mipLevels = 1,
		StringView name = "")
	{
		return mTexturePool.Create2DArray(width, height, arrayLayers, format, usage, mipLevels, name);
	}

	/// Creates a cube texture.
	public TextureHandle CreateTextureCube(
		uint32 size,
		TextureFormat format,
		TextureUsage usage,
		uint32 mipLevels = 1,
		StringView name = "")
	{
		return mTexturePool.CreateCube(size, format, usage, mipLevels, name);
	}

	/// Creates a 3D texture.
	public TextureHandle CreateTexture3D(
		uint32 width,
		uint32 height,
		uint32 depth,
		TextureFormat format,
		TextureUsage usage,
		uint32 mipLevels = 1,
		StringView name = "")
	{
		return mTexturePool.Create3D(width, height, depth, format, usage, mipLevels, name);
	}

	/// Gets the underlying texture for a handle.
	public ITexture GetTexture(TextureHandle handle)
	{
		return mTexturePool.Get(handle);
	}

	/// Gets the default texture view for a handle.
	public ITextureView GetTextureView(TextureHandle handle)
	{
		return mTexturePool.GetView(handle);
	}

	/// Releases a texture (queued for deferred deletion).
	public void ReleaseTexture(TextureHandle handle)
	{
		mTexturePool.Release(handle);
	}

	/// Destroys all resources immediately.
	/// Only call during shutdown when GPU is guaranteed to be idle.
	public void Shutdown()
	{
		// Process any pending deletions first
		mDeletionQueue.FlushAll();

		// Then destroy all pooled resources
		mBufferPool.DestroyAll();
		mTexturePool.DestroyAll();
	}
}
