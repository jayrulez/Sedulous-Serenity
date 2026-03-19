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
	Result<void> Initialize(RenderSystem renderer);

	/// Shuts down the feature.
	/// Called once when the feature is unregistered.
	void Shutdown();

	/// Prepares shared frame data (visibility, uniforms, lighting).
	/// Called once per frame before per-view AddPasses calls.
	/// Only needed for multi-view rendering; single-view path may skip this.
	void PrepareFrame(Span<RenderView> views, RenderWorld world, int32 frameIndex);

	/// Adds render passes to the graph for the current frame.
	/// Called each frame after BeginFrame and before Compile.
	/// In multi-view mode, called once per view.
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

	/// Default: no shared frame preparation needed.
	public virtual void PrepareFrame(Span<RenderView> views, RenderWorld world, int32 frameIndex)
	{
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

	/// Uploads texture data, using the init-time transfer batch if available,
	/// otherwise falling back to synchronous upload.
	protected void UploadTexture(ITexture texture, Span<uint8> data,
		TextureDataLayout* dataLayout, Extent3D* writeSize,
		uint32 mipLevel = 0, uint32 arrayLayer = 0)
	{
		if (mRenderer?.TransferBatch != null)
			mRenderer.TransferBatch.WriteTexture(texture, data, dataLayout, writeSize, mipLevel, arrayLayer);
		else
			mRenderer.Device.Queue.WriteTextureSync(texture, data, dataLayout, writeSize, mipLevel, arrayLayer);
	}

	/// Uploads buffer data via staging, using the init-time transfer batch if available,
	/// otherwise falling back to synchronous upload.
	protected void UploadBuffer(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		if (mRenderer?.TransferBatch != null)
			mRenderer.TransferBatch.WriteBuffer(buffer, offset, data);
		else
			mRenderer.Device.Queue.WriteStagedBufferSync(buffer, offset, data);
	}
}
