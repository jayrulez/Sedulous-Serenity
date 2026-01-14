namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;

/// Key for identifying a bind group configuration.
struct BindGroupKey : IHashable, IEquatable<BindGroupKey>
{
	public IBindGroupLayout Layout;
	public int64 Hash;

	public int GetHashCode() => (int)Hash;

	public bool Equals(Self other)
	{
		return Layout == other.Layout && Hash == other.Hash;
	}

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}

/// Cached bind group entry.
struct CachedBindGroup
{
	public IBindGroup BindGroup;
	public int32 LastUsedFrame;
}

/// Caches bind groups to avoid recreating them every frame.
/// Bind groups with the same layout and resources are reused.
class BindGroupCache
{
	private IDevice mDevice;
	private Dictionary<int, CachedBindGroup> mCache = new .() ~ {
		for (let kv in _)
			delete kv.value.BindGroup;
		delete _;
	};
	private int32 mCurrentFrame = 0;
	private int32 mMaxUnusedFrames = 4;

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Begins a new frame.
	public void BeginFrame(int32 frameIndex)
	{
		mCurrentFrame = frameIndex;
		ReleaseUnusedBindGroups();
	}

	/// Gets or creates a bind group for a single buffer binding.
	public Result<IBindGroup> GetBindGroup(IBindGroupLayout layout, uint32 binding, IBuffer buffer)
	{
		BindGroupEntry[1] entries = .(BindGroupEntry.Buffer(binding, buffer));
		return GetBindGroup(layout, entries);
	}

	/// Gets or creates a bind group for buffer + texture + sampler (common pattern).
	public Result<IBindGroup> GetBindGroup(IBindGroupLayout layout,
		uint32 bufferBinding, IBuffer buffer,
		uint32 textureBinding, ITextureView texture,
		uint32 samplerBinding, ISampler sampler)
	{
		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(bufferBinding, buffer),
			BindGroupEntry.Texture(textureBinding, texture),
			BindGroupEntry.Sampler(samplerBinding, sampler)
		);
		return GetBindGroup(layout, entries);
	}

	/// Gets or creates a bind group with the specified entries.
	public Result<IBindGroup> GetBindGroup(IBindGroupLayout layout, Span<BindGroupEntry> entries)
	{
		let key = ComputeKey(layout, entries);

		if (mCache.TryGetValue(key, var cached))
		{
			cached.LastUsedFrame = mCurrentFrame;
			mCache[key] = cached;
			return .Ok(cached.BindGroup);
		}

		// Create new bind group
		BindGroupDescriptor desc = .(layout, entries);
		if (mDevice.CreateBindGroup(&desc) case .Ok(let bindGroup))
		{
			mCache[key] = .()
			{
				BindGroup = bindGroup,
				LastUsedFrame = mCurrentFrame
			};
			return .Ok(bindGroup);
		}

		return .Err;
	}

	/// Computes a hash key for the bind group configuration.
	private int ComputeKey(IBindGroupLayout layout, Span<BindGroupEntry> entries)
	{
		int hash = Internal.UnsafeCastToPtr(layout).GetHashCode();

		for (let entry in entries)
		{
			hash = hash * 31 + (int)entry.Binding;

			// Hash buffer if present
			if (entry.Buffer != null)
			{
				hash = hash * 31 + Internal.UnsafeCastToPtr(entry.Buffer).GetHashCode();
				hash = hash * 31 + (int)entry.BufferOffset;
				hash = hash * 31 + (int)entry.BufferSize;
			}

			// Hash sampler if present
			if (entry.Sampler != null)
				hash = hash * 31 + Internal.UnsafeCastToPtr(entry.Sampler).GetHashCode();

			// Hash texture view if present
			if (entry.TextureView != null)
				hash = hash * 31 + Internal.UnsafeCastToPtr(entry.TextureView).GetHashCode();
		}

		return hash;
	}

	/// Releases bind groups that haven't been used recently.
	private void ReleaseUnusedBindGroups()
	{
		List<int> keysToRemove = scope .();

		for (let kv in mCache)
		{
			if ((mCurrentFrame - kv.value.LastUsedFrame) > mMaxUnusedFrames)
			{
				keysToRemove.Add(kv.key);
			}
		}

		for (let key in keysToRemove)
		{
			if (mCache.TryGetValue(key, let cached))
			{
				delete cached.BindGroup;
				mCache.Remove(key);
			}
		}
	}

	/// Clears all cached bind groups.
	public void Clear()
	{
		for (let kv in mCache)
			delete kv.value.BindGroup;
		mCache.Clear();
	}

	/// Number of cached bind groups.
	public int32 CachedCount => (int32)mCache.Count;
}
