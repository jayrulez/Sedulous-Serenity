namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using System.Diagnostics;

/// Manages the clustered lighting system.
/// Orchestrates cluster grid, light culling, and shadow rendering.
class LightingSystem
{
	// Forward shadow constants for external access
	public const int32 CASCADE_COUNT = ShadowConstants.CASCADE_COUNT;
	public const int32 SHADOW_MAP_SIZE = ShadowConstants.CASCADE_MAP_SIZE;
	public const int32 MAX_FRAMES_IN_FLIGHT = 2;

	private IDevice mDevice;
	private ClusterGrid mClusterGrid ~ delete _;

	// Shadow systems
	private CascadedShadowMaps mCascadedShadows ~ delete _;
	private ShadowAtlas mShadowAtlas ~ delete _;
	private ISampler mShadowSampler ~ delete _;
	private ShadowUniforms mShadowUniforms;

	// Per-frame shadow uniform buffers (to avoid GPU/CPU synchronization issues)
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mShadowUniformBuffers ~ { for (let b in _) delete b; };

	// Directional light (only one for now)
	private LightProxy* mDirectionalLight = null;

	// Active lights for this frame
	private List<LightProxy*> mActiveLights = new .() ~ delete _;

	// Stats
	private int32 mVisibleLightCount = 0;
	private int32 mShadowCasterCount = 0;

	public this(IDevice device)
	{
		mDevice = device;
		mClusterGrid = new ClusterGrid(device);
		mCascadedShadows = new CascadedShadowMaps(device);
		mShadowAtlas = new ShadowAtlas(device);
		mShadowUniforms = ShadowUniforms.Default;
		CreateShadowResources();
	}

	private void CreateShadowResources()
	{
		// Create per-frame shadow uniform buffers
		BufferDescriptor uniformDesc = .((uint64)sizeof(ShadowUniforms), .Uniform, .Upload);
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (mDevice.CreateBuffer(&uniformDesc) case .Ok(let buf))
				mShadowUniformBuffers[i] = buf;
		}

