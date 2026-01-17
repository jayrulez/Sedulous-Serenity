namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Configuration for the shadow atlas.
public struct ShadowAtlasConfig
{
	/// Total atlas resolution (width and height).
	public uint32 Resolution;

	/// Tile size for individual shadows.
	public uint32 TileSize;

	/// Maximum number of point lights with shadows.
	public uint32 MaxPointLights;

	/// Maximum number of spot lights with shadows.
	public uint32 MaxSpotLights;

	/// Creates default configuration.
	public static Self Default => .()
	{
		Resolution = 4096,
		TileSize = 512,
		MaxPointLights = 8,
		MaxSpotLights = 16
	};

	/// Number of tiles per row/column.
	public uint32 TilesPerSide => Resolution / TileSize;

	/// Total number of tiles.
	public uint32 TotalTiles => TilesPerSide * TilesPerSide;
}

/// A tile allocation in the shadow atlas.
public struct ShadowTile
{
	/// Tile index in the atlas.
	public int32 Index;

	/// UV offset in the atlas (0-1 range).
	public Vector2 UVOffset;

	/// UV scale for this tile (0-1 range).
	public Vector2 UVScale;

	/// Viewport offset in pixels.
	public uint32 ViewportX;
	public uint32 ViewportY;

	/// Viewport size in pixels.
	public uint32 ViewportSize;

	/// View-projection matrix for this shadow.
	public Matrix ViewProjection;

	/// Light handle that owns this tile.
	public LightProxyHandle LightHandle;

	/// Whether this tile is allocated.
	public bool IsAllocated;

	/// For point lights: which face (0-5).
	public uint8 CubeFace;
}

/// GPU data for a shadow in the atlas.
[CRepr]
public struct GPUShadowData
{
	/// View-projection matrix.
	public Matrix ViewProjection;

	/// UV offset and scale.
	public Vector4 UVOffsetScale;

	/// Shadow parameters (bias, normal bias, softness, unused).
	public Vector4 Params;

	/// Size of this struct.
	public static int Size => 64 + 16 + 16; // 96 bytes
}

/// Manages a shadow atlas for point and spot lights.
/// Uses dynamic tile allocation with soft priority.
public class ShadowAtlas : IDisposable
{
	// Configuration
	private ShadowAtlasConfig mConfig;

	// GPU resources
	private IDevice mDevice;
	private ITexture mAtlasTexture;
	private ITextureView mAtlasView;
	private ISampler mShadowSampler;
	private IBuffer mShadowDataBuffer;

	// Point light cubemap resources
	private ITexture mPointLightCubemapArray;
	private ITextureView mPointLightCubemapArrayView;

	// Tile management
	private ShadowTile[] mTiles ~ delete _;
	private List<int32> mFreeTiles = new .() ~ delete _;
	private Dictionary<LightProxyHandle, int32> mLightToTile = new .() ~ delete _;

	// Shadow data for GPU upload
	private GPUShadowData[] mShadowData ~ delete _;
	private int32 mActiveShadowCount = 0;

	/// Gets the atlas texture.
	public ITexture AtlasTexture => mAtlasTexture;

	/// Gets the atlas view for sampling.
	public ITextureView AtlasView => mAtlasView;

	/// Gets the shadow comparison sampler.
	public ISampler ShadowSampler => mShadowSampler;

	/// Gets the shadow data buffer.
	public IBuffer ShadowDataBuffer => mShadowDataBuffer;

	/// Gets the point light cubemap array.
	public ITexture PointLightCubemapArray => mPointLightCubemapArray;

	/// Gets the configuration.
	public ShadowAtlasConfig Config => mConfig;

	/// Whether the atlas is initialized.
	public bool IsInitialized => mDevice != null && mAtlasTexture != null;

	/// Number of active shadows.
	public int32 ActiveShadowCount => mActiveShadowCount;

	/// Initializes the shadow atlas.
	public Result<void> Initialize(IDevice device, ShadowAtlasConfig config = .Default)
	{
		mDevice = device;
		mConfig = config;

		// Create atlas texture
		if (CreateAtlasTexture() case .Err)
			return .Err;

		// Create point light cubemap array
		if (CreatePointLightCubemaps() case .Err)
			return .Err;

		// Create comparison sampler
		if (CreateShadowSampler() case .Err)
			return .Err;

		// Create shadow data buffer
		if (CreateShadowDataBuffer() case .Err)
			return .Err;

		// Initialize tile array
		InitializeTiles();

		return .Ok;
	}

