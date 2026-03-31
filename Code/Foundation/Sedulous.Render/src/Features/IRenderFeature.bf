namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;

/// Interface for modular render features.
/// Each feature is a self-contained rendering module that adds passes to the render graph.
public interface IRenderFeature
{
	/// Unique name for this feature (used for dependency resolution).
	StringView Name { get; }

	/// Gets the names of features this feature depends on.
	/// Dependencies are executed before this feature.
	void GetDependencies(List<StringView> outDependencies);

	/// Initializes the feature.
	/// Called once when the feature is registered with the render system.
	/// Use initCtx for all GPU resource creation and uploads during init.
	Result<void> Initialize(RenderSystem renderer, InitContext initCtx);

	/// Shuts down the feature.
	/// Called once when the feature is unregistered.
	void Shutdown();

	/// Prepares shared frame data (visibility, uniforms, lighting).
	/// Called once per frame before per-view AddPasses calls.
	/// Only needed for multi-view rendering; single-view path may skip this.
	void PrepareFrame(Span<RenderView> views, RenderWorld world, int32 frameIndex);

	/// Called when the renderer viewport is resized.
	void OnViewportResize(uint32 width, uint32 height);

	/// Adds render passes to the graph for the current frame.
	/// Called each frame after BeginFrame and before Compile.
	/// In multi-view mode, called once per view.
	void AddPasses(RenderGraph graph, ViewContext view, RenderWorld world);
}

/// Base class for render features with common functionality.
public abstract class RenderFeatureBase : IRenderFeature
{
	protected RenderSystem mRenderer;
	protected bool mInitialized = false;

	/// Gets the render system.
	protected RenderSystem Renderer => mRenderer;

	/// Gets whether the feature is initialized.
	public bool IsInitialized => mInitialized;

	/// Feature name - must be overridden.
	public abstract StringView Name { get; }

	/// Default: no dependencies.
	public virtual void GetDependencies(List<StringView> outDependencies)
	{
		// Override to add dependencies
	}

	/// Initializes the feature.
	public Result<void> Initialize(RenderSystem renderer, InitContext initCtx)
	{
		if (mInitialized)
			return .Err;

		mRenderer = renderer;

		if (OnInitialize(initCtx) case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	/// Shuts down the feature.
	public void Shutdown()
	{
		if (!mInitialized)
			return;

		OnShutdown();
		mInitialized = false;
		mRenderer = null;
	}

	/// Default: no shared frame preparation needed.
	public virtual void PrepareFrame(Span<RenderView> views, RenderWorld world, int32 frameIndex)
	{
	}

	/// Default: no resize handling needed.
	public virtual void OnViewportResize(uint32 width, uint32 height)
	{
	}

	/// Called to add passes - must be overridden.
	public abstract void AddPasses(RenderGraph graph, ViewContext view, RenderWorld world);

	/// Override for custom initialization.
	/// Use initCtx for GPU resource creation and uploads.
	protected virtual Result<void> OnInitialize(InitContext initCtx)
	{
		return .Ok;
	}

	/// Override for custom shutdown.
	protected virtual void OnShutdown()
	{
	}

}
