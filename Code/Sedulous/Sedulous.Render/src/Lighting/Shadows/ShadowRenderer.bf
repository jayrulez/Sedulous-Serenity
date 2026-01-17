namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Manages all shadow rendering operations.
public class ShadowRenderer : IDisposable
{
	// Subsystems
	private CascadedShadowMaps mCascadedShadows ~ delete _;
	private ShadowAtlas mShadowAtlas ~ delete _;

	// Configuration
	private IDevice mDevice;
	private bool mEnableShadows = true;

	// Current state
	private LightProxyHandle mMainDirectionalLight = .Invalid;

	/// Gets the cascaded shadow maps.
	public CascadedShadowMaps CascadedShadows => mCascadedShadows;

	/// Gets the shadow atlas.
	public ShadowAtlas ShadowAtlas => mShadowAtlas;

	/// Gets or sets whether shadows are enabled.
	public bool EnableShadows
	{
		get => mEnableShadows;
		set => mEnableShadows = value;
	}

	/// Whether the shadow renderer is initialized.
	public bool IsInitialized => mDevice != null && mCascadedShadows != null && mShadowAtlas != null;

	/// Initializes the shadow renderer.
	public Result<void> Initialize(IDevice device, CascadeConfig cascadeConfig = .Default, ShadowAtlasConfig atlasConfig = .Default)
	{
		mDevice = device;

		// Initialize cascaded shadow maps
		mCascadedShadows = new CascadedShadowMaps();
		if (mCascadedShadows.Initialize(device, cascadeConfig) case .Err)
			return .Err;

		// Initialize shadow atlas
		mShadowAtlas = new ShadowAtlas();
		if (mShadowAtlas.Initialize(device, atlasConfig) case .Err)
			return .Err;

		return .Ok;
	}

	/// Updates shadow maps for the current frame.
	public void Update(RenderWorld world, VisibilityResolver visibility, CameraProxy* camera)
	{
		if (!IsInitialized || !mEnableShadows || camera == null)
			return;

		// Find main directional light for CSM
		UpdateMainDirectionalLight(world, visibility);

		// Update CSM matrices
		if (mMainDirectionalLight.IsValid)
		{
			if (let light = world.GetLight(mMainDirectionalLight))
			{
				mCascadedShadows.Update(camera, light.Direction);
			}
		}

		// Update shadow atlas for point/spot lights
		UpdateAtlasShadows(world, visibility);
	}

	/// Gets shadow render passes that need to be executed.
	public void GetShadowPasses(List<ShadowPass> outPasses)
	{
		outPasses.Clear();

		if (!mEnableShadows)
			return;

		// Add CSM passes
		if (mMainDirectionalLight.IsValid)
		{
			for (int i = 0; i < mCascadedShadows.Config.CascadeCount; i++)
			{
				outPasses.Add(.()
				{
					Type = .Cascade,
					CascadeIndex = (uint8)i,
					ViewProjection = mCascadedShadows.GetCascadeViewProjection(i),
					RenderTarget = mCascadedShadows.GetCascadeView(i),
					Viewport = .(0, 0, (.)mCascadedShadows.Config.Resolution, (.)mCascadedShadows.Config.Resolution)
				});
			}
		}

		// Add atlas passes for spot/point lights
		for (uint32 i = 0; i < mShadowAtlas.Config.TotalTiles; i++)
		{
			if (let tile = mShadowAtlas.GetTileByIndex((int32)i))
			{
				if (!tile.IsAllocated)
					continue;

				// Determine pass type based on whether this is a point light face
				ShadowPassType passType = tile.CubeFace > 0 ? .PointLightFace : .AtlasTile;

				outPasses.Add(.()
				{
					Type = passType,
					CascadeIndex = 0,
					CubeFace = tile.CubeFace,
					ViewProjection = tile.ViewProjection,
					RenderTarget = mShadowAtlas.AtlasView,
					Viewport = .((.)tile.ViewportX, (.)tile.ViewportY, (.)tile.ViewportSize, (.)tile.ViewportSize)
				});
			}
		}
	}

	/// Assigns a shadow index to a light.
	public int32 AssignShadowIndex(LightProxyHandle lightHandle, LightType lightType)
	{
		if (!mEnableShadows)
			return -1;

		switch (lightType)
		{
		case .Directional:
			// CSM uses a fixed index
			mMainDirectionalLight = lightHandle;
			return 0;

		case .Spot:
			if (mShadowAtlas.AllocateSpotLightTile(lightHandle) case .Ok(let tile))
				return tile.Index;
			return -1;

		case .Point:
			// Point lights need 6 tiles
			ShadowTile*[6] tiles = .();
			if (mShadowAtlas.AllocatePointLightTiles(lightHandle, ref tiles) case .Ok)
				return tiles[0].Index;
			return -1;

		default:
			return -1;
		}
	}