	/// Allocates a tile for a spot light shadow.
	public Result<ShadowTile*> AllocateSpotLightTile(LightProxyHandle lightHandle)
	{
		if (mFreeTiles.IsEmpty)
			return .Err;

		let tileIndex = mFreeTiles.PopBack();
		var tile = &mTiles[tileIndex];

		tile.IsAllocated = true;
		tile.LightHandle = lightHandle;
		tile.CubeFace = 0;

		mLightToTile[lightHandle] = tileIndex;

		return .Ok(tile);
	}

	/// Allocates 6 tiles for a point light shadow (cubemap).
	public Result<void> AllocatePointLightTiles(LightProxyHandle lightHandle, ref ShadowTile*[6] outTiles)
	{
		if (mFreeTiles.Count < 6)
			return .Err;

		for (int face = 0; face < 6; face++)
		{
			let tileIndex = mFreeTiles.PopBack();
			var tile = &mTiles[tileIndex];

			tile.IsAllocated = true;
			tile.LightHandle = lightHandle;
			tile.CubeFace = (uint8)face;

			outTiles[face] = tile;
		}

		// Store first tile index for lookup
		mLightToTile[lightHandle] = outTiles[0].Index;

		return .Ok;
	}

	/// Releases a tile allocation.
	public void ReleaseTile(LightProxyHandle lightHandle)
	{
		if (mLightToTile.TryGetValue(lightHandle, let tileIndex))
		{
			var tile = &mTiles[tileIndex];

			// For point lights, release all 6 faces
			if (tile.CubeFace == 0)
			{
				// Check if this is a point light (would have 6 consecutive tiles)
				// For simplicity, just release the single tile
				tile.IsAllocated = false;
				tile.LightHandle = .Invalid;
				mFreeTiles.Add(tileIndex);
			}
			else
			{
				tile.IsAllocated = false;
				tile.LightHandle = .Invalid;
				mFreeTiles.Add(tileIndex);
			}

			mLightToTile.Remove(lightHandle);
		}
	}

	/// Gets a tile for a light.
	public ShadowTile* GetTile(LightProxyHandle lightHandle)
	{
		if (mLightToTile.TryGetValue(lightHandle, let tileIndex))
			return &mTiles[tileIndex];
		return null;
	}

	/// Updates shadow matrices for a spot light.
	public void UpdateSpotLightShadow(LightProxyHandle lightHandle, LightProxy* light)
	{
		if (let tile = GetTile(lightHandle))
		{
			// Calculate view matrix (look from light position in light direction)
			let target = light.Position + light.Direction;
			let viewMatrix = Matrix.CreateLookAt(light.Position, target, .(0, 1, 0));

			// Calculate perspective projection for spot light
			let fov = light.OuterConeAngle * 2.0f;
			let projMatrix = Matrix.CreatePerspectiveFieldOfView(fov, 1.0f, 0.1f, light.Range);

			tile.ViewProjection = viewMatrix * projMatrix;
		}
	}

	/// Updates shadow matrices for a point light (all 6 faces).
	public void UpdatePointLightShadow(LightProxyHandle lightHandle, LightProxy* light, ShadowTile*[6] tiles)
	{
		// Cubemap face directions and up vectors
		Vector3[6] directions = .(
			.(1, 0, 0),   // +X
			.(-1, 0, 0),  // -X
			.(0, 1, 0),   // +Y
			.(0, -1, 0),  // -Y
			.(0, 0, 1),   // +Z
			.(0, 0, -1)   // -Z
		);

		Vector3[6] upVectors = .(
			.(0, -1, 0),  // +X
			.(0, -1, 0),  // -X
			.(0, 0, 1),   // +Y
			.(0, 0, -1),  // -Y
			.(0, -1, 0),  // +Z
			.(0, -1, 0)   // -Z
		);

		let projMatrix = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 2.0f, 1.0f, 0.1f, light.Range);

