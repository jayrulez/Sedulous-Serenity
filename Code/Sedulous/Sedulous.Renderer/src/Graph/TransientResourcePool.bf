namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;

/// Pooled texture entry.
class PooledTexture
{
	public ITexture Texture;
	public ITextureView View;
	public TextureDescriptor Desc;
	public uint32 LastUsedFrame;

	public ~this()
	{
		if (View != null)
			delete View;
		if (Texture != null)
			delete Texture;
	}
}

/// Pooled buffer entry.
class PooledBuffer
{
	public IBuffer Buffer;
	public BufferDescriptor Desc;
	public uint32 LastUsedFrame;

	public ~this()
	{
		if (Buffer != null)
			delete Buffer;
	}
}

/// Manages a pool of transient GPU resources for efficient reuse.
///
/// Resources that are no longer needed can be returned to the pool and
/// reused in subsequent frames, reducing allocation overhead.
class TransientResourcePool
{
	private IDevice mDevice;
	private List<PooledTexture> mTexturePool = new .() ~ DeleteContainerAndItems!(_);
	private List<PooledBuffer> mBufferPool = new .() ~ DeleteContainerAndItems!(_);
	private uint32 mCurrentFrame;

	/// Number of frames to keep unused resources before releasing.
	private const uint32 RESOURCE_LIFETIME_FRAMES = 3;

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Advances the frame counter. Call once per frame.
	public void AdvanceFrame()
	{
		mCurrentFrame++;
		GarbageCollect();
	}

	/// Acquires a texture from the pool, or creates a new one if none are available.
	public (ITexture texture, ITextureView view) AcquireTexture(TextureDescriptor desc)
	{
		var desc;
		// Try to find a matching texture in the pool
		for (int i = 0; i < mTexturePool.Count; i++)
		{
			let pooled = mTexturePool[i];
			if (TextureDescMatches(pooled.Desc, desc))
			{
				// Found a match - remove from pool and return
				let texture = pooled.Texture;
				let view = pooled.View;
				pooled.Texture = null;
				pooled.View = null;
				mTexturePool.RemoveAt(i);
				delete pooled;
				return (texture, view);
			}
		}

		// No match found - create new texture
		if (mDevice.CreateTexture(&desc) case .Ok(let texture))
		{
			TextureViewDescriptor viewDesc = .()
			{
				Format = desc.Format,
				Dimension = desc.Dimension == .Texture2D ? .Texture2D : .Texture2D,
				BaseMipLevel = 0,
				MipLevelCount = desc.MipLevelCount,
				BaseArrayLayer = 0,
				ArrayLayerCount = desc.ArrayLayerCount
			};

			if (mDevice.CreateTextureView(texture, &viewDesc) case .Ok(let view))
			{
				return (texture, view);
			}
			else
			{
				delete texture;
			}
		}

		return (null, null);
	}

	/// Returns a texture to the pool for later reuse.
	public void ReturnTexture(ITexture texture, ITextureView view, TextureDescriptor desc)
	{
		let pooled = new PooledTexture();
		pooled.Texture = texture;
		pooled.View = view;
		pooled.Desc = desc;
		pooled.LastUsedFrame = mCurrentFrame;
		mTexturePool.Add(pooled);
	}

	/// Acquires a buffer from the pool, or creates a new one if none are available.
	public IBuffer AcquireBuffer(BufferDescriptor desc)
	{
		var desc;
		// Try to find a matching buffer in the pool
		for (int i = 0; i < mBufferPool.Count; i++)
		{
			let pooled = mBufferPool[i];
			if (BufferDescMatches(pooled.Desc, desc))
			{
				// Found a match - remove from pool and return
				let buffer = pooled.Buffer;
				pooled.Buffer = null;
				mBufferPool.RemoveAt(i);
				delete pooled;
				return buffer;
			}
		}

		// No match found - create new buffer
		if (mDevice.CreateBuffer(&desc) case .Ok(let buffer))
		{
			return buffer;
		}

		return null;
	}

	/// Returns a buffer to the pool for later reuse.
	public void ReturnBuffer(IBuffer buffer, BufferDescriptor desc)
	{
		let pooled = new PooledBuffer();
		pooled.Buffer = buffer;
		pooled.Desc = desc;
		pooled.LastUsedFrame = mCurrentFrame;
		mBufferPool.Add(pooled);
	}

	/// Removes resources that haven't been used for several frames.
	public void GarbageCollect()
	{
		// Remove old textures
		for (int i = mTexturePool.Count - 1; i >= 0; i--)
		{
			if (mCurrentFrame - mTexturePool[i].LastUsedFrame > RESOURCE_LIFETIME_FRAMES)
			{
				delete mTexturePool[i];
				mTexturePool.RemoveAt(i);
			}
		}

		// Remove old buffers
		for (int i = mBufferPool.Count - 1; i >= 0; i--)
		{
			if (mCurrentFrame - mBufferPool[i].LastUsedFrame > RESOURCE_LIFETIME_FRAMES)
			{
				delete mBufferPool[i];
				mBufferPool.RemoveAt(i);
			}
		}
	}

	/// Clears all pooled resources.
	public void Clear()
	{
		ClearAndDeleteItems!(mTexturePool);
		ClearAndDeleteItems!(mBufferPool);
	}

	// ===== Matching Helpers =====

	private static bool TextureDescMatches(TextureDescriptor a, TextureDescriptor b)
	{
		return a.Dimension == b.Dimension &&
			   a.Format == b.Format &&
			   a.Width == b.Width &&
			   a.Height == b.Height &&
			   a.Depth == b.Depth &&
			   a.MipLevelCount == b.MipLevelCount &&
			   a.ArrayLayerCount == b.ArrayLayerCount &&
			   a.SampleCount == b.SampleCount &&
			   a.Usage == b.Usage;
	}

	private static bool BufferDescMatches(BufferDescriptor a, BufferDescriptor b)
	{
		// Match if size is at least as large and usage/access are compatible
		return a.Size >= b.Size &&
			   (a.Usage & b.Usage) == b.Usage &&
			   a.MemoryAccess == b.MemoryAccess;
	}
}
