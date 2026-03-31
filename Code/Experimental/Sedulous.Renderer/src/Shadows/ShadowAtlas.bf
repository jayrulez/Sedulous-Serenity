namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// GPU data for a single shadow tile in the atlas.
/// Must match the GPUShadowData struct in forward_pbr.hlsl exactly.
[CRepr]
struct GPUShadowData
{
	public Matrix ViewProjection;       // 64 bytes
	public Vector4 UVOffsetScale;       // 16 bytes (xy=offset, zw=scale)
	public Vector4 Params;              // 16 bytes (x=bias, y=nearPlane, z=farPlane, w=lightType 0=spot 1=point)
	// Total: 96 bytes
}

/// A tile allocation in the shadow atlas.
struct ShadowTile
{
	/// Tile index in the atlas grid.
	public int32 Index;
	/// Owner light key (0 = unallocated).
	public uint64 LightKey;
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
	/// Whether this tile is allocated.
	public bool IsAllocated;
	/// For point lights: which face (0-5). For spot lights: 0.
	public uint8 CubeFace;
	/// Index in the GPUShadowData buffer for this tile.
	public int32 ShadowDataIndex;
}

/// Manages a shadow atlas for point and spot light shadows.
/// Uses a uniform-grid tile allocator on a single Depth32Float Texture2D.
/// Each spot light gets 1 tile, each point light gets 6 tiles (cubemap faces).
/// Owned by ShadowSystem.
class ShadowAtlas
{
	private IDevice mDevice;

	// --- GPU resources ---
	private ITexture mAtlasTexture;
	private ITextureView mAtlasView;            // SRV for sampling in forward pass
	private ITextureView mAtlasDsvView;          // DSV for rendering
	// Shadow data: staging (CpuToGpu, CopySrc) → GPU (GpuOnly, Storage|CopyDst)
	private IBuffer[RenderConfig.FrameBufferCount] mStagingDataBuffers;
	private void*[RenderConfig.FrameBufferCount] mStagingDataPtrs;
	private IBuffer[RenderConfig.FrameBufferCount] mGpuDataBuffers;

	// --- Tile management ---
	private ShadowTile[RenderConfig.ShadowAtlasTotalTiles] mTiles;
	private List<int32> mFreeTiles = new .() ~ delete _;

	// --- Shadow data for GPU upload ---
	private GPUShadowData[RenderConfig.ShadowAtlasTotalTiles] mShadowData;
	private int32 mActiveShadowCount;

	private bool mFirstFrame = true;

	/// Number of active shadow tiles this frame.
	public int32 ActiveShadowCount => mActiveShadowCount;

	/// Gets the atlas texture view for sampling in the forward shader.
	public ITextureView GetAtlasTextureView() => mAtlasView;

	/// Gets the atlas DSV for rendering.
	public ITextureView GetAtlasDsvView() => mAtlasDsvView;

	/// Gets the atlas texture for barriers.
	public ITexture GetAtlasTexture() => mAtlasTexture;

	/// Gets the GPU shadow data storage buffer for the given frame index.
	public IBuffer GetShadowDataBuffer(int frameIndex) => mGpuDataBuffers[frameIndex];

	/// Whether this is the first frame (needs initial barrier).
	public bool IsFirstFrame => mFirstFrame;

	/// Marks first frame as done.
	public void ClearFirstFrame() { mFirstFrame = false; }

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// --- Atlas texture (single 2D depth texture) ---
		let texResult = device.CreateTexture(TextureDesc.Tex2D(
			.Depth32Float,
			(uint32)RenderConfig.ShadowAtlasSize,
			(uint32)RenderConfig.ShadowAtlasSize,
			.DepthStencil | .Sampled,
			label: "ShadowAtlas"
		));
		if (texResult case .Err)
			return .Err;
		mAtlasTexture = texResult.Value;

