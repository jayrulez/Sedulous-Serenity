namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shaders;

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
	public Result<void> Initialize(IDevice device, ClusterGridConfig clusterConfig = .Default, NewShaderSystem shaderSystem = null)
	{
		mDevice = device;

		// Initialize cluster grid
		mClusterGrid = new ClusterGrid();
		if (mClusterGrid.Initialize(device, clusterConfig, shaderSystem) case .Err)
			return .Err;

		// Initialize light buffer
		mLightBuffer = new LightBuffer();
		if (mLightBuffer.Initialize(device) case .Err)
			return .Err;

		return .Ok;
	}

	/// Updates the lighting system for the current frame.
	/// @param frameIndex The frame index for multi-buffering.
	public void Update(
		RenderWorld world,
		VisibilityResolver visibility,
		CameraProxy* camera,
		uint32 screenWidth,
		uint32 screenHeight,
		int32 frameIndex)
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

		// Update light buffer from visible lights (CPU-side fill only)
		mLightBuffer.Update(world, visibility);
		// Upload to GPU for specified frame
		mLightBuffer.UploadLightData(frameIndex);
		mLightBuffer.UploadUniforms(frameIndex);

		// Perform light culling against clusters
		if (mUseClustered)
		{
			mClusterGrid.CullLightsCPU(world, visibility, camera.ViewMatrix, frameIndex);
		}
	}

	/// Updates lighting for rendering (GPU operations).
	/// This dispatches GPU compute for cluster building and light culling.
	/// @param frameIndex The frame index for multi-buffering.
	public void PrepareForRendering(ICommandEncoder encoder, int32 frameIndex)
	{
		if (!IsInitialized)
			return;

		// Skip GPU culling if not available
		if (!mClusterGrid.GPUCullingAvailable || !mUseClustered)
			return;

		// Ensure bind groups are created
		mClusterGrid.CreateBindGroups(mLightBuffer);

		// Begin compute pass for GPU light culling
		let computePass = encoder.BeginComputePass();
		if (computePass != null)
		{
			// Build cluster AABBs on GPU (only if view changed - handled internally)
			mClusterGrid.BuildClustersGPU(computePass);

			// Cull lights against clusters
			mClusterGrid.CullLights(computePass, mLightBuffer, frameIndex);

			computePass.End();
			delete computePass;
		}
	}

	/// Performs GPU light culling in an existing compute pass.
	/// @param frameIndex The frame index for multi-buffering.
	public void DispatchLightCulling(IComputePassEncoder encoder, int32 frameIndex)
	{
		if (!IsInitialized || !mUseClustered)
			return;

		if (!mClusterGrid.GPUCullingAvailable)
		{
			// Fall back to CPU culling (already done in Update)
			return;
		}

		// Ensure bind groups are created
		mClusterGrid.CreateBindGroups(mLightBuffer);

		// Cull lights against clusters
		mClusterGrid.CullLights(encoder, mLightBuffer, frameIndex);
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
