namespace Sedulous.Render;

using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Materials;

/// Context provided to features during initialization.
/// Features must use the shared TransferBatch for all GPU uploads —
/// they must NOT submit work to queues directly.
public class InitContext
{
	/// The GPU device for creating pipelines, layouts, buffers, textures.
	public IDevice Device;

	/// Shared transfer batch for queueing GPU uploads.
	/// Do NOT call Submit() — the RenderSystem handles that.
	public ITransferBatch TransferBatch;

	/// GPU resource manager for uploading meshes, textures, bone buffers.
	public GPUResourceManager Resources;

	/// Shared default textures and samplers.
	public SharedResources SharedResources;

	/// Shader system for getting compiled shaders.
	public ShaderSystem ShaderSystem;

	/// Material system for creating materials and bind groups.
	public MaterialSystem MaterialSystem;

	/// Pipeline cache for lazy pipeline creation.
	public RenderPipelineCache PipelineCache;
}
