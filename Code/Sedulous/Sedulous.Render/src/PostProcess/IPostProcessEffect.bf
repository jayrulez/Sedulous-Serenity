namespace Sedulous.Render;

using System;
using Sedulous.RHI;

/// Interface for post-processing effects.
/// Effects are executed in order, reading from the previous result and writing to the next target.
interface IPostProcessEffect
{
	/// Unique name for this effect (for debugging and configuration).
	StringView Name { get; }

	/// Priority determines execution order (lower = earlier).
	/// Suggested ranges:
	/// - 0-99: Pre-lighting effects (volumetric fog)
	/// - 100-199: Lighting effects (SSR, SSAO)
	/// - 200-299: Color effects (bloom, exposure)
	/// - 300-399: Anti-aliasing (TAA, FXAA)
	/// - 400-499: Final adjustments (tone mapping, color grading)
	int Priority { get; }

	/// Whether this effect is currently enabled.
	bool Enabled { get; set; }

	/// Initialize the effect (create pipelines, buffers, etc.).
	Result<void> Initialize(IDevice device);

	/// Shutdown and release resources.
	void Shutdown();

	/// Add passes to the render graph for this effect.
	/// @param graph The render graph to add passes to.
	/// @param view The current render view.
	/// @param inputHandle Handle to the input texture (previous effect's output or SceneColor).
	/// @param outputHandle Handle to the output texture (this effect's result).
	/// @param depthHandle Handle to the scene depth texture (for effects that need it).
	void AddPasses(
		RenderGraph graph,
		RenderView view,
		RGResourceHandle inputHandle,
		RGResourceHandle outputHandle,
		RGResourceHandle depthHandle);
}