		// Shadow comparison sampler for PCF
		// Comparison is: reference op stored_value
		// LessEqual: returns 1.0 when fragmentDepth <= storedDepth (lit)
		SamplerDescriptor samplerDesc = .()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Nearest,
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			Compare = .LessEqual,  // 1.0 when fragmentDepth <= storedDepth (lit)
			LodMinClamp = 0,
			LodMaxClamp = 0,
			MaxAnisotropy = 1,
			Label = "ShadowComparisonSampler"
		};
		if (mDevice.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mShadowSampler = sampler;
	}

	/// Updates the lighting system for a new frame.
	/// frameIndex should be SwapChain.CurrentFrameIndex for proper buffer synchronization.
	public void Update(CameraProxy* camera, List<LightProxy*> lights, int32 frameIndex)
	{
		if (camera == null)
			return;

		// Update cluster grid for camera
		mClusterGrid.UpdateClusters(camera);

		// Find directional light and gather active point/spot lights
		mDirectionalLight = null;
		mActiveLights.Clear();

		for (let light in lights)
		{
			if (!light.Enabled)
				continue;

			if (light.Type == .Directional)
			{
				// Use first directional light
				if (mDirectionalLight == null)
					mDirectionalLight = light;
			}
			else
			{
				// Point/spot lights go into cluster culling
				mActiveLights.Add(light);
			}
		}

		// Cull lights to clusters (per-frame buffer)
		mClusterGrid.CullLights(mActiveLights, camera, frameIndex);

		// Update uniform buffer with directional light info (per-frame buffer)
		mClusterGrid.UpdateUniforms(camera, mDirectionalLight, frameIndex);

		// Update stats
		mVisibleLightCount = (int32)mActiveLights.Count;
		if (mDirectionalLight != null)
			mVisibleLightCount++;
	}

	/// Prepares shadow data for the frame (call after Update, before rendering shadows).
	/// This updates cascade matrices and allocates atlas tiles, but doesn't render.
	public void PrepareShadows(CameraProxy* camera)
	{
		mShadowCasterCount = 0;
		mShadowAtlas.Reset();

		// Reset shadow uniforms
		mShadowUniforms = ShadowUniforms.Default;

		// Update cascaded shadow maps for directional light
		if (mDirectionalLight != null && mDirectionalLight.CastsShadows)
		{
			mCascadedShadows.UpdateCascades(camera, mDirectionalLight.Direction);

			// Copy cascade data to uniforms
			for (int32 i = 0; i < ShadowConstants.CASCADE_COUNT; i++)
				mShadowUniforms.Cascades[i] = mCascadedShadows.CascadeData[i];

			mShadowUniforms.DirectionalShadowEnabled = 1;
			mDirectionalLight.ShadowMapIndex = 0;  // Cascades use index 0 convention
			mShadowCasterCount++;
		}

		// Allocate shadow atlas tiles for point/spot lights
		int32 tileIndex = 0;
		for (let light in mActiveLights)
		{
			if (!light.CastsShadows)
				continue;

			if (light.Type == .Spot)
			{
				int32 slot = mShadowAtlas.AllocateTile(light);
				if (slot >= 0)
				{
					light.ShadowMapIndex = slot;
					if (tileIndex < ShadowConstants.MAX_SHADOW_TILES)
						mShadowUniforms.ShadowTiles[tileIndex++] = mShadowAtlas.TileData[slot];
					mShadowCasterCount++;
				}
			}
			else if (light.Type == .Point)
			{
				// Point lights need 6 faces
				int32 firstSlot = -1;
				for (int32 face = 0; face < 6; face++)
				{
					int32 slot = mShadowAtlas.AllocateTile(light, face);
					if (slot >= 0)
					{
						if (firstSlot < 0) firstSlot = slot;
						if (tileIndex < ShadowConstants.MAX_SHADOW_TILES)
							mShadowUniforms.ShadowTiles[tileIndex++] = mShadowAtlas.TileData[slot];
					}
				}
				if (firstSlot >= 0)
				{
					light.ShadowMapIndex = firstSlot;
					mShadowCasterCount++;
				}
			}
		}

		mShadowUniforms.ActiveTileCount = (uint32)mShadowAtlas.ActiveTileCount;
	}

	/// Uploads shadow uniform data to GPU for the specified frame.
	public void UploadShadowUniforms(int32 frameIndex)
	{
		if (frameIndex >= 0 && frameIndex < MAX_FRAMES_IN_FLIGHT && mShadowUniformBuffers[frameIndex] != null && mDevice?.Queue != null)
		{
			Span<uint8> data = .((uint8*)&mShadowUniforms, sizeof(ShadowUniforms));
			mDevice.Queue.WriteBuffer(mShadowUniformBuffers[frameIndex], 0, data);
		}
	}

	/// Gets the cluster grid for shader binding.
	public ClusterGrid ClusterGrid => mClusterGrid;

	/// Gets the lighting uniform buffer for shader binding for the specified frame.
	public IBuffer GetLightingUniformBuffer(int32 frameIndex) => mClusterGrid.GetLightingUniformBuffer(frameIndex);

	/// Gets the light buffer for shader binding for the specified frame.
	public IBuffer GetLightBuffer(int32 frameIndex) => mClusterGrid.GetLightBuffer(frameIndex);

	/// Gets the light grid buffer for shader binding for the specified frame.
	public IBuffer GetLightGridBuffer(int32 frameIndex) => mClusterGrid.GetLightGridBuffer(frameIndex);

	/// Gets the light index buffer for shader binding for the specified frame.
	public IBuffer GetLightIndexBuffer(int32 frameIndex) => mClusterGrid.GetLightIndexBuffer(frameIndex);

	/// Gets the directional light (if any).
	public LightProxy* DirectionalLight => mDirectionalLight;

	/// Gets the number of visible lights this frame.
	public int32 VisibleLightCount => mVisibleLightCount;

	/// Gets the number of shadow-casting lights.
	public int32 ShadowCasterCount => mShadowCasterCount;

	/// Gets the number of point/spot lights (excluding directional).
	public int32 LocalLightCount => (int32)mActiveLights.Count;

	/// Creates bind group entries for lighting resources for the specified frame.
	public void GetBindGroupEntries(List<BindGroupEntry> entries, uint32 baseBinding, int32 frameIndex)
	{
		// Lighting uniforms at baseBinding
		entries.Add(.() { Binding = baseBinding, Buffer = mClusterGrid.GetLightingUniformBuffer(frameIndex) });

		// Structured buffers for lights
		entries.Add(.() { Binding = baseBinding + 1, Buffer = mClusterGrid.GetLightBuffer(frameIndex) });
		entries.Add(.() { Binding = baseBinding + 2, Buffer = mClusterGrid.GetLightGridBuffer(frameIndex) });
		entries.Add(.() { Binding = baseBinding + 3, Buffer = mClusterGrid.GetLightIndexBuffer(frameIndex) });
	}

	// ==================== Shadow Resources ====================

	/// Gets the cascaded shadow maps system.
	public CascadedShadowMaps CascadedShadows => mCascadedShadows;

	/// Gets the shadow atlas system.
	public ShadowAtlas ShadowAtlas => mShadowAtlas;

	/// Gets the shadow uniform buffer for shader binding for the specified frame.
	public IBuffer GetShadowUniformBuffer(int32 frameIndex)
	{
		if (frameIndex >= 0 && frameIndex < MAX_FRAMES_IN_FLIGHT)
			return mShadowUniformBuffers[frameIndex];
		return null;
	}

	/// Gets the shadow comparison sampler.
	public ISampler ShadowSampler => mShadowSampler;

	/// Gets the cascade shadow map array view for shader binding.
	public ITextureView CascadeShadowMapView => mCascadedShadows?.ArrayView;

	/// Gets the cascade shadow map texture for barrier transitions.
	public ITexture CascadeShadowMapTexture => mCascadedShadows?.ShadowMapArray;

	/// Gets the shadow atlas view for shader binding.
	public ITextureView ShadowAtlasView => mShadowAtlas?.AtlasView;

	/// Gets a specific cascade view for rendering to that cascade.
	public ITextureView GetCascadeRenderView(int32 cascadeIndex) => mCascadedShadows?.GetCascadeView(cascadeIndex);

	/// Gets the shadow atlas texture view for rendering.
	public ITextureView ShadowAtlasRenderView => mShadowAtlas?.AtlasView;

	/// Gets the viewport for a shadow atlas tile.
	public void GetShadowTileViewport(int32 slot, out int32 x, out int32 y, out int32 width, out int32 height)
	{
		mShadowAtlas.GetTileViewport(slot, out x, out y, out width, out height);
	}

	/// Gets cascade data for a specific cascade.
	public CascadeData GetCascadeData(int32 index) => mCascadedShadows.CascadeData[index];

	/// Gets tile data for a specific atlas slot.
	public GPUShadowTileData GetTileData(int32 slot) => mShadowAtlas.TileData[slot];

	/// Gets whether directional shadows are enabled this frame.
	public bool HasDirectionalShadows => mDirectionalLight != null && mDirectionalLight.CastsShadows;

	/// Gets the number of active shadow atlas tiles.
	public int32 ActiveShadowTileCount => mShadowAtlas.ActiveTileCount;
}

