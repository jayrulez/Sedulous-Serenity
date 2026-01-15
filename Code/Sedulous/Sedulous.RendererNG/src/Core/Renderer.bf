namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;

/// Main entry point for the RendererNG system.
/// Owns all rendering subsystems and orchestrates frame rendering.
class Renderer : IDisposable
{
	private IDevice mDevice;
	private bool mInitialized = false;

	// Core systems (to be implemented)
	// private ResourcePool mResourcePool;
	// private ShaderSystem mShaderSystem;
	// private MaterialRegistry mMaterialRegistry;
	// private PipelineFactory mPipelineFactory;
	// private RenderGraph mRenderGraph;

	// Draw systems (to be implemented)
	// private MeshDrawSystem mMeshDrawSystem;
	// private ParticleDrawSystem mParticleDrawSystem;
	// private SpriteDrawSystem mSpriteDrawSystem;
	// private SkyboxDrawSystem mSkyboxDrawSystem;
	// private ShadowDrawSystem mShadowDrawSystem;

	// Statistics
	private RenderStats mStats;
	private RenderStatsAccumulator mStatsAccumulator = new .() ~ delete _;

	/// Gets the graphics device.
	public IDevice Device => mDevice;

	/// Gets whether the renderer has been initialized.
	public bool IsInitialized => mInitialized;

	/// Gets the current frame statistics.
	public ref RenderStats Stats => ref mStats;

	/// Gets the statistics accumulator.
	public RenderStatsAccumulator StatsAccumulator => mStatsAccumulator;

	/// Initializes the renderer with a graphics device.
	/// @param device The RHI device to use for rendering.
	/// @param shaderBasePath Base path for shader files.
	/// @returns Success or error.
	public Result<void> Initialize(IDevice device, StringView shaderBasePath = "shaders")
	{
		if (device == null)
			return .Err;

		if (mInitialized)
			return .Err; // Already initialized

		mDevice = device;

		// TODO: Initialize subsystems
		// mResourcePool = new ResourcePool(device);
		// mShaderSystem = new ShaderSystem(device, shaderBasePath);
		// mMaterialRegistry = new MaterialRegistry();
		// mPipelineFactory = new PipelineFactory(device, mShaderSystem);
		// mRenderGraph = new RenderGraph(device);

		// TODO: Initialize draw systems
		// mMeshDrawSystem = new MeshDrawSystem(...);
		// mParticleDrawSystem = new ParticleDrawSystem(...);
		// mSpriteDrawSystem = new SpriteDrawSystem(...);
		// mSkyboxDrawSystem = new SkyboxDrawSystem(...);
		// mShadowDrawSystem = new ShadowDrawSystem(...);

		mInitialized = true;
		return .Ok;
	}

	/// Shuts down the renderer and releases resources.
	public void Shutdown()
	{
		if (!mInitialized)
			return;

		// TODO: Shutdown draw systems (reverse order)
		// delete mShadowDrawSystem; mShadowDrawSystem = null;
		// delete mSkyboxDrawSystem; mSkyboxDrawSystem = null;
		// delete mSpriteDrawSystem; mSpriteDrawSystem = null;
		// delete mParticleDrawSystem; mParticleDrawSystem = null;
		// delete mMeshDrawSystem; mMeshDrawSystem = null;

		// TODO: Shutdown core systems
		// delete mRenderGraph; mRenderGraph = null;
		// delete mPipelineFactory; mPipelineFactory = null;
		// delete mMaterialRegistry; mMaterialRegistry = null;
		// delete mShaderSystem; mShaderSystem = null;
		// delete mResourcePool; mResourcePool = null;

		mDevice = null;
		mInitialized = false;
	}

	/// Begins a new frame.
	/// @param frameIndex Current frame index (for multi-buffering).
	/// @param deltaTime Time since last frame in seconds.
	/// @param totalTime Total elapsed time in seconds.
	public void BeginFrame(uint32 frameIndex, float deltaTime, float totalTime)
	{
		if (!mInitialized)
			return;

		// Reset per-frame statistics
		mStats.Reset();

		// TODO: Begin frame on subsystems
		// mResourcePool.BeginFrame(frameIndex);
		// mRenderGraph.BeginFrame(frameIndex, deltaTime, totalTime);
	}

	/// Ends the current frame and records statistics.
	public void EndFrame()
	{
		if (!mInitialized)
			return;

		// TODO: End frame on subsystems
		// mRenderGraph.EndFrame();
		// mResourcePool.ProcessDeletions(frameIndex);

		// Record statistics
		mStatsAccumulator.RecordFrame(mStats);
	}

	/// Creates a new RenderWorld for a scene.
	/// @returns A new RenderWorld instance owned by the caller.
	public RenderWorld CreateRenderWorld()
	{
		return new RenderWorld();
	}

	public void Dispose()
	{
		Shutdown();
	}
}
