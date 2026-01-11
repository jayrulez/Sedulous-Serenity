namespace Sedulous.Renderer;

using Sedulous.RHI;

/// Interface for rendering systems that participate in the render graph.
///
/// ## Overview
///
/// Any rendering system (UI, particles, post-processing, etc.) that needs to render
/// to textures or participate in the frame's render pass ordering should implement
/// this interface. This ensures proper barrier management and resource tracking.
///
/// ## Why This Matters
///
/// The render graph manages GPU resource state transitions (barriers). When a renderer
/// creates its own render passes internally, it bypasses the graph's barrier management,
/// leading to validation errors like:
///
///   "Cannot use VkImage with layout VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
///    that doesn't match VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL"
///
/// By implementing this interface, renderers let the graph handle all state transitions.
///
/// ## Implementation Pattern
///
/// 1. **AddPasses**: Register your render passes with the graph. Import any textures
///    you'll render to, declare reads/writes, and set up the execute callback.
///
/// 2. **RenderWithinPass**: Do the actual rendering within the graph-provided pass.
///    Don't create your own render passes here - just issue draw calls.
///
/// ## Example Implementation
///
/// ```beef
/// class MyRenderer : IGraphRenderer
/// {
///     private ITexture mRenderTexture;
///     private ITextureView mRenderTextureView;
///
///     public void AddPasses(RenderGraph graph, int32 frameIndex)
///     {
///         // Import your render target
///         let handle = graph.ImportTexture("MyOutput", mRenderTexture, mRenderTextureView, .Undefined);
///
///         // Add a pass that writes to it
///         graph.AddGraphicsPass("MyPass")
///             .SetColorAttachment(0, handle, .Clear, .Store, Color(0, 0, 0, 0))
///             .Write(handle, .ColorAttachment)
///             .SetExecute(new [this, frameIndex](ctx) => {
///                 RenderWithinPass(ctx.RenderPass, frameIndex);
///             });
///     }
///
///     public void RenderWithinPass(IRenderPassEncoder renderPass, int32 frameIndex)
///     {
///         // Issue draw calls - don't create render passes here
///         renderPass.SetPipeline(mPipeline);
///         renderPass.Draw(vertexCount, 1, 0, 0);
///     }
/// }
/// ```
///
/// ## Dependencies Between Passes
///
/// If another pass needs to sample your output texture (e.g., a sprite sampling
/// a render-to-texture UI), that pass should declare a dependency:
///
/// ```beef
/// graph.AddGraphicsPass("ConsumerPass")
///     .AddDependency("MyPass")  // Ensures MyPass runs first
///     // ...
/// ```
///
/// The render graph automatically inserts barriers to transition ColorAttachment
/// outputs to ShaderReadOnly when dependent passes run.
///
/// ## Integration with Scene Components
///
/// Scene components that own an IGraphRenderer should call AddPasses during
/// the frame's preparation phase (e.g., in RenderSceneComponent.AddRenderPasses
/// or via RendererService.BeginFrame).
///
interface IGraphRenderer
{
	/// Adds this renderer's passes to the render graph.
	///
	/// Import any textures you'll render to, declare resource dependencies,
	/// and register execute callbacks. The graph will handle pass ordering
	/// and barrier insertion.
	///
	/// @param graph The render graph for the current frame.
	/// @param frameIndex The current frame index (for double/triple buffering).
	void AddPasses(RenderGraph graph, int32 frameIndex);

	/// Renders within a graph-provided render pass.
	///
	/// Issue draw calls here. Do NOT create your own render passes -
	/// the graph has already set up the render pass with proper attachments
	/// and will handle ending it.
	///
	/// @param renderPass The active render pass encoder.
	/// @param frameIndex The current frame index.
	void RenderWithinPass(IRenderPassEncoder renderPass, int32 frameIndex);
}