/// Cascaded shadow maps for directional light.
/// Uses 4 cascades with practical split scheme and frustum fitting.
class CascadedShadowMaps
{
	public const int32 CASCADE_COUNT = ShadowConstants.CASCADE_COUNT;
	public const int32 SHADOW_MAP_SIZE = ShadowConstants.CASCADE_MAP_SIZE;

	private IDevice mDevice;
	private ITexture mShadowMapArray ~ delete _;
	private ITextureView mArrayView ~ delete _;
	private ITextureView[CASCADE_COUNT] mCascadeViews ~ { for (let v in _) delete v; };
	private CascadeData[CASCADE_COUNT] mCascadeData;

	public this(IDevice device)
	{
		mDevice = device;
		CreateShadowMapArray();
		CreateCascadeViews();
	}

	private void CreateShadowMapArray()
	{
		TextureDescriptor desc = .()
		{
			Dimension = .Texture2D,
			Width = SHADOW_MAP_SIZE,
			Height = SHADOW_MAP_SIZE,
			Depth = 1,
			ArrayLayerCount = CASCADE_COUNT,
			MipLevelCount = 1,
			SampleCount = 1,
			Format = .Depth32Float,
			Usage = .DepthStencil | .Sampled,
			Label = "CascadedShadowMaps"
		};
		if (mDevice.CreateTexture(&desc) case .Ok(let tex))
			mShadowMapArray = tex;
	}

