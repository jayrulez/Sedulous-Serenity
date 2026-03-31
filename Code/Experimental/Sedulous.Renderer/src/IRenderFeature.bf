namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;

/// Context provided to features during initialization.
/// Features must use the shared TransferBatch for all GPU uploads —
/// they must NOT submit work to queues directly.
class InitContext
{
	/// The GPU device for creating pipelines, layouts, buffers, textures.
	public IDevice Device;

	/// Shared transfer batch for queueing GPU uploads.
	/// Do NOT call Submit() — the RenderSystem handles that.
	public ITransferBatch TransferBatch;

	/// GPU resource manager for uploading meshes, textures, bone buffers.
	public GPUResourceManager Resources;

	/// Shader library for registering and compiling shaders.
	public ShaderLibrary Shaders;

	/// Pipeline cache for creating and caching render pipelines.
	public RenderPipelineCache Pipelines;

	/// The owning render system (for accessing shared state like batcher, bind groups).
	public RenderSystem System;
}

/// Interface for modular render features.
/// Each feature encapsulates one aspect of the rendering pipeline
/// (e.g., shadows, lighting, post-processing) and adds passes
/// to the render graph each frame.
interface IRenderFeature
{
	/// Display name of this feature (for debugging/profiling).
	StringView Name { get; }

	/// Whether this feature participates in probe capture (scene rendering into cubemap faces).
	/// Override to return true for features that render geometry or sky.
	/// Default false — post-processing, blit, motion vectors, ImGui skip probe capture.
	bool SupportsProbeCapture => false;

	/// Called once during RenderSystem initialization.
	/// Use initCtx.TransferBatch for GPU uploads; do not submit work directly.
	Result<void> OnInitialize(InitContext initCtx);

	/// Called each frame before graph execution to record pre-graph GPU work
	/// (one-time compute bakes, per-frame uploads, etc.).
	/// Features should early-return if they have no work to do.
	void OnRecordPreGraph(ICommandEncoder encoder) {}

	/// Called each frame to add passes to the render graph.
	void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx);

	/// Called each frame after graph execution to read back stats, etc.
	void OnPostRender() {}

	/// Called during RenderSystem shutdown to release GPU resources.
	void OnShutdown(IDevice device);
}