	/// Releases a shadow assignment.
	public void ReleaseShadow(LightProxyHandle lightHandle)
	{
		if (mMainDirectionalLight == lightHandle)
			mMainDirectionalLight = .Invalid;
		else
			mShadowAtlas.ReleaseTile(lightHandle);
	}

	public void Dispose()
	{
		// Destructors handle cleanup
	}

	private void UpdateMainDirectionalLight(RenderWorld world, VisibilityResolver visibility)
	{
		// Find first enabled directional light that casts shadows
		for (let visibleLight in visibility.VisibleLights)
		{
			if (let light = world.GetLight(visibleLight.Handle))
			{
				if (light.Type == .Directional && light.CastsShadows)
				{
					mMainDirectionalLight = visibleLight.Handle;
					return;
				}
			}
		}

		mMainDirectionalLight = .Invalid;
	}

	private void UpdateAtlasShadows(RenderWorld world, VisibilityResolver visibility)
	{
		// Update shadow matrices for spot/point lights with assigned shadows
		for (let visibleLight in visibility.VisibleLights)
		{
			if (let light = world.GetLight(visibleLight.Handle))
			{
				if (!light.CastsShadows || light.Type == .Directional)
					continue;

				if (light.Type == .Spot)
				{
					mShadowAtlas.UpdateSpotLightShadow(visibleLight.Handle, light);
				}
				else if (light.Type == .Point)
				{
					// Get all 6 tiles for this point light
					ShadowTile*[6] tiles = .();
					if (GetPointLightTiles(visibleLight.Handle, ref tiles))
					{
						mShadowAtlas.UpdatePointLightShadow(visibleLight.Handle, light, tiles);
					}
				}
			}
		}

		mShadowAtlas.UploadShadowData();
	}

	/// Gets the 6 cubemap tiles for a point light.
	private bool GetPointLightTiles(LightProxyHandle lightHandle, ref ShadowTile*[6] outTiles)
	{
		if (let firstTile = mShadowAtlas.GetTile(lightHandle))
		{
			// Find all 6 faces starting from the first tile
			int32 startIndex = firstTile.Index;

			for (int face = 0; face < 6; face++)
			{
				if (let tile = mShadowAtlas.GetTileByIndex(startIndex + (.)face))
				{
					if (tile.LightHandle == lightHandle)
						outTiles[face] = tile;
					else
						return false; // Not all tiles belong to this light
				}
				else
				{
					return false;
				}
			}
			return true;
		}
		return false;
	}

	/// Gets shadow data for binding to shaders.
	public ShadowShaderData GetShadowShaderData()
	{
		return .()
		{
			CascadedShadowMapView = mCascadedShadows?.ShadowMapArrayView,
			CascadedShadowSampler = mCascadedShadows?.ShadowSampler,
			CascadedShadowUniforms = mCascadedShadows?.UniformBuffer,
			ShadowAtlasView = mShadowAtlas?.AtlasView,
			ShadowAtlasSampler = mShadowAtlas?.ShadowSampler,
			ShadowAtlasData = mShadowAtlas?.ShadowDataBuffer,
			PointLightCubemapView = mShadowAtlas?.PointLightCubemapArrayView
		};
	}
}

/// Shadow resources for shader binding.
public struct ShadowShaderData
{
	/// Cascaded shadow map array view.
	public ITextureView CascadedShadowMapView;

	/// Shadow comparison sampler.
	public ISampler CascadedShadowSampler;

	/// Cascade uniform buffer.
	public IBuffer CascadedShadowUniforms;

	/// Shadow atlas texture view.
	public ITextureView ShadowAtlasView;

	/// Shadow atlas sampler.
	public ISampler ShadowAtlasSampler;

	/// Shadow atlas data buffer.
	public IBuffer ShadowAtlasData;

	/// Point light cubemap array view.
	public ITextureView PointLightCubemapView;
}

/// Type of shadow pass.
public enum ShadowPassType
{
	/// Cascaded shadow map pass.
	Cascade,
	/// Shadow atlas tile pass.
	AtlasTile,
	/// Point light cubemap face pass.
	PointLightFace
}

/// Describes a shadow rendering pass.
public struct ShadowPass
{
	/// Type of shadow pass.
	public ShadowPassType Type;

	/// Cascade index (for CSM).
	public uint8 CascadeIndex;

	/// Cubemap face index (for point lights).
	public uint8 CubeFace;

	/// View-projection matrix for this pass.
	public Matrix ViewProjection;

	/// Render target view.
	public ITextureView RenderTarget;

	/// Viewport for rendering.
	public Rect Viewport;
}

/// Rectangle for viewport specification.
public struct Rect
{
	public int32 X;
	public int32 Y;
	public int32 Width;
	public int32 Height;

	public this(int32 x, int32 y, int32 width, int32 height)
	{
		X = x;
		Y = y;
		Width = width;
		Height = height;
	}
}