	private void CreateCascadeViews()
	{
		if (mShadowMapArray == null)
			return;

		// Create a view for each cascade layer (for rendering)
		for (int32 i = 0; i < CASCADE_COUNT; i++)
		{
			TextureViewDescriptor viewDesc = .()
			{
				Dimension = .Texture2D,
				Format = .Depth32Float,
				BaseMipLevel = 0,
				MipLevelCount = 1,
				BaseArrayLayer = (uint32)i,
				ArrayLayerCount = 1,
				Label = scope :: $"CascadeView{i}"
			};
			if (mDevice.CreateTextureView(mShadowMapArray, &viewDesc) case .Ok(let view))
				mCascadeViews[i] = view;
		}

		// Create array view for sampling all cascades
		TextureViewDescriptor arrayViewDesc = .()
		{
			Dimension = .Texture2DArray,
			Format = .Depth32Float,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = CASCADE_COUNT,
			Label = "CascadeShadowMapArray"
		};
		if (mDevice.CreateTextureView(mShadowMapArray, &arrayViewDesc) case .Ok(let view))
			mArrayView = view;
	}

	/// Updates cascade split distances and view-projection matrices.
	public void UpdateCascades(CameraProxy* camera, Vector3 lightDirection)
	{
		if (camera == null)
			return;

		// Calculate cascade split distances using practical split scheme
		float[CASCADE_COUNT + 1] splitDistances = .();
		CalculateSplitDistances(camera, ref splitDistances);

		// Debug.WriteLine($"[Cascade] Split distances: {splitDistances[0]}, {splitDistances[1]}, {splitDistances[2]}, {splitDistances[3]}, {splitDistances[4]}");

		// For each cascade, compute tight frustum bounds
		for (int32 i = 0; i < CASCADE_COUNT; i++)
		{
			float nearSplit = splitDistances[i];
			float farSplit = splitDistances[i + 1];

			// Get frustum corners for this cascade slice
			Vector3[8] frustumCorners = .();
			GetFrustumCornersWorldSpace(camera, nearSplit, farSplit, ref frustumCorners);

			// Calculate view-projection matrix with texel snapping
			mCascadeData[i] = ComputeCascadeMatrix(frustumCorners, lightDirection);
			mCascadeData[i].SplitDepths = .(nearSplit, farSplit, 0, 0);

			// Debug.WriteLine($"[Cascade {i}] nearSplit={nearSplit}, farSplit={farSplit}");
			// Debug.WriteLine($"[Cascade {i}] VP[0,0]={mCascadeData[i].ViewProjection.M11}, VP[3,3]={mCascadeData[i].ViewProjection.M44}");
		}
	}

	private void CalculateSplitDistances(CameraProxy* camera, ref float[CASCADE_COUNT + 1] splits)
	{
		float near = camera.NearPlane;
		float far = Math.Min(camera.FarPlane, 100.0f); // Limit shadow range for better quality
		float lambda = 0.75f; // Blend factor between log and uniform

		splits[0] = near;
		for (int32 i = 1; i <= CASCADE_COUNT; i++)
		{
			float p = (float)i / CASCADE_COUNT;
			float logSplit = near * Math.Pow(far / near, p);
			float uniformSplit = near + (far - near) * p;
			splits[i] = lambda * logSplit + (1.0f - lambda) * uniformSplit;
		}
	}

