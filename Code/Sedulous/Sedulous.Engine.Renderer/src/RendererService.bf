namespace Sedulous.Engine.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Engine.Core;
using Sedulous.Renderer;

/// Context service that owns shared GPU resources across all scenes.
/// Register this service with the Context to enable entity-based rendering.
/// Automatically creates RenderSceneComponent for each scene.
///
/// Owns:
/// - GPUResourceManager (meshes, textures)
/// - ShaderLibrary (shader loading/caching)
/// - MaterialSystem (materials, material instances)
/// - PipelineCache (render pipeline caching)
/// - RenderPipeline (shared rendering orchestrator)
///
/// Note: LightingSystem is per-scene and owned by RenderContext, not here.
class RendererService : ContextService, IDisposable
{
	private Context mContext;
	private IDevice mDevice;
	private GPUResourceManager mResourceManager ~ delete _;
	private ShaderLibrary mShaderLibrary ~ delete _;
	private PipelineCache mPipelineCache ~ delete _;
	private MaterialSystem mMaterialSystem ~ delete _;
	private RenderPipeline mPipeline ~ delete _;
	private bool mInitialized = false;
	private TextureFormat mColorFormat = .BGRA8Unorm;
	private TextureFormat mDepthFormat = .Depth32FloatStencil8;

	// Track created scene components
	private List<RenderSceneComponent> mSceneComponents = new .() ~ delete _;

	/// Gets the graphics device.
	public IDevice Device => mDevice;

	/// Gets the GPU resource manager for meshes and textures.
	public GPUResourceManager ResourceManager => mResourceManager;

	/// Gets the shader library for loading and caching shaders.
	public ShaderLibrary ShaderLibrary => mShaderLibrary;

	/// Gets the pipeline cache for render pipelines.
	public PipelineCache PipelineCache => mPipelineCache;

	/// Gets the material system for materials and material instances.
	public MaterialSystem MaterialSystem => mMaterialSystem;

	/// Gets the shared render pipeline.
	public RenderPipeline Pipeline => mPipeline;

	/// Gets whether the service has been initialized.
	public bool IsInitialized => mInitialized;

	/// Gets the color format used for rendering.
	public TextureFormat ColorFormat => mColorFormat;

	/// Gets the depth format used for rendering.
	public TextureFormat DepthFormat => mDepthFormat;

	/// Initializes the renderer service with a graphics device.
	/// Call this before registering the service with the context.
	public Result<void> Initialize(IDevice device, StringView shaderBasePath = "shaders")
	{
		if (device == null)
			return .Err;

		mDevice = device;
		mResourceManager = new GPUResourceManager(device);
		mShaderLibrary = new ShaderLibrary(device, shaderBasePath);
		mPipelineCache = new PipelineCache(device, mShaderLibrary);
		mMaterialSystem = new MaterialSystem(device, mShaderLibrary, mResourceManager);

		// Create the shared render pipeline
		mPipeline = new RenderPipeline();
		if (mPipeline.Initialize(device, mShaderLibrary, mMaterialSystem, mResourceManager,
			mPipelineCache, mColorFormat, mDepthFormat) case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	/// Sets the color and depth format for rendering.
	/// Must be called before Initialize() if using non-default formats.
	public void SetFormats(TextureFormat colorFormat, TextureFormat depthFormat)
	{
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;
	}

	/// Sets the shader base path for loading shaders.
	public void SetShaderPath(StringView path)
	{
		if (mShaderLibrary != null)
			mShaderLibrary.SetShaderPath(path);
	}

	// ==================== IContextService Implementation ====================

	/// Called when the service is registered with the context.
	public override void OnRegister(Context context)
	{
		mContext = context;
	}

	/// Called when the service is unregistered from the context.
	public override void OnUnregister()
	{
		mContext = null;
	}

	/// Called during context startup.
	public override void Startup()
	{
		// Renderer is ready to use after context startup
	}

	/// Called during context shutdown.
	public override void Shutdown()
	{
		// Clean up cached resources
		if (mPipelineCache != null)
			mPipelineCache.Clear();
		if (mShaderLibrary != null)
			mShaderLibrary.ClearCache();
	}

	/// Called each frame during context update.
	public override void Update(float deltaTime)
	{
		// Global renderer updates (if any) go here
		// Per-scene rendering is handled by RenderSceneComponent
	}

	/// Called when a scene is created.
	/// Automatically adds RenderSceneComponent to the scene.
	public override void OnSceneCreated(Scene scene)
	{
		if (!mInitialized || mDevice == null)
		{
			mContext?.Logger?.LogWarning("RendererService: Not initialized, skipping RenderSceneComponent for '{}'", scene.Name);
			return;
		}

		let component = new RenderSceneComponent(this);
		scene.AddSceneComponent(component);
		mSceneComponents.Add(component);

		// Initialize rendering resources
		if (component.InitializeRendering() case .Err)
		{
			mContext?.Logger?.LogError("RendererService: Failed to initialize rendering for scene '{}'", scene.Name);
			scene.RemoveSceneComponent<RenderSceneComponent>();
			mSceneComponents.Remove(component);
			return;
		}

		mContext?.Logger?.LogDebug("RendererService: Added RenderSceneComponent to scene '{}'", scene.Name);
	}

	/// Called when a scene is being destroyed.
	/// Removes tracked component for this scene.
	public override void OnSceneDestroyed(Scene scene)
	{
		// Find and remove component belonging to this scene
		for (int i = mSceneComponents.Count - 1; i >= 0; i--)
		{
			let component = mSceneComponents[i];
			if (component.Scene == scene)
			{
				mSceneComponents.RemoveAt(i);
				// Note: Scene will delete the component via RemoveSceneComponent
				break;
			}
		}
	}

	/// Gets all RenderSceneComponents created by this service.
	public Span<RenderSceneComponent> SceneComponents => mSceneComponents;

	// ==================== IDisposable Implementation ====================

	public void Dispose()
	{
		Shutdown();
	}
}
