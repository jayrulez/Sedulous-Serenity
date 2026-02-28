using System;
using System.Collections;
using Sedulous.RHI;

namespace Sedulous.RenderGraph;

/// Manages allocation and reuse of transient GPU resources across frames.
///
/// Transient resources are textures and buffers that only live within a single
/// frame. The pool caches them across frames so matching descriptors reuse
/// existing allocations rather than creating new ones each frame.
///
/// Resources unused for several frames are automatically released.
///
public class TransientResourcePool
{
	private const int UNUSED_FRAME_THRESHOLD = 4;

	private struct PooledTexture
	{
		public ITexture Texture;
		public ITextureView View;
		public TextureDescriptor Desc;
		public int FramesSinceLastUse;
		public bool InUse;
	}

	private struct PooledBuffer
	{
		public IBuffer Buffer;
		public BufferDescriptor Desc;
		public int FramesSinceLastUse;
		public bool InUse;
	}

	private IDevice mDevice;
	private List<PooledTexture> mTextures = new .() ~ delete _;
	private List<PooledBuffer> mBuffers = new .() ~ delete _;

	public this(IDevice device)
	{
		mDevice = device;
	}

	public ~this()
	{
		ReleaseAll();
	}

	/// Acquires a texture matching the given descriptor. May reuse a cached one.
	public Result<(ITexture texture, ITextureView view)> AcquireTexture(TextureDescriptor desc)
	{
		var desc;
		// Try to find a matching unused texture
		for (int i = 0; i < mTextures.Count; i++)
		{
			var entry = ref mTextures[i];
			if (!entry.InUse && TextureDescMatches(ref entry.Desc, ref desc))
			{
				entry.InUse = true;
				entry.FramesSinceLastUse = 0;
				return .Ok((entry.Texture, entry.View));
			}
		}

		// Create a new texture
		if (mDevice.CreateTexture(&desc) case .Ok(let texture))
		{
			TextureViewDescriptor viewDesc = .()
			{
				Format = desc.Format,
				Dimension = .Texture2D,
				BaseMipLevel = 0,
				MipLevelCount = desc.MipLevelCount,
				BaseArrayLayer = 0,
				ArrayLayerCount = desc.ArrayLayerCount
			};

			if (mDevice.CreateTextureView(texture, &viewDesc) case .Ok(let view))
			{
				PooledTexture entry = .()
				{
					Texture = texture,
					View = view,
					Desc = desc,
					FramesSinceLastUse = 0,
					InUse = true
				};
				mTextures.Add(entry);
				return .Ok((texture, view));
			}
			else
			{
				delete texture;
				return .Err;
			}
		}
		return .Err;
	}

	/// Acquires a buffer matching the given descriptor. May reuse a cached one.
	public Result<IBuffer> AcquireBuffer(BufferDescriptor desc)
	{
		var desc;
		// Try to find a matching unused buffer
		for (int i = 0; i < mBuffers.Count; i++)
		{
			var entry = ref mBuffers[i];
			if (!entry.InUse && BufferDescMatches(ref entry.Desc, ref desc))
			{
				entry.InUse = true;
				entry.FramesSinceLastUse = 0;
				return .Ok(entry.Buffer);
			}
		}

		// Create a new buffer
		if (mDevice.CreateBuffer(&desc) case .Ok(let buffer))
		{
			PooledBuffer entry = .()
			{
				Buffer = buffer,
				Desc = desc,
				FramesSinceLastUse = 0,
				InUse = true
			};
			mBuffers.Add(entry);
			return .Ok(buffer);
		}
		return .Err;
	}

	/// Marks all resources as unused for this frame.
	/// Call at the beginning of each frame before graph compilation.
	public void BeginFrame()
	{
		for (int i = 0; i < mTextures.Count; i++)
		{
			var entry = ref mTextures[i];
			entry.InUse = false;
			entry.FramesSinceLastUse++;
		}
		for (int i = 0; i < mBuffers.Count; i++)
		{
			var entry = ref mBuffers[i];
			entry.InUse = false;
			entry.FramesSinceLastUse++;
		}

		// Purge resources that haven't been used for a while
		Purge();
	}

	/// Releases all pooled resources.
	public void ReleaseAll()
	{
		for (var entry in mTextures)
		{
			if (entry.View != null) delete entry.View;
			if (entry.Texture != null) delete entry.Texture;
		}
		mTextures.Clear();

		for (var entry in mBuffers)
		{
			if (entry.Buffer != null) delete entry.Buffer;
		}
		mBuffers.Clear();
	}

	/// Releases resources that haven't been used for several frames.
	private void Purge()
	{
		for (int i = mTextures.Count - 1; i >= 0; i--)
		{
			let entry = mTextures[i];
			if (!entry.InUse && entry.FramesSinceLastUse > UNUSED_FRAME_THRESHOLD)
			{
				if (entry.View != null) delete entry.View;
				if (entry.Texture != null) delete entry.Texture;
				mTextures.RemoveAtFast(i);
			}
		}

		for (int i = mBuffers.Count - 1; i >= 0; i--)
		{
			let entry = mBuffers[i];
			if (!entry.InUse && entry.FramesSinceLastUse > UNUSED_FRAME_THRESHOLD)
			{
				if (entry.Buffer != null) delete entry.Buffer;
				mBuffers.RemoveAtFast(i);
			}
		}
	}

	/// Checks if two texture descriptors are compatible for reuse.
	private static bool TextureDescMatches(ref TextureDescriptor a, ref TextureDescriptor b)
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

	/// Checks if two buffer descriptors are compatible for reuse.
	private static bool BufferDescMatches(ref BufferDescriptor a, ref BufferDescriptor b)
	{
		return a.Size == b.Size &&
			a.Usage == b.Usage &&
			a.MemoryAccess == b.MemoryAccess;
	}
}