	private void GetFrustumCornersWorldSpace(CameraProxy* camera, float nearZ, float farZ, ref Vector3[8] corners)
	{
		// Build projection for this slice
		Matrix proj = Matrix.CreatePerspectiveFieldOfView(
			camera.FieldOfView, camera.AspectRatio, nearZ, farZ
		);
		// Row-vector order: View * Projection
		Matrix viewProj = camera.ViewMatrix * proj;
		Matrix invViewProj = Matrix.Invert(viewProj);

		// NDC corners (Z is 0 to 1 for this projection)
		Vector4[8] ndcCorners = .(
			.(-1, -1, 0, 1), .(1, -1, 0, 1), .(1, 1, 0, 1), .(-1, 1, 0, 1),  // Near (Z = 0)
			.(-1, -1, 1, 1), .(1, -1, 1, 1), .(1, 1, 1, 1), .(-1, 1, 1, 1)   // Far (Z = 1)
		);

		for (int32 i = 0; i < 8; i++)
		{
			Vector4 world = Vector4.Transform(ndcCorners[i], invViewProj);
			corners[i] = .(world.X / world.W, world.Y / world.W, world.Z / world.W);
		}
	}

	private CascadeData ComputeCascadeMatrix(Vector3[8] frustumCorners, Vector3 lightDir)
	{
		// TODO: Frustum-fitted bounds (USE_FIXED_BOUNDS=false) produce offset shadows.
		// The light-space bounds calculation or near/far Z logic needs investigation.
		// Fixed bounds work correctly but don't adapt to camera position/orientation.
		// For scenes with known extents, fixed bounds are a valid simplification.
		const bool USE_FIXED_BOUNDS = true;

		Vector3 center;
		float halfSize;

		if (USE_FIXED_BOUNDS)
		{
			// Fixed bounds centered on scene origin - covers a 30x30 unit area
			center = Vector3(0, 0, 0);
			halfSize = 15.0f;
		}
		else
		{
			// Find frustum center
			center = .Zero;
			for (let corner in frustumCorners)
				center = center + corner;
			center = center / 8.0f;
			halfSize = 50.0f;
		}

		// Light view matrix (looking along light direction toward scene center)
		// Compute stable up vector using orthonormal basis to avoid discontinuities
		Vector3 lightPos = center - lightDir * 50.0f;

		// Choose a reference vector that's not parallel to lightDir
		Vector3 refVec = Math.Abs(lightDir.Y) < 0.9f ? Vector3.Up : Vector3.Right;

		// Build orthonormal basis: right = refVec x lightDir, up = lightDir x right
		Vector3 lightRight = Vector3.Normalize(Vector3.Cross(refVec, lightDir));
		Vector3 lightUp = Vector3.Cross(lightDir, lightRight);

		Matrix lightView = Matrix.CreateLookAt(lightPos, center, lightUp);

		// Debug.WriteLine($"[Shadow] Light pos: {lightPos}, center: {center}, dir: {lightDir}");

		float minX, maxX, minY, maxY, nearZ, farZ;

		if (USE_FIXED_BOUNDS)
		{
			// Simple symmetric ortho bounds
			minX = -halfSize;
			maxX = halfSize;
			minY = -halfSize;
			maxY = halfSize;
			nearZ = 0.1f;
			farZ = 100.0f;
		}
		else
		{
			// Transform corners to light space and find bounds
			float minXf = float.MaxValue, maxXf = float.MinValue;
			float minYf = float.MaxValue, maxYf = float.MinValue;
			float minZf = float.MaxValue, maxZf = float.MinValue;

			for (let corner in frustumCorners)
			{
				Vector4 lightSpace = Vector4.Transform(Vector4(corner, 1.0f), lightView);
				minXf = Math.Min(minXf, lightSpace.X);
				maxXf = Math.Max(maxXf, lightSpace.X);
				minYf = Math.Min(minYf, lightSpace.Y);
				maxYf = Math.Max(maxYf, lightSpace.Y);
				minZf = Math.Min(minZf, lightSpace.Z);
				maxZf = Math.Max(maxZf, lightSpace.Z);
			}

			// Extend Z for objects behind camera
			minZf -= 50.0f;

			// Snap to texel boundaries
			float worldUnitsPerTexel = (maxXf - minXf) / SHADOW_MAP_SIZE;
			minX = Math.Floor(minXf / worldUnitsPerTexel) * worldUnitsPerTexel;
			maxX = Math.Floor(maxXf / worldUnitsPerTexel) * worldUnitsPerTexel;
			minY = Math.Floor(minYf / worldUnitsPerTexel) * worldUnitsPerTexel;
			maxY = Math.Floor(maxYf / worldUnitsPerTexel) * worldUnitsPerTexel;

			nearZ = Math.Max(-maxZf, 0.1f);
			farZ = -minZf;
		}

		// Debug.WriteLine($"[Shadow] Bounds: X=[{minX}, {maxX}], Y=[{minY}, {maxY}]");
		// Debug.WriteLine($"[Shadow] nearZ: {nearZ}, farZ: {farZ}");

		// Orthographic projection for directional light
		Matrix lightProj = Matrix.CreateOrthographicOffCenter(
			minX, maxX, minY, maxY, nearZ, farZ
		);

		return .()
		{
			// Row-vector order: View * Projection
			ViewProjection = lightView * lightProj,
			SplitDepths = .(0, 0, 0, 0)
		};
	}

