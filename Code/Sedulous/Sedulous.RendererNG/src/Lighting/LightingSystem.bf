namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Main facade for the lighting system.
/// Manages cluster grid, light buffer, and shadows.
class LightingSystem : IDisposable
{
	private IDevice mDevice;

	// Sub-systems
	private ClusterGrid mClusterGrid ~ delete _;
	private LightBuffer mLightBuffer ~ delete _;

	// Cached view data
	private Matrix mViewMatrix;
	private Matrix mProjectionMatrix;
	private float mNearPlane;
	private float mFarPlane;
	private uint32 mScreenWidth;
	private uint32 mScreenHeight;
	private bool mClustersDirty = true;

	/// Creates a new lighting system.
	public this(uint32 clusterX = 16, uint32 clusterY = 9, uint32 clusterZ = 24)
	{
		mClusterGrid = new ClusterGrid(clusterX, clusterY, clusterZ);
		mLightBuffer = new LightBuffer();
	}

	/// Initializes the lighting system.
	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		if (mClusterGrid.Initialize(device) case .Err)
			return .Err;

		if (mLightBuffer.Initialize(device) case .Err)
			return .Err;

		return .Ok;
	}

	/// Sets the view parameters for cluster computation.
	public void SetView(Matrix view, Matrix projection, float nearPlane, float farPlane,
						uint32 screenWidth, uint32 screenHeight)
	{
		// Check if view changed
		if (mViewMatrix != view || mProjectionMatrix != projection ||
			mNearPlane != nearPlane || mFarPlane != farPlane ||
			mScreenWidth != screenWidth || mScreenHeight != screenHeight)
		{
			mViewMatrix = view;
			mProjectionMatrix = projection;
			mNearPlane = nearPlane;
			mFarPlane = farPlane;
			mScreenWidth = screenWidth;
			mScreenHeight = screenHeight;
			mClustersDirty = true;
		}
	}

	/// Begins a new frame. Clears lights for re-population.
	public void BeginFrame()
	{
		mLightBuffer.Clear();
	}

	/// Adds a directional light.
	public void AddDirectionalLight(Vector3 direction, Vector3 color, float intensity)
	{
		mLightBuffer.AddDirectionalLight(direction, color, intensity);
	}

	/// Adds a point light.
	public void AddPointLight(Vector3 position, float range, Vector3 color, float intensity)
	{
		mLightBuffer.AddPointLight(position, range, color, intensity);
	}

	/// Adds a spot light.
	public void AddSpotLight(Vector3 position, Vector3 direction, float range,
							 float innerAngleDeg, float outerAngleDeg, Vector3 color, float intensity)
	{
		float innerRad = innerAngleDeg * (Math.PI_f / 180.0f);
		float outerRad = outerAngleDeg * (Math.PI_f / 180.0f);
		mLightBuffer.AddSpotLight(position, direction, range, innerRad, outerRad, color, intensity);
	}

	/// Adds lights from the render world's light proxies.
	public void AddLightsFromWorld(RenderWorld world)
	{
		world.ForEachLight(scope [&](handle, proxy) =>
		{
			if (!proxy.IsEnabled)
				return;

			switch (proxy.Type)
			{
			case .Directional:
				AddDirectionalLight(proxy.Direction, proxy.Color, proxy.Intensity);
			case .Point:
				AddPointLight(proxy.Position, proxy.Range, proxy.Color, proxy.Intensity);
			case .Spot:
				// Convert radians to degrees for AddSpotLight
				float innerDeg = proxy.InnerConeAngle * (180.0f / Math.PI_f);
				float outerDeg = proxy.OuterConeAngle * (180.0f / Math.PI_f);
				AddSpotLight(proxy.Position, proxy.Direction, proxy.Range,
					innerDeg, outerDeg, proxy.Color, proxy.Intensity);
			}
		});
	}

	/// Sets ambient lighting.
	public void SetAmbient(Vector3 color, float intensity)
	{
		mLightBuffer.SetAmbient(color, intensity);
	}

	/// Sets sun (main directional) light parameters.
	public void SetSun(Vector3 direction, Vector3 color, float intensity)
	{
		mLightBuffer.SetSun(direction, color, intensity);
	}

	/// Updates lighting data and uploads to GPU.
	/// Call after all lights have been added.
	public void Update()
	{
		// Recompute clusters if view changed
		if (mClustersDirty && mScreenWidth > 0 && mScreenHeight > 0)
		{
			mClusterGrid.ComputeClusterBounds(mProjectionMatrix, mNearPlane, mFarPlane,
				mScreenWidth, mScreenHeight);
			mClustersDirty = false;
		}

		// Upload light data
		mLightBuffer.Upload();

		// Assign lights to clusters
		mClusterGrid.AssignLights(mLightBuffer.Lights, mViewMatrix);
	}

	/// Gets the cluster grid.
	public ClusterGrid ClusterGrid => mClusterGrid;

	/// Gets the light buffer.
	public LightBuffer LightBuffer => mLightBuffer;

	/// Gets statistics.
	public void GetStats(String outStats)
	{
		mClusterGrid.GetStats(outStats);
		mLightBuffer.GetStats(outStats);
	}

	public void Dispose()
	{
		// Sub-systems cleaned up by destructor
	}
}
