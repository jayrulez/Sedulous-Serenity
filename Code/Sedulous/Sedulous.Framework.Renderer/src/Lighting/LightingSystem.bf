namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Manages the clustered lighting system.
/// Orchestrates cluster grid, light culling, and shadow rendering.
class LightingSystem
{
	private IDevice mDevice;
	private ClusterGrid mClusterGrid ~ delete _;

	// Shadow rendering (will be expanded in later phases)
	private CascadedShadowMaps mCascadedShadows ~ delete _;
	private ShadowAtlas mShadowAtlas ~ delete _;

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
	}

	/// Updates the lighting system for a new frame.
	public void Update(CameraProxy* camera, List<LightProxy*> lights)
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

		// Cull lights to clusters
		mClusterGrid.CullLights(mActiveLights, camera);

		// Update uniform buffer with directional light info
		mClusterGrid.UpdateUniforms(camera, mDirectionalLight);

		// Update stats
		mVisibleLightCount = (int32)mActiveLights.Count;
		if (mDirectionalLight != null)
			mVisibleLightCount++;
	}

	/// Updates shadow maps for shadow-casting lights.
	public void UpdateShadows(CameraProxy* camera, List<MeshProxy*> shadowCasters)
	{
		mShadowCasterCount = 0;

		// Cascaded shadow maps for directional light
		if (mDirectionalLight != null && mDirectionalLight.CastsShadows)
		{
			// TODO: Render cascaded shadow maps
			mShadowCasterCount++;
		}

		// Shadow atlas for point/spot lights
		for (let light in mActiveLights)
		{
			if (light.CastsShadows)
			{
				// TODO: Render shadow atlas tile
				mShadowCasterCount++;
			}
		}
	}

	/// Gets the cluster grid for shader binding.
	public ClusterGrid ClusterGrid => mClusterGrid;

	/// Gets the lighting uniform buffer for shader binding.
	public IBuffer LightingUniformBuffer => mClusterGrid.LightingUniformBuffer;

	/// Gets the light buffer for shader binding.
	public IBuffer LightBuffer => mClusterGrid.LightBuffer;

	/// Gets the light grid buffer for shader binding.
	public IBuffer LightGridBuffer => mClusterGrid.LightGridBuffer;

	/// Gets the light index buffer for shader binding.
	public IBuffer LightIndexBuffer => mClusterGrid.LightIndexBuffer;

	/// Gets the directional light (if any).
	public LightProxy* DirectionalLight => mDirectionalLight;

	/// Gets the number of visible lights this frame.
	public int32 VisibleLightCount => mVisibleLightCount;

	/// Gets the number of shadow-casting lights.
	public int32 ShadowCasterCount => mShadowCasterCount;

	/// Gets the number of point/spot lights (excluding directional).
	public int32 LocalLightCount => (int32)mActiveLights.Count;

	/// Creates bind group entries for lighting resources.
	public void GetBindGroupEntries(List<BindGroupEntry> entries, uint32 baseBinding)
	{
		// Lighting uniforms at baseBinding
		entries.Add(.() { Binding = baseBinding, Buffer = mClusterGrid.LightingUniformBuffer });

		// Structured buffers for lights
		entries.Add(.() { Binding = baseBinding + 1, Buffer = mClusterGrid.LightBuffer });
		entries.Add(.() { Binding = baseBinding + 2, Buffer = mClusterGrid.LightGridBuffer });
		entries.Add(.() { Binding = baseBinding + 3, Buffer = mClusterGrid.LightIndexBuffer });
	}
}

/// Placeholder for cascaded shadow maps (Phase 5 shadows).
class CascadedShadowMaps
{
	public const int32 CASCADE_COUNT = 4;
	public const int32 SHADOW_MAP_SIZE = 2048;

	private IDevice mDevice;
	private ITexture mShadowMapArray ~ delete _;
	private ITextureView mDepthViews ~ delete _;
	private Matrix4x4[CASCADE_COUNT] mLightViewProjections;
	private float[CASCADE_COUNT] mSplitDistances;

	public this(IDevice device)
	{
		mDevice = device;
		CreateShadowMapArray();
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

	/// Updates cascade split distances and view-projection matrices.
	public void UpdateCascades(CameraProxy* camera, Vector3 lightDirection)
	{
		if (camera == null)
			return;

		// Calculate cascade split distances using practical split scheme
		float near = camera.NearPlane;
		float far = camera.FarPlane;
		float lambda = 0.75f; // Blend factor between log and uniform

		for (int i = 0; i < CASCADE_COUNT; i++)
		{
			float p = (float)(i + 1) / CASCADE_COUNT;
			float logSplit = near * Math.Pow(far / near, p);
			float uniformSplit = near + (far - near) * p;
			mSplitDistances[i] = lambda * logSplit + (1.0f - lambda) * uniformSplit;
		}

		// Calculate light view-projection for each cascade
		// TODO: Proper cascade frustum fitting
	}

	public ITexture ShadowMapArray => mShadowMapArray;
	public float[CASCADE_COUNT] SplitDistances => mSplitDistances;
	public Matrix4x4[CASCADE_COUNT] LightViewProjections => mLightViewProjections;
}

/// Placeholder for shadow atlas (Phase 5 shadows).
class ShadowAtlas
{
	public const int32 ATLAS_SIZE = 4096;
	public const int32 TILE_SIZE = 512;
	public const int32 TILES_PER_ROW = ATLAS_SIZE / TILE_SIZE;
	public const int32 MAX_TILES = TILES_PER_ROW * TILES_PER_ROW;

	private IDevice mDevice;
	private ITexture mAtlasTexture ~ delete _;
	private ShadowAtlasSlot[MAX_TILES] mSlots;
	private int32 mNextFreeSlot = 0;

	public this(IDevice device)
	{
		mDevice = device;
		CreateAtlasTexture();
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

	/// Allocates a tile for a light.
	public int32 AllocateTile(int32 lightIndex, int32 faceIndex = 0)
	{
		if (mNextFreeSlot >= MAX_TILES)
			return -1;

		int32 slot = mNextFreeSlot++;

		int32 tileX = slot % TILES_PER_ROW;
		int32 tileY = slot / TILES_PER_ROW;

		mSlots[slot] = .()
		{
			UVOffsetSize = .(
				(float)tileX / TILES_PER_ROW,
				(float)tileY / TILES_PER_ROW,
				1.0f / TILES_PER_ROW,
				1.0f / TILES_PER_ROW
			),
			LightIndex = lightIndex,
			FaceIndex = faceIndex,
			_pad0 = 0,
			_pad1 = 0
		};

		return slot;
	}

	/// Resets the atlas for a new frame.
	public void Reset()
	{
		mNextFreeSlot = 0;
	}

	public ITexture AtlasTexture => mAtlasTexture;
}