	/// Gets the texture view for rendering to a specific cascade.
	public ITextureView GetCascadeView(int32 cascadeIndex) => mCascadeViews[cascadeIndex];

	/// Gets the array view for sampling all cascades.
	public ITextureView ArrayView => mArrayView;

	/// Gets the shadow map texture.
	public ITexture ShadowMapArray => mShadowMapArray;

	/// Gets cascade data for uniform upload.
	public CascadeData[CASCADE_COUNT] CascadeData => mCascadeData;

	/// Gets the split distance for a cascade (far plane of that cascade).
	public float GetSplitDistance(int32 index) => mCascadeData[index].SplitDepths.Y;
}

/// Shadow atlas for point and spot light shadows.
/// Uses a 4096x4096 texture subdivided into 512x512 tiles.
class ShadowAtlas
{
	public const int32 ATLAS_SIZE = ShadowConstants.ATLAS_SIZE;
	public const int32 TILE_SIZE = ShadowConstants.TILE_SIZE;
	public const int32 TILES_PER_ROW = ShadowConstants.TILES_PER_ROW;
	public const int32 MAX_TILES = ShadowConstants.MAX_TILES;

	private IDevice mDevice;
	private ITexture mAtlasTexture ~ delete _;
	private ITextureView mAtlasView ~ delete _;
	private GPUShadowTileData[MAX_TILES] mTileData;
	private int32 mNextFreeSlot = 0;

	// Cube map face directions for point lights
	private static Vector3[6] sCubeDirections = .(
		.(1, 0, 0), .(-1, 0, 0),   // +X, -X
		.(0, 1, 0), .(0, -1, 0),   // +Y, -Y
		.(0, 0, 1), .(0, 0, -1)    // +Z, -Z
	);

	private static Vector3[6] sCubeUps = .(
		.(0, -1, 0), .(0, -1, 0),  // +X, -X
		.(0, 0, 1), .(0, 0, -1),   // +Y, -Y
		.(0, -1, 0), .(0, -1, 0)   // +Z, -Z
	);

	public this(IDevice device)
	{
		mDevice = device;
		CreateAtlasTexture();
		CreateAtlasView();
	}

