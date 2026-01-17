namespace Sedulous.Render;

using System;
using System.Collections;

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
	Result<void> Initialize(RenderSystem renderer);

	/// Shuts down the feature.
	/// Called once when the feature is unregistered.
	void Shutdown();

	/// Adds render passes to the graph for the current frame.
	/// Called each frame after BeginFrame and before Compile.
	void AddPasses(RenderGraph graph, RenderView view, RenderWorld world);
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

	/// Shuts down the feature.
	public void Shutdown()
	{
		if (!mInitialized)
			return;

		OnShutdown();
		mInitialized = false;
		mRenderer = null;
	}

	/// Called to add passes - must be overridden.
	public abstract void AddPasses(RenderGraph graph, RenderView view, RenderWorld world);

	/// Override for custom initialization.
	protected virtual Result<void> OnInitialize()
	{
		return .Ok;
	}

	/// Override for custom shutdown.
	protected virtual void OnShutdown()
	{
	}
}
