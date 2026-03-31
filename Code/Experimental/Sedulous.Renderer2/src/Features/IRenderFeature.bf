namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;

/// Interface for modular render features.
/// Each feature encapsulates one aspect of the rendering pipeline
/// and adds passes to the render graph each frame.
/// Access world data via Renderer.ActiveWorld, view data via ViewContext.
public interface IRenderFeature
{
	/// Unique name for this feature (used for dependency resolution).
	StringView Name { get; }

	/// Gets the names of features this feature depends on.
	void GetDependencies(List<StringView> outDependencies);

	/// Initializes the feature. Called once when registered.
	Result<void> Initialize(RenderSystem renderer);

	/// Shuts down the feature. Called once when unregistered.
	void Shutdown();

	/// Prepares shared frame data before per-view pass building.
	/// Called once per frame (not per view).
	void PrepareFrame(int32 frameIndex);

	/// Adds render passes to the graph for the current view.
	/// Called each frame, once per view in multi-view mode.
	/// Access world data via Renderer.ActiveWorld.
	void AddPasses(Sedulous.RenderGraph.RenderGraph graph, RenderFrameContext frameCtx, ViewContext viewCtx);
}

/// Base class for render features with common functionality.
public abstract class RenderFeatureBase : IRenderFeature
{
	protected RenderSystem mRenderer;
	protected bool mInitialized = false;

	protected RenderSystem Renderer => mRenderer;
	protected IDevice Device => mRenderer?.Device;
	protected SharedResources Shared => mRenderer?.SharedResources;

	/// Convenience: the active world from the render system.
	protected RenderWorld World => mRenderer?.ActiveWorld;

	public bool IsInitialized => mInitialized;

	public abstract StringView Name { get; }

	public virtual void GetDependencies(List<StringView> outDependencies)
	{
	}

	public Result<void> Initialize(RenderSystem renderer)
	{
		if (mInitialized)
			return .Err;

		mRenderer = renderer;

		if (OnInitialize() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	public void Shutdown()
	{
		if (!mInitialized)
			return;

		OnShutdown();
		mInitialized = false;
		mRenderer = null;
	}

	public virtual void PrepareFrame(int32 frameIndex)
	{
	}

	public abstract void AddPasses(Sedulous.RenderGraph.RenderGraph graph, RenderFrameContext frameCtx, ViewContext viewCtx);

	protected virtual Result<void> OnInitialize()
	{
		return .Ok;
	}

	protected virtual void OnShutdown()
	{
	}
}
