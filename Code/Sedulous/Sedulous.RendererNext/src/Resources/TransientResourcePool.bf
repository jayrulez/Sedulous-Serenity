namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;

/// Pool entry for a texture resource.
struct PooledTexture
{
	public ITexture Texture;
	public ITextureView View;
	public RenderGraphTextureDescriptor Descriptor;
	public int32 LastUsedFrame;
	public bool InUse;
}

/// Pool entry for a buffer resource.
struct PooledBuffer
{
	public IBuffer Buffer;
	public RenderGraphBufferDescriptor Descriptor;
	public int32 LastUsedFrame;
	public bool InUse;
}

/// Manages pooled transient resources for the render graph.
/// Resources are reused across frames to minimize allocations.
class TransientResourcePool
{
	private IDevice mDevice;
	private List<PooledTexture> mTexturePool = new .() ~ {
		for (var entry in _)
		{
			if (entry.View != null) delete entry.View;
			if (entry.Texture != null) delete entry.Texture;
		}
		delete _;
	};
	private List<PooledBuffer> mBufferPool = new .() ~ {
		for (var entry in _)
		{
			if (entry.Buffer != null) delete entry.Buffer;
		}
		delete _;
	};

	private int32 mCurrentFrame = 0;
	private int32 mMaxUnusedFrames = 4;  // Release resources unused for this many frames

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Begins a new frame, resetting usage flags and releasing old resources.
	public void BeginFrame(int32 frameIndex)
	{
		mCurrentFrame = frameIndex;

		// Reset in-use flags
		for (int i = 0; i < mTexturePool.Count; i++)
		{
			var entry = mTexturePool[i];
			entry.InUse = false;
			mTexturePool[i] = entry;
		}

		for (int i = 0; i < mBufferPool.Count; i++)
		{
			var entry = mBufferPool[i];
			entry.InUse = false;
			mBufferPool[i] = entry;
		}

		// Release resources that haven't been used for a while
		ReleaseUnusedResources();
	}

	/// Allocates a transient texture from the pool.
	public Result<(ITexture texture, ITextureView view)> AllocateTexture(RenderGraphTextureDescriptor desc)
	{
		// Try to find a matching unused texture
		for (int i = 0; i < mTexturePool.Count; i++)
		{
			var entry = mTexturePool[i];
			if (!entry.InUse && IsTextureCompatible(entry.Descriptor, desc))
			{
				entry.InUse = true;
				entry.LastUsedFrame = mCurrentFrame;
				mTexturePool[i] = entry;
				return .Ok((entry.Texture, entry.View));
			}
		}

		// Create new texture
		if (CreateTexture(desc) case .Ok(let result))
		{
			PooledTexture newEntry = .()
			{
				Texture = result.texture,
				View = result.view,
				Descriptor = desc,
				LastUsedFrame = mCurrentFrame,
				InUse = true
			};
			mTexturePool.Add(newEntry);
			return .Ok(result);
		}

		return .Err;
	}

	/// Allocates a transient buffer from the pool.
	public Result<IBuffer> AllocateBuffer(RenderGraphBufferDescriptor desc)
	{
		// Try to find a matching unused buffer
		for (int i = 0; i < mBufferPool.Count; i++)
		{
			var entry = mBufferPool[i];
			if (!entry.InUse && IsBufferCompatible(entry.Descriptor, desc))
			{
				entry.InUse = true;
				entry.LastUsedFrame = mCurrentFrame;
				mBufferPool[i] = entry;
				return .Ok(entry.Buffer);
			}
		}

		// Create new buffer
		if (CreateBuffer(desc) case .Ok(let buffer))
		{
			PooledBuffer newEntry = .()
			{
				Buffer = buffer,
				Descriptor = desc,
				LastUsedFrame = mCurrentFrame,
				InUse = true
			};
			mBufferPool.Add(newEntry);
			return .Ok(buffer);
		}

		return .Err;
	}

	/// Ends the frame.
	public void EndFrame()
	{
		// Nothing to do here currently
	}

	/// Releases all pooled resources.
	public void Clear()
	{
		for (var entry in mTexturePool)
		{
			if (entry.View != null) delete entry.View;
			if (entry.Texture != null) delete entry.Texture;
		}
		mTexturePool.Clear();

		for (var entry in mBufferPool)
		{
			if (entry.Buffer != null) delete entry.Buffer;
		}
		mBufferPool.Clear();
	}

