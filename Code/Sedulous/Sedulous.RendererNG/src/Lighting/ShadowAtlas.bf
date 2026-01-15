namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Region in the shadow atlas.
struct ShadowAtlasRegion
{
	public uint32 X;       // X offset in atlas
	public uint32 Y;       // Y offset in atlas
	public uint32 Size;    // Region size (square)
	public uint32 LightIndex; // Light this region is assigned to

	public const uint32 Invalid = uint32.MaxValue;

	/// Computes UV offset and scale for this region.
	public void GetUVTransform(uint32 atlasSize, out Vector4 uvTransform)
	{
		float invAtlasSize = 1.0f / atlasSize;
		uvTransform = .(
			(float)X * invAtlasSize,
			(float)Y * invAtlasSize,
			(float)Size * invAtlasSize,
			(float)Size * invAtlasSize
		);
	}
}

/// GPU data for shadow atlas lookup.
[CRepr]
struct ShadowAtlasData
{
	public Vector4 AtlasParams;  // x=invSize, y=bias, z=normalBias, w=softness
	public const uint32 Size = 16;
}

/// Per-light shadow data for GPU.
[CRepr]
struct LocalShadowData
{
	public Matrix ViewProjection;    // Light's view-projection
	public Vector4 UVTransform;      // xy=offset, zw=scale
	public Vector4 ShadowParams;     // x=near, y=far, z=bias, w=unused

	public const uint32 Size = 96;
}

/// Manages a shadow atlas texture for local (point/spot) lights.
/// Uses a simple shelf-packing algorithm for region allocation.
class ShadowAtlas : IDisposable
{
	private IDevice mDevice;

	// Configuration
	public readonly uint32 AtlasSize;
	public readonly uint32 MinRegionSize;
	public readonly uint32 MaxRegionSize;

	// Atlas texture
	private ITexture mAtlasTexture ~ delete _;
	private ITextureView mAtlasView ~ delete _;

	// Region allocation
	private List<ShadowAtlasRegion> mAllocatedRegions = new .() ~ delete _;
	private List<Shelf> mShelves = new .() ~ delete _;

	// GPU data
	private IBuffer mShadowDataBuffer ~ delete _;
	private LocalShadowData[64] mShadowData;
	private uint32 mShadowCount;

	// Shadow parameters
	public float ShadowBias = 0.002f;
	public float ShadowNormalBias = 0.02f;
	public float ShadowSoftness = 1.0f;

	/// Shelf for packing algorithm.
	private struct Shelf
	{
		public uint32 Y;
		public uint32 Height;
		public uint32 UsedWidth;
	}

	/// Creates shadow atlas with specified size.
	public this(uint32 atlasSize = 4096, uint32 minRegion = 256, uint32 maxRegion = 1024)
	{
		AtlasSize = atlasSize;
		MinRegionSize = minRegion;
		MaxRegionSize = maxRegion;
	}

	/// Initializes atlas resources.
	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create atlas texture
		var texDesc = TextureDescriptor();
		texDesc.Width = AtlasSize;
		texDesc.Height = AtlasSize;
		texDesc.MipLevelCount = 1;
		texDesc.ArrayLayerCount = 1;
		texDesc.Format = .Depth32Float;
		texDesc.Usage = .DepthStencil | .Sampled;
		texDesc.Dimension = .Texture2D;
		texDesc.Label = "ShadowAtlas";

		switch (device.CreateTexture(&texDesc))
		{
		case .Ok(let texture):
			mAtlasTexture = texture;
		case .Err:
			return .Err;
		}

		// Create view for shader sampling
		var viewDesc = TextureViewDescriptor();
		viewDesc.Format = .Depth32Float;
		viewDesc.Dimension = .Texture2D;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = 1;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = 1;
		viewDesc.Aspect = .DepthOnly;

		switch (device.CreateTextureView(mAtlasTexture, &viewDesc))
		{
		case .Ok(let view):
			mAtlasView = view;
		case .Err:
			return .Err;
		}

		// Create shadow data buffer
		var bufDesc = BufferDescriptor(LocalShadowData.Size * 64, .Uniform, .Upload);
		bufDesc.Label = "LocalShadowDataBuffer";

		switch (device.CreateBuffer(&bufDesc))
		{
		case .Ok(let buffer):
			mShadowDataBuffer = buffer;
		case .Err:
			return .Err;
		}

