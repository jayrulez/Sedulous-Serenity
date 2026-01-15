namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;

/// Key for bind group layout lookup.
struct LayoutKey : IHashable, IEquatable<LayoutKey>
{
	public int Hash;
	public int BindingCount;

	public this(Span<BindGroupLayoutEntry> entries)
	{
		Hash = 0;
		for (let entry in entries)
		{
			Hash = Hash * 31 + (int)entry.Binding;
			Hash = Hash * 31 + (int)entry.Type;
			Hash = Hash * 31 + (int)entry.Visibility;
		}
		BindingCount = entries.Length;
	}

	public int GetHashCode() => Hash;

	public bool Equals(LayoutKey other)
	{
		return Hash == other.Hash && BindingCount == other.BindingCount;
	}
}

/// Caches bind group layouts to avoid redundant creation.
class BindGroupLayoutCache : IDisposable
{
	private IDevice mDevice;

	/// Cache by layout key.
	private Dictionary<LayoutKey, IBindGroupLayout> mCache = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	/// Initializes the layout cache.
	public void Initialize(IDevice device)
	{
		mDevice = device;
	}

	/// Total cached layouts.
	public int Count => mCache.Count;

	/// Gets or creates a bind group layout.
	public Result<IBindGroupLayout> GetOrCreate(Span<BindGroupLayoutEntry> entries)
	{
		let key = LayoutKey(entries);

		// Check cache
		if (mCache.TryGetValue(key, let cached))
			return cached;

		// Create layout
		var desc = BindGroupLayoutDescriptor();
		desc.Entries = entries;

		switch (mDevice.CreateBindGroupLayout(&desc))
		{
		case .Ok(let layout):
			mCache[key] = layout;
			return layout;
		case .Err:
			return .Err;
		}
	}

	/// Creates standard per-frame layout (camera, lighting, etc.).
	public Result<IBindGroupLayout> GetPerFrameLayout()
	{
		BindGroupLayoutEntry[4] entries = .(
			.UniformBuffer(0, .Vertex | .Fragment), // CameraData
			.UniformBuffer(1, .Fragment),           // LightingData
			.UniformBuffer(2, .Fragment),           // TimeData
			.UniformBuffer(3, .Vertex | .Fragment)  // Reserved
		);
		return GetOrCreate(entries);
	}

	/// Creates standard per-material layout (textures, samplers).
	public Result<IBindGroupLayout> GetPerMaterialLayout()
	{
		BindGroupLayoutEntry[8] entries = .(
			.SampledTexture(0, .Fragment),  // Albedo
			.SampledTexture(1, .Fragment),  // Normal
			.SampledTexture(2, .Fragment),  // Metallic/Roughness
			.SampledTexture(3, .Fragment),  // Occlusion
			.SampledTexture(4, .Fragment),  // Emissive
			.SampledTexture(5, .Fragment),  // Reserved
			.Sampler(6, .Fragment),         // Main sampler
			.Sampler(7, .Fragment)          // Reserved sampler
		);
		return GetOrCreate(entries);
	}

	/// Creates standard per-object layout (transforms).
	public Result<IBindGroupLayout> GetPerObjectLayout()
	{
		BindGroupLayoutEntry[2] entries = .(
			.UniformBuffer(0, .Vertex), // ObjectTransforms
			.UniformBuffer(1, .Vertex)  // BoneMatrices (for skinned)
		);
		return GetOrCreate(entries);
	}

	/// Clears all cached layouts.
	public void Clear()
	{
		for (let kv in mCache)
			delete kv.value;
		mCache.Clear();
	}

	/// Gets cache statistics.
	public void GetStats(String outStats)
	{
		outStats.AppendF("Bind Group Layout Cache:\n");
		outStats.AppendF("  Cached layouts: {}\n", mCache.Count);
	}

	public void Dispose()
	{
		Clear();
	}
}
