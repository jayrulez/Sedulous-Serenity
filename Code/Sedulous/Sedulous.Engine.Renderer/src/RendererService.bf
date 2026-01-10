namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Engine.Core;
using Sedulous.Renderer;

/// Context service that owns shared GPU resources across all scenes.
/// Register this service with the Context to enable entity-based rendering.
class RendererService : IContextService, IDisposable
{
	private Context mContext;
	private IDevice mDevice;
	private GPUResourceManager mResourceManager ~ delete _;
	private ShaderLibrary mShaderLibrary ~ delete _;
	private LightingSystem mLightingSystem ~ delete _;
	private PipelineCache mPipelineCache ~ delete _;
	private MaterialSystem mMaterialSystem ~ delete _;
	private bool mInitialized = false;

	/// Gets the graphics device.
	public IDevice Device => mDevice;

	/// Gets the GPU resource manager for meshes and textures.
	public GPUResourceManager ResourceManager => mResourceManager;

	/// Gets the shader library for loading and caching shaders.
	public ShaderLibrary ShaderLibrary => mShaderLibrary;

	/// Gets the lighting system for clustered lighting and shadows.
	public LightingSystem LightingSystem => mLightingSystem;

	/// Gets the pipeline cache for render pipelines.
	public PipelineCache PipelineCache => mPipelineCache;

	/// Gets the material system for materials and material instances.
	public MaterialSystem MaterialSystem => mMaterialSystem;

	/// Gets whether the service has been initialized.
	public bool IsInitialized => mInitialized;

	/// Initializes the renderer service with a graphics device.
	/// Call this before registering the service with the context.
	public Result<void> Initialize(IDevice device, StringView shaderBasePath = "shaders")
	{
		if (device == null)
			return .Err;

		mDevice = device;
		mResourceManager = new GPUResourceManager(device);
		mShaderLibrary = new ShaderLibrary(device, shaderBasePath);
		mLightingSystem = new LightingSystem(device);
		mPipelineCache = new PipelineCache(device, mShaderLibrary);
		mMaterialSystem = new MaterialSystem(device, mShaderLibrary, mResourceManager);
		mInitialized = true;

		return .Ok;
	}

	/// Sets the shader base path for loading shaders.
	public void SetShaderPath(StringView path)
	{
		if (mShaderLibrary != null)
			mShaderLibrary.SetShaderPath(path);
	}

	// ==================== IContextService Implementation ====================

	/// Called when the service is registered with the context.
	public void OnRegister(Context context)
	{
		mContext = context;
	}

	/// Called when the service is unregistered from the context.
	public void OnUnregister()
	{
		mContext = null;
	}

	/// Called during context startup.
	public void Startup()
	{
		// Renderer is ready to use after context startup
	}

	/// Called during context shutdown.
	public void Shutdown()
	{
		// Clean up cached resources
		if (mPipelineCache != null)
			mPipelineCache.Clear();
		if (mShaderLibrary != null)
			mShaderLibrary.ClearCache();
	}

	/// Called each frame during context update.
	public void Update(float deltaTime)
	{
		// Global renderer updates (if any) go here
		// Per-scene rendering is handled by RenderSceneComponent
	}

	// ==================== IDisposable Implementation ====================

	public void Dispose()
	{
		Shutdown();
	}
}