	private void CreateAtlasTexture()
	{
		TextureDescriptor desc = .()
		{
			Dimension = .Texture2D,
			Width = ATLAS_SIZE,
			Height = ATLAS_SIZE,
			Depth = 1,
			ArrayLayerCount = 1,
			MipLevelCount = 1,
			SampleCount = 1,
			Format = .Depth32Float,
			Usage = .DepthStencil | .Sampled,
			Label = "ShadowAtlas"
		};
		if (mDevice.CreateTexture(&desc) case .Ok(let tex))
			mAtlasTexture = tex;
	}

	private void CreateAtlasView()
	{
		if (mAtlasTexture == null)
			return;

		TextureViewDescriptor viewDesc = .()
		{
			Dimension = .Texture2D,
			Format = .Depth32Float,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1,
			Label = "ShadowAtlasView"
		};
		if (mDevice.CreateTextureView(mAtlasTexture, &viewDesc) case .Ok(let view))
			mAtlasView = view;
	}

	/// Allocates a tile for a light and computes its view-projection matrix.
	public int32 AllocateTile(LightProxy* light, int32 faceIndex = 0)
	{
		if (mNextFreeSlot >= MAX_TILES)
			return -1;

		int32 slot = mNextFreeSlot++;
		int32 tileX = slot % TILES_PER_ROW;
		int32 tileY = slot / TILES_PER_ROW;

		// Compute UV offset/scale for shader
		float uvScale = 1.0f / TILES_PER_ROW;

		mTileData[slot] = .()
		{
			ViewProjection = ComputeLightViewProjection(light, faceIndex),
			UVOffsetScale = .(
				(float)tileX * uvScale,
				(float)tileY * uvScale,
				uvScale,
				uvScale
			),
			LightIndex = (int32)light.Id,
			FaceIndex = faceIndex,
			_pad0 = 0,
			_pad1 = 0
		};

		return slot;
	}

	private Matrix ComputeLightViewProjection(LightProxy* light, int32 faceIndex)
	{
		if (light.Type == .Spot)
		{
			// Spot light perspective projection
			Matrix view = Matrix.CreateLookAt(
				light.Position,
				light.Position + light.Direction,
				Vector3.Up
			);
			Matrix proj = Matrix.CreatePerspectiveFieldOfView(
				light.OuterConeAngle * 2.0f,  // Full cone angle
				1.0f,  // Aspect ratio 1:1 for square tiles
				0.1f,
				light.Range
			);
			// Row-vector order: View * Projection
			return view * proj;
		}
		else if (light.Type == .Point)
		{
			// Point light - 6 faces (cube map style)
			Vector3 direction = sCubeDirections[faceIndex];
			Vector3 up = sCubeUps[faceIndex];

			Matrix view = Matrix.CreateLookAt(
				light.Position,
				light.Position + direction,
				up
			);
			Matrix proj = Matrix.CreatePerspectiveFieldOfView(
				Math.PI_f / 2.0f,  // 90 degree FOV
				1.0f,
				0.1f,
				light.Range
			);
			// Row-vector order: View * Projection
			return view * proj;
		}

		return .Identity;
	}

	/// Gets the viewport rectangle for a tile slot.
	public void GetTileViewport(int32 slot, out int32 x, out int32 y, out int32 width, out int32 height)
	{
		int32 tileX = slot % TILES_PER_ROW;
		int32 tileY = slot / TILES_PER_ROW;
		x = tileX * TILE_SIZE;
		y = tileY * TILE_SIZE;
		width = TILE_SIZE;
		height = TILE_SIZE;
	}

	/// Resets the atlas for a new frame.
	public void Reset()
	{
		mNextFreeSlot = 0;
	}

	/// Gets the atlas texture.
	public ITexture AtlasTexture => mAtlasTexture;

	/// Gets the atlas view for sampling.
	public ITextureView AtlasView => mAtlasView;

	/// Gets tile data for uniform upload.
	public GPUShadowTileData[MAX_TILES] TileData => mTileData;

	/// Gets the number of allocated tiles this frame.
	public int32 ActiveTileCount => mNextFreeSlot;
}
