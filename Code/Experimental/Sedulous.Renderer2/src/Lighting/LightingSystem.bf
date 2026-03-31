namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Profiler;

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
	public Result<void> Initialize(IDevice device, ClusterGridConfig clusterConfig = .Default, ShaderSystem shaderSystem = null)
	{
		using (SProfiler.Begin("Renderer.LightingSystem.Init"))
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
	}

	/// Updates the lighting system for the current frame.
	/// @param frameIndex The frame index for multi-buffering.
	public void Update(
		RenderWorld world,
		VisibilityResolver visibility,
		ViewContext viewCtx,
		int32 frameIndex,
		int32 viewIndex = 0)
	{
		if (!IsInitialized)
			return;

		// Update light buffer from visible lights (CPU-side fill only)
		mLightBuffer.Update(world, visibility);
		// Upload light data to GPU for specified frame
		mLightBuffer.UploadLightData(frameIndex);

		// Update cluster grid from view context
		let screenWidth = viewCtx.RenderWidth;
		let screenHeight = viewCtx.RenderHeight;

		bool viewChanged = mScreenWidth != screenWidth ||
						   mScreenHeight != screenHeight ||
						   mNearPlane != viewCtx.NearPlane ||
						   mFarPlane != viewCtx.FarPlane;

		mScreenWidth = screenWidth;
		mScreenHeight = screenHeight;
		mNearPlane = viewCtx.NearPlane;
		mFarPlane = viewCtx.FarPlane;
		Matrix.TryInvert(viewCtx.ProjectionMatrix, out mInverseProjection);

		// Update cluster grid if view changed
		if (viewChanged && mUseClustered)
		{
			mClusterGrid.Update(screenWidth, screenHeight, mNearPlane, mFarPlane, mInverseProjection);
		}

		// Sync cluster grid parameters to lighting uniforms (must happen before UploadUniforms)
		if (mUseClustered)
		{
			let config = mClusterGrid.Config;
			let clusterScaleX = (float)config.ClustersX / (float)screenWidth;
			let clusterScaleY = (float)config.ClustersY / (float)screenHeight;
			let logDepthScale = (float)config.ClustersZ / Math.Log(mFarPlane / mNearPlane);
			let logDepthBias = -(float)config.ClustersZ * Math.Log(mNearPlane) / Math.Log(mFarPlane / mNearPlane);

			mLightBuffer.SetClusterInfo(
				config.ClustersX, config.ClustersY, config.ClustersZ,
				.(clusterScaleX, clusterScaleY),
				.(logDepthScale, logDepthBias));
		}

		// Upload lighting uniforms (includes cluster info) AFTER cluster params are set
		mLightBuffer.UploadUniforms(frameIndex);

		// Perform light culling against clusters
		if (mUseClustered)
		{
			mClusterGrid.CullLightsCPU(world, visibility, viewCtx.ViewMatrix, frameIndex, viewIndex);
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
		let computePass = encoder.BeginComputePass("Light Clustering");
		if (computePass != null)
		{
			// Build cluster AABBs on GPU (only if view changed - handled internally)
			mClusterGrid.BuildClustersGPU(computePass);

			// Cull lights against clusters
			mClusterGrid.CullLights(computePass, mLightBuffer, frameIndex);

			computePass.End();
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