		return .Ok;
	}

	/// Clears all allocations for a new frame.
	public void BeginFrame()
	{
		mAllocatedRegions.Clear();
		mShelves.Clear();
		mShadowCount = 0;
	}

	/// Allocates a region for a shadow-casting light.
	/// Returns the region index, or Invalid if allocation failed.
	public uint32 AllocateRegion(uint32 lightIndex, uint32 requestedSize)
	{
		// Clamp to valid range
		uint32 size = Math.Clamp(requestedSize, MinRegionSize, MaxRegionSize);

		// Round up to power of 2
		size = NextPowerOf2(size);

		// Try to find space in existing shelves
		for (int i = 0; i < mShelves.Count; i++)
		{
			ref Shelf shelf = ref mShelves[i];
			if (shelf.Height >= size && shelf.UsedWidth + size <= AtlasSize)
			{
				// Found space
				ShadowAtlasRegion region;
				region.X = shelf.UsedWidth;
				region.Y = shelf.Y;
				region.Size = size;
				region.LightIndex = lightIndex;

				shelf.UsedWidth += size;
				mAllocatedRegions.Add(region);
				return (uint32)(mAllocatedRegions.Count - 1);
			}
		}

		// Need new shelf
		uint32 newShelfY = 0;
		for (let shelf in mShelves)
			newShelfY += shelf.Height;

		if (newShelfY + size > AtlasSize)
			return ShadowAtlasRegion.Invalid; // Atlas full

		Shelf newShelf;
		newShelf.Y = newShelfY;
		newShelf.Height = size;
		newShelf.UsedWidth = size;
		mShelves.Add(newShelf);

		ShadowAtlasRegion region;
		region.X = 0;
		region.Y = newShelfY;
		region.Size = size;
		region.LightIndex = lightIndex;

		mAllocatedRegions.Add(region);
		return (uint32)(mAllocatedRegions.Count - 1);
	}

	/// Adds shadow data for a light (call after AllocateRegion).
	public void SetShadowData(uint32 regionIndex, Matrix viewProjection, float nearPlane, float farPlane)
	{
		if (regionIndex >= mAllocatedRegions.Count || mShadowCount >= 64)
			return;

		let region = mAllocatedRegions[regionIndex];

		var data = LocalShadowData();
		data.ViewProjection = viewProjection;
		region.GetUVTransform(AtlasSize, out data.UVTransform);
		data.ShadowParams = .(nearPlane, farPlane, ShadowBias, 0);

		mShadowData[mShadowCount] = data;
		mShadowCount++;
	}

	/// Uploads shadow data to GPU.
	public void Upload()
	{
		if (mShadowDataBuffer == null || mShadowCount == 0)
			return;

		let ptr = mShadowDataBuffer.Map();
		if (ptr != null)
		{
			Internal.MemCpy(ptr, &mShadowData, mShadowCount * LocalShadowData.Size);
			mShadowDataBuffer.Unmap();
		}
	}

	/// Gets a region by index.
	public ShadowAtlasRegion GetRegion(uint32 index)
	{
		if (index < mAllocatedRegions.Count)
			return mAllocatedRegions[index];
		return .() { X = 0, Y = 0, Size = 0, LightIndex = ShadowAtlasRegion.Invalid };
	}

	/// Gets all allocated regions (for rendering shadow maps).
	public Span<ShadowAtlasRegion> Regions => mAllocatedRegions;

	/// Gets atlas texture.
	public ITexture AtlasTexture => mAtlasTexture;

	/// Gets atlas view for shader sampling.
	public ITextureView AtlasView => mAtlasView;

	/// Gets shadow data buffer.
	public IBuffer ShadowDataBuffer => mShadowDataBuffer;

	/// Gets allocated region count.
	public int RegionCount => mAllocatedRegions.Count;

	/// Gets shadow data count.
	public uint32 ShadowCount => mShadowCount;

	/// Round up to next power of 2.
	private static uint32 NextPowerOf2(uint32 value)
	{
		var v = value;
		v--;
		v |= v >> 1;
		v |= v >> 2;
		v |= v >> 4;
		v |= v >> 8;
		v |= v >> 16;
		v++;
		return v;
	}

	/// Gets statistics.
	public void GetStats(String outStats)
	{
		uint32 usedArea = 0;
		for (let region in mAllocatedRegions)
			usedArea += region.Size * region.Size;

		float utilization = (float)usedArea / (AtlasSize * AtlasSize) * 100;

		outStats.AppendF("Shadow Atlas:\n");
		outStats.AppendF("  Size: {}x{}\n", AtlasSize, AtlasSize);
		outStats.AppendF("  Regions: {}\n", mAllocatedRegions.Count);
		outStats.AppendF("  Shelves: {}\n", mShelves.Count);
		outStats.AppendF("  Utilization: {:.1f}%\n", utilization);
	}

	public void Dispose()
	{
		// Resources cleaned up by destructor
	}
}
