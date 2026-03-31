namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;

/// Inputs available to all post-processing effects.
struct PostProcessInputs
{
	/// Current chain input (RGBA16Float HDR). First effect gets scene color.
	public RGTexture SceneColor;
	/// Depth prepass output.
	public RGTexture Depth;
	/// Per-pixel motion vectors (RG16Float).
	public RGTexture MotionVectors;
	/// Thin G-buffer: RG=octahedral normal, B=roughness, A=metallic.
	public RGTexture GBuffer;
}

/// Interface for modular post-processing effects.
/// Each effect reads from the chain input and returns a new texture as output.
/// Effects are managed by PostProcessStack and executed in priority order.
interface IPostProcessEffect
{
	/// Display name.
	StringView Name { get; }

	/// Execution priority (lower = earlier in chain).
	/// TAA=0, Bloom=100, Tonemap=1000.
	int32 Priority { get; }

	/// Whether this effect is active.
	bool Enabled { get; set; }

	/// Called before the render graph is built, before features add passes.
	/// Use for operations that must precede scene rendering (e.g., TAA jitter).
	void OnPreGraph(ViewContext viewCtx, FrameContext frameCtx) { }

	/// Called once during PostProcessStack initialization.
	Result<void> OnInitialize(InitContext initCtx);

	/// Adds render graph passes for this effect.
	/// Returns the output texture (may be a new texture or the input unchanged).
	RGTexture OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx,
		PostProcessInputs inputs);

	/// Called during shutdown to release GPU resources.
	void OnShutdown(IDevice device);
}