		// SRV for sampling in forward pass
		let srvResult = device.CreateTextureView(mAtlasTexture, TextureViewDesc()
		{
			Dimension = .Texture2D,
			Aspect = .DepthOnly,
			Label = "ShadowAtlas_SRV"
		});
		if (srvResult case .Err)
			return .Err;
		mAtlasView = srvResult.Value;

		// DSV for rendering shadow passes
		let dsvResult = device.CreateTextureView(mAtlasTexture, TextureViewDesc()
		{
			Dimension = .Texture2D,
			Aspect = .DepthOnly,
			Label = "ShadowAtlas_DSV"
		});
		if (dsvResult case .Err)
			return .Err;
		mAtlasDsvView = dsvResult.Value;

		// --- Shadow data buffers: staging (CPU-writable) + GPU (shader-readable) ---
		let dataSize = (uint64)(RenderConfig.ShadowAtlasTotalTiles * sizeof(GPUShadowData));
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// Staging buffer — CPU writes shadow data here
			let stagingResult = device.CreateBuffer(BufferDesc()
			{
				Size = dataSize,
				Usage = .CopySrc,
				Memory = .CpuToGpu,
				Label = "ShadowAtlasData_Staging"
			});
			if (stagingResult case .Err)
				return .Err;
			mStagingDataBuffers[i] = stagingResult.Value;
			mStagingDataPtrs[i] = mStagingDataBuffers[i].Map();

