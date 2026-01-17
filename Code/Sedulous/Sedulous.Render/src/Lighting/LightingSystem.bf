namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Manages clustered lighting infrastructure.
/// Coordinates cluster grid building and light culling.
public class LightingSystem : IDisposable
{
	// Subsystems
	private ClusterGrid mClusterGrid ~ delete _;
	private LightBuffer mLightBuffer ~ delete _;

	// Configuration
	private IDevice mDevice;
	private bool mUseClustered = true;

	// Current view state
	private uint32 mScreenWidth;
	private uint32 mScreenHeight;
	private float mNearPlane;
	private float mFarPlane;
	private Matrix mInverseProjection;

	/// Gets the cluster grid.
	public ClusterGrid ClusterGrid => mClusterGrid;

	/// Gets the light buffer.
	public LightBuffer LightBuffer => mLightBuffer;

	/// Gets or sets whether clustered lighting is enabled.
	public bool UseClusteredLighting
	{
		get => mUseClustered;
		set => mUseClustered = value;
	}

	/// Whether the system is initialized.
	public bool IsInitialized => mDevice != null && mClusterGrid != null && mLightBuffer != null;

	/// Initializes the lighting system.
	public Result<void> Initialize(IDevice device, ClusterGridConfig clusterConfig = .Default)
	{
		mDevice = device;

		// Initialize cluster grid
		mClusterGrid = new ClusterGrid();
		if (mClusterGrid.Initialize(device, clusterConfig) case .Err)
			return .Err;

		// Initialize light buffer
		mLightBuffer = new LightBuffer();
		if (mLightBuffer.Initialize(device) case .Err)
			return .Err;

		return .Ok;
	}

	/// Updates the lighting system for the current frame.
	public void Update(
		RenderWorld world,
		VisibilityResolver visibility,
		CameraProxy* camera,
		uint32 screenWidth,
		uint32 screenHeight)
	{
		if (!IsInitialized || camera == null)
			return;

		// Check if view parameters changed
		bool viewChanged = mScreenWidth != screenWidth ||
						   mScreenHeight != screenHeight ||
						   mNearPlane != camera.NearPlane ||
						   mFarPlane != camera.FarPlane;

		mScreenWidth = screenWidth;
		mScreenHeight = screenHeight;
		mNearPlane = camera.NearPlane;
		mFarPlane = camera.FarPlane;
		mInverseProjection = camera.InverseProjectionMatrix;

		// Update cluster grid if view changed
		if (viewChanged && mUseClustered)
		{
			mClusterGrid.Update(screenWidth, screenHeight, mNearPlane, mFarPlane, mInverseProjection);
		}

		// Update light buffer from visible lights
		mLightBuffer.Update(world, visibility);

		// Perform light culling against clusters
		if (mUseClustered)
		{
			mClusterGrid.CullLightsCPU(world, visibility);
		}
	}

	/// Updates lighting for rendering (GPU operations).
	public void PrepareForRendering(ICommandEncoder encoder)
	{
		if (!IsInitialized)
			return;

		// GPU light culling would be dispatched here
		// For now, we use the CPU fallback in Update()
	}

	/// Sets the ambient light color.
	public void SetAmbientColor(Vector3 color)
	{
		if (mLightBuffer != null)
			mLightBuffer.AmbientColor = color;
	}

	/// Sets the environment map intensity.
	public void SetEnvironmentIntensity(float intensity)
	{
		if (mLightBuffer != null)
			mLightBuffer.EnvironmentIntensity = intensity;
	}

	/// Sets the exposure value.
	public void SetExposure(float exposure)
	{
		if (mLightBuffer != null)
			mLightBuffer.Exposure = exposure;
	}

	/// Gets combined lighting statistics.
	public LightingStats GetStats()
	{
		return .()
		{
			ActiveLights = mLightBuffer?.LightCount ?? 0,
			MaxLights = mLightBuffer?.MaxLights ?? 0,
			ClusterStats = mClusterGrid?.Stats ?? .(),
			UsesClustered = mUseClustered
		};
	}

	public void Dispose()
	{
		// Destructor handles deletion
	}
}

/// Combined statistics for the lighting system.
public struct LightingStats
{
	/// Number of active lights.
	public int32 ActiveLights;

	/// Maximum supported lights.
	public int32 MaxLights;

	/// Cluster grid statistics.
	public ClusterStats ClusterStats;

	/// Whether clustered lighting is enabled.
	public bool UsesClustered;
}