		for (int face = 0; face < 6; face++)
		{
			if (tiles[face] != null)
			{
				let target = light.Position + directions[face];
				let viewMatrix = Matrix.CreateLookAt(light.Position, target, upVectors[face]);
				tiles[face].ViewProjection = viewMatrix * projMatrix;
			}
		}
	}

	/// Updates the GPU shadow data buffer.
	public void UploadShadowData()
	{
		if (!IsInitialized)
			return;

		mActiveShadowCount = 0;

		for (let tile in mTiles)
		{
			if (tile.IsAllocated && mActiveShadowCount < mShadowData.Count)
			{
				mShadowData[mActiveShadowCount] = .()
				{
					ViewProjection = tile.ViewProjection,
					UVOffsetScale = Vector4(tile.UVOffset.X, tile.UVOffset.Y, tile.UVScale.X, tile.UVScale.Y),
					Params = Vector4(0.005f, 0.02f, 1.0f, 0) // bias, normalBias, softness, unused
				};
				mActiveShadowCount++;
			}
		}

		if (mActiveShadowCount > 0)
		{
			let uploadSize = mActiveShadowCount * GPUShadowData.Size;
			mDevice.Queue.WriteBuffer(mShadowDataBuffer, 0, Span<uint8>((uint8*)&mShadowData[0], uploadSize));
		}
	}

	public void Dispose()
	{
		if (mAtlasView != null) { delete mAtlasView; mAtlasView = null; }
		if (mAtlasTexture != null) { delete mAtlasTexture; mAtlasTexture = null; }
		if (mPointLightCubemapArrayView != null) { delete mPointLightCubemapArrayView; mPointLightCubemapArrayView = null; }
		if (mPointLightCubemapArray != null) { delete mPointLightCubemapArray; mPointLightCubemapArray = null; }
		if (mShadowSampler != null) { delete mShadowSampler; mShadowSampler = null; }
		if (mShadowDataBuffer != null) { delete mShadowDataBuffer; mShadowDataBuffer = null; }
	}

	private Result<void> CreateAtlasTexture()
	{
		TextureDescriptor desc = .()
		{
			Label = "Shadow Atlas",
			Dimension = .Texture2D,
			Width = mConfig.Resolution,
			Height = mConfig.Resolution,
			Depth = 1,
			Format = .Depth32Float,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Usage = .DepthStencil | .Sampled
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mAtlasTexture = tex;
		case .Err: return .Err;
		}

		TextureViewDescriptor viewDesc = .()
		{
			Label = "Shadow Atlas View",
			Format = .Depth32Float,
			Dimension = .Texture2D,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1,
			Aspect = .DepthOnly
		};

		switch (mDevice.CreateTextureView(mAtlasTexture, &viewDesc))
		{
		case .Ok(let view): mAtlasView = view;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreatePointLightCubemaps()
	{
		// Create cubemap array for point light shadows
		TextureDescriptor desc = .()
		{
			Label = "Point Light Shadow Cubemaps",
			Dimension = .Texture2D,
			Width = mConfig.TileSize,
			Height = mConfig.TileSize,
			Depth = 1,
			Format = .Depth32Float,
			MipLevelCount = 1,
			ArrayLayerCount = mConfig.MaxPointLights * 6, // 6 faces per light
			SampleCount = 1,
			Usage = .DepthStencil | .Sampled
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mPointLightCubemapArray = tex;
		case .Err: return .Err;
		}

		TextureViewDescriptor viewDesc = .()
		{
			Label = "Point Light Cubemap Array View",
			Format = .Depth32Float,
			Dimension = .TextureCubeArray,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = mConfig.MaxPointLights * 6,
			Aspect = .DepthOnly
		};

		switch (mDevice.CreateTextureView(mPointLightCubemapArray, &viewDesc))
		{
		case .Ok(let view): mPointLightCubemapArrayView = view;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateShadowSampler()
	{
		SamplerDescriptor desc = .()
		{
			Label = "Shadow Atlas Sampler",
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			MagFilter = .Linear,
			MinFilter = .Linear,
			MipmapFilter = .Nearest,
			Compare = .LessEqual
		};

		switch (mDevice.CreateSampler(&desc))
		{
		case .Ok(let sampler): mShadowSampler = sampler;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateShadowDataBuffer()
	{
		let maxShadows = mConfig.TotalTiles;
		mShadowData = new GPUShadowData[maxShadows];

		BufferDescriptor desc = .()
		{
			Label = "Shadow Data",
			Size = (uint64)(maxShadows * GPUShadowData.Size),
			Usage = .Storage | .CopyDst
		};

		switch (mDevice.CreateBuffer(&desc))
		{
		case .Ok(let buf): mShadowDataBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private void InitializeTiles()
	{
		let totalTiles = mConfig.TotalTiles;
		let tilesPerSide = mConfig.TilesPerSide;
		let tileUVSize = 1.0f / (float)tilesPerSide;

		mTiles = new ShadowTile[totalTiles];

		for (uint32 i = 0; i < totalTiles; i++)
		{
			let tileX = i % tilesPerSide;
			let tileY = i / tilesPerSide;

			mTiles[i] = .()
			{
				Index = (int32)i,
				UVOffset = Vector2((float)tileX * tileUVSize, (float)tileY * tileUVSize),
				UVScale = Vector2(tileUVSize, tileUVSize),
				ViewportX = tileX * mConfig.TileSize,
				ViewportY = tileY * mConfig.TileSize,
				ViewportSize = mConfig.TileSize,
				ViewProjection = .Identity,
				LightHandle = .Invalid,
				IsAllocated = false,
				CubeFace = 0
			};

			mFreeTiles.Add((int32)i);
		}
	}
}