			// GPU storage buffer — shader reads from here
			let gpuResult = device.CreateBuffer(BufferDesc()
			{
				Size = dataSize,
				Usage = .Storage | .CopyDst,
				Memory = .GpuOnly,
				Label = "ShadowAtlasData"
			});
			if (gpuResult case .Err)
				return .Err;
			mGpuDataBuffers[i] = gpuResult.Value;
		}

		// --- Initialize tile grid ---
		InitializeTiles();

		return .Ok;
	}

	private void InitializeTiles()
	{
		let tilesPerSide = RenderConfig.ShadowAtlasTilesPerSide;
		let tileUVSize = 1.0f / (float)tilesPerSide;

		for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
		{
			let tileX = (uint32)(i % tilesPerSide);
			let tileY = (uint32)(i / tilesPerSide);

			mTiles[i] = .()
			{
				Index = (int32)i,
				LightKey = 0,
				UVOffset = Vector2((float)tileX * tileUVSize, (float)tileY * tileUVSize),
				UVScale = Vector2(tileUVSize, tileUVSize),
				ViewportX = tileX * (uint32)RenderConfig.ShadowAtlasTileSize,
				ViewportY = tileY * (uint32)RenderConfig.ShadowAtlasTileSize,
				ViewportSize = (uint32)RenderConfig.ShadowAtlasTileSize,
				ViewProjection = .Identity,
				IsAllocated = false,
				CubeFace = 0,
				ShadowDataIndex = -1
			};

			mFreeTiles.Add((int32)i);
		}
	}

	/// Checks if a light already has tiles allocated.
	public bool HasAllocation(uint64 lightKey)
	{
		for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
		{
			if (mTiles[i].IsAllocated && mTiles[i].LightKey == lightKey)
				return true;
		}
		return false;
	}

	/// Allocates a single tile for a spot light.
	/// Returns the first tile index, or -1 on failure.
	public int32 AllocateSpotLight(uint64 lightKey)
	{
		if (mFreeTiles.IsEmpty)
			return -1;

		let tileIndex = mFreeTiles.PopBack();
		mTiles[tileIndex].IsAllocated = true;
		mTiles[tileIndex].LightKey = lightKey;
		mTiles[tileIndex].CubeFace = 0;

		return tileIndex;
	}

	/// Allocates 6 tiles for a point light (cubemap faces).
	/// Returns the first tile index, or -1 on failure.
	public int32 AllocatePointLight(uint64 lightKey)
	{
		if (mFreeTiles.Count < 6)
			return -1;

		int32 firstIndex = -1;
		for (int face = 0; face < 6; face++)
		{
			let tileIndex = mFreeTiles.PopBack();
			mTiles[tileIndex].IsAllocated = true;
			mTiles[tileIndex].LightKey = lightKey;
			mTiles[tileIndex].CubeFace = (uint8)face;

			if (face == 0)
				firstIndex = tileIndex;
		}

		return firstIndex;
	}

	/// Releases all tiles allocated to a light.
	public void ReleaseTiles(uint64 lightKey)
	{
		for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
		{
			if (mTiles[i].IsAllocated && mTiles[i].LightKey == lightKey)
			{
				mTiles[i].IsAllocated = false;
				mTiles[i].LightKey = 0;
				mTiles[i].ShadowDataIndex = -1;
				mFreeTiles.Add((int32)i);
			}
		}
	}

	/// Gets the shadow data buffer index for a light.
	/// For spot lights, this is the single shadow data index.
	/// For point lights, this is face 0's index; faces 1-5 follow consecutively.
	/// Returns -1 if not allocated or data not yet uploaded.
	public int32 GetShadowDataIndex(uint64 lightKey)
	{
		// For point lights, find face 0's data index (faces are consecutive after UploadShadowData)
		// For spot lights, find the single tile's data index
		int32 minDataIndex = int32.MaxValue;
		for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
		{
			if (mTiles[i].IsAllocated && mTiles[i].LightKey == lightKey && mTiles[i].ShadowDataIndex >= 0)
			{
				if (mTiles[i].CubeFace == 0)
					return mTiles[i].ShadowDataIndex;
				if (mTiles[i].ShadowDataIndex < minDataIndex)
					minDataIndex = mTiles[i].ShadowDataIndex;
			}
		}
		return (minDataIndex < int32.MaxValue) ? minDataIndex : -1;
	}

	/// Updates the VP matrix for a spot light tile.
	public void UpdateSpotLight(uint64 lightKey, ref LightProxy proxy)
	{
		for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
		{
			if (mTiles[i].IsAllocated && mTiles[i].LightKey == lightKey)
			{
				let target = proxy.Position + proxy.Direction;
				let up = (Math.Abs(proxy.Direction.Y) > 0.99f) ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
				let viewMatrix = Matrix.CreateLookAt(proxy.Position, target, up);
				let fov = Math.Max(proxy.OuterConeAngle * 2.0f, 0.1f);
				let projMatrix = Matrix.CreatePerspectiveFieldOfView(fov, 1.0f, 0.1f, proxy.Range);
				mTiles[i].ViewProjection = viewMatrix * projMatrix;
				return;
			}
		}
	}

	/// Updates VP matrices for all 6 faces of a point light.
	public void UpdatePointLight(uint64 lightKey, ref LightProxy proxy)
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

		let projMatrix = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 2.0f, 1.0f, 0.1f, proxy.Range);

		for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
		{
			if (mTiles[i].IsAllocated && mTiles[i].LightKey == lightKey)
			{
				let face = (int)mTiles[i].CubeFace;
				let target = proxy.Position + directions[face];
				let viewMatrix = Matrix.CreateLookAt(proxy.Position, target, upVectors[face]);
				mTiles[i].ViewProjection = viewMatrix * projMatrix;
			}
		}
	}

	/// Builds GPU shadow data and assigns ShadowDataIndex to each tile.
	/// Groups point light faces consecutively in face order (0-5) so the shader
	/// can sample ShadowData[shadowIndex + faceIndex].
	/// Call after all VP matrices are updated.
	public void UploadShadowData(int frameIndex)
	{
		mActiveShadowCount = 0;

		// Clear all data indices
		for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
			mTiles[i].ShadowDataIndex = -1;

		// Collect unique light keys to group faces together
		uint64[RenderConfig.ShadowAtlasTotalTiles] seenKeys = .();
		int seenCount = 0;

		for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
		{
			if (!mTiles[i].IsAllocated)
				continue;

			let key = mTiles[i].LightKey;
			bool alreadySeen = false;
			for (int s = 0; s < seenCount; s++)
			{
				if (seenKeys[s] == key)
				{
					alreadySeen = true;
					break;
				}
			}
			if (!alreadySeen)
				seenKeys[seenCount++] = key;
		}

		// For each unique light, write its tiles in face order
		for (int s = 0; s < seenCount; s++)
		{
			let key = seenKeys[s];

			// Count faces for this light to determine if it's a point light (6 faces)
			int faceCount = 0;
			for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
			{
				if (mTiles[i].IsAllocated && mTiles[i].LightKey == key)
					faceCount++;
			}

			if (faceCount == 6)
			{
				// Point light: write faces in order 0-5
				for (uint8 face = 0; face < 6; face++)
				{
					for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
					{
						if (mTiles[i].IsAllocated && mTiles[i].LightKey == key && mTiles[i].CubeFace == face)
						{
							mTiles[i].ShadowDataIndex = mActiveShadowCount;
							WriteShadowData(ref mTiles[i]);
							break;
						}
					}
				}
			}
			else
			{
				// Spot light (or single tile): write directly
				for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
				{
					if (mTiles[i].IsAllocated && mTiles[i].LightKey == key)
					{
						mTiles[i].ShadowDataIndex = mActiveShadowCount;
						WriteShadowData(ref mTiles[i]);
					}
				}
			}
		}

		if (mActiveShadowCount > 0 && mStagingDataPtrs[frameIndex] != null)
		{
			let uploadSize = mActiveShadowCount * sizeof(GPUShadowData);
			Internal.MemCpy(mStagingDataPtrs[frameIndex], &mShadowData[0], uploadSize);
		}
	}

	private void WriteShadowData(ref ShadowTile tile)
	{
		mShadowData[mActiveShadowCount] = .()
		{
			ViewProjection = tile.ViewProjection,
			UVOffsetScale = .(tile.UVOffset.X, tile.UVOffset.Y, tile.UVScale.X, tile.UVScale.Y),
			Params = .(0.003f, 0.1f, 100.0f, 0.0f)
		};
		mActiveShadowCount++;
	}

	/// Records the staging → GPU copy for shadow data. Call on the encoder before atlas passes.
	public void RecordUpload(ICommandEncoder encoder, int frameIndex)
	{
		if (mActiveShadowCount == 0)
			return;

		let copySize = (uint64)(mActiveShadowCount * sizeof(GPUShadowData));
		encoder.CopyBufferToBuffer(mStagingDataBuffers[frameIndex], 0, mGpuDataBuffers[frameIndex], 0, copySize);
	}

	/// Gets a tile by index. Returns null if index is out of range.
	public ShadowTile* GetTile(int index)
	{
		if (index >= 0 && index < RenderConfig.ShadowAtlasTotalTiles)
			return &mTiles[index];
		return null;
	}

	public void Shutdown()
	{
		if (mDevice == null)
			return;

		// Shadow data buffers
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mStagingDataBuffers[i] != null)
			{
				mStagingDataBuffers[i].Unmap();
				mStagingDataPtrs[i] = null;
				mDevice.DestroyBuffer(ref mStagingDataBuffers[i]);
			}
			if (mGpuDataBuffers[i] != null)
				mDevice.DestroyBuffer(ref mGpuDataBuffers[i]);
		}

		// Texture views
		if (mAtlasView != null)
			mDevice.DestroyTextureView(ref mAtlasView);
		if (mAtlasDsvView != null)
			mDevice.DestroyTextureView(ref mAtlasDsvView);

		// Texture
		if (mAtlasTexture != null)
			mDevice.DestroyTexture(ref mAtlasTexture);
	}
}