	/// Releases resources that haven't been used recently.
	private void ReleaseUnusedResources()
	{
		// Textures
		for (int i = mTexturePool.Count - 1; i >= 0; i--)
		{
			let entry = mTexturePool[i];
			if (!entry.InUse && (mCurrentFrame - entry.LastUsedFrame) > mMaxUnusedFrames)
			{
				if (entry.View != null) delete entry.View;
				if (entry.Texture != null) delete entry.Texture;
				mTexturePool.RemoveAt(i);
			}
		}

		// Buffers
		for (int i = mBufferPool.Count - 1; i >= 0; i--)
		{
			let entry = mBufferPool[i];
			if (!entry.InUse && (mCurrentFrame - entry.LastUsedFrame) > mMaxUnusedFrames)
			{
				if (entry.Buffer != null) delete entry.Buffer;
				mBufferPool.RemoveAt(i);
			}
		}
	}

	/// Checks if a pooled texture is compatible with the requested descriptor.
	private static bool IsTextureCompatible(RenderGraphTextureDescriptor pooled, RenderGraphTextureDescriptor requested)
	{
		return pooled.Width == requested.Width &&
			   pooled.Height == requested.Height &&
			   pooled.Depth == requested.Depth &&
			   pooled.MipLevels == requested.MipLevels &&
			   pooled.ArraySize == requested.ArraySize &&
			   pooled.Format == requested.Format &&
			   pooled.Usage == requested.Usage &&
			   pooled.Dimension == requested.Dimension &&
			   pooled.SampleCount == requested.SampleCount;
	}

	/// Checks if a pooled buffer is compatible with the requested descriptor.
	private static bool IsBufferCompatible(RenderGraphBufferDescriptor pooled, RenderGraphBufferDescriptor requested)
	{
		// Allow larger buffers to satisfy smaller requests
		return pooled.Size >= requested.Size &&
			   pooled.Usage == requested.Usage &&
			   pooled.StructureByteStride == requested.StructureByteStride;
	}

	/// Creates a new texture.
	private Result<(ITexture texture, ITextureView view)> CreateTexture(RenderGraphTextureDescriptor desc)
	{
		TextureDescriptor texDesc = .()
		{
			Dimension = desc.Dimension,
			Format = desc.Format,
			Width = desc.Width,
			Height = desc.Height,
			Depth = desc.Depth,
			ArrayLayerCount = desc.ArraySize,
			MipLevelCount = desc.MipLevels,
			SampleCount = desc.SampleCount,
			Usage = desc.Usage
		};

		if (mDevice.CreateTexture(&texDesc) case .Ok(let texture))
		{
			TextureViewDescriptor viewDesc = .()
			{
				Format = desc.Format,
				Dimension = GetViewDimension(desc.Dimension),
				BaseMipLevel = 0,
				MipLevelCount = desc.MipLevels,
				BaseArrayLayer = 0,
				ArrayLayerCount = desc.ArraySize
			};

			if (mDevice.CreateTextureView(texture, &viewDesc) case .Ok(let view))
			{
				return .Ok((texture, view));
			}

			delete texture;
		}

		return .Err;
	}

	/// Creates a new buffer.
	private Result<IBuffer> CreateBuffer(RenderGraphBufferDescriptor desc)
	{
		BufferDescriptor bufDesc = .()
		{
			Size = desc.Size,
			Usage = desc.Usage
		};

		if (mDevice.CreateBuffer(&bufDesc) case .Ok(let buffer))
			return .Ok(buffer);

		return .Err;
	}

	/// Converts texture dimension to view dimension.
	private static TextureViewDimension GetViewDimension(TextureDimension dimension)
	{
		switch (dimension)
		{
		case .Texture1D: return .Texture1D;
		case .Texture2D: return .Texture2D;
		case .Texture3D: return .Texture3D;
		default: return .Texture2D;
		}
	}

	/// Number of pooled textures.
	public int32 PooledTextureCount => (int32)mTexturePool.Count;

	/// Number of pooled buffers.
	public int32 PooledBufferCount => (int32)mBufferPool.Count;

	/// Number of textures currently in use.
	public int32 TexturesInUse
	{
		get
		{
			int32 count = 0;
			for (let entry in mTexturePool)
				if (entry.InUse) count++;
			return count;
		}
	}

	/// Number of buffers currently in use.
	public int32 BuffersInUse
	{
		get
		{
			int32 count = 0;
			for (let entry in mBufferPool)
				if (entry.InUse) count++;
			return count;
		}
	}
}
