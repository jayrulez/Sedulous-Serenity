namespace Sedulous.RendererNext;

using System;
using Sedulous.RHI;

/// Skybox render pass.
/// Renders a fullscreen skybox using a cubemap texture.
/// Should be rendered after opaque geometry with depth test but no depth write.
class SkyboxPass : RenderPass
{
	private RenderGraphTextureHandle mColorTarget;
	private RenderGraphTextureHandle mDepthTarget;
	private IRenderPipeline mPipeline;
	private IBindGroup mBindGroup;
	private bool mEnabled = true;
	private CameraData mCameraData;
	private uint32 mWidth = 0;
	private uint32 mHeight = 0;

	public this() : base("SkyboxPass")
	{
	}

	/// Sets both color and depth targets.
	public void SetRenderTargets(RenderGraphTextureHandle colorTarget, RenderGraphTextureHandle depthTarget)
	{
		mColorTarget = colorTarget;
		mDepthTarget = depthTarget;
	}

	/// Sets the color target for this pass.
	public void SetColorTarget(RenderGraphTextureHandle colorTarget)
	{
		mColorTarget = colorTarget;
	}

	/// Sets the depth target for this pass.
	public void SetDepthTarget(RenderGraphTextureHandle depthTarget)
	{
		mDepthTarget = depthTarget;
	}

	/// Sets the camera data for this pass.
	public void SetCameraData(CameraData data)
	{
		mCameraData = data;
	}

	/// Sets the viewport dimensions.
	public void SetViewport(uint32 width, uint32 height)
	{
		mWidth = width;
		mHeight = height;
	}

	/// Sets the pipeline and bind group for skybox rendering.
	/// Bind group should contain: camera buffer, cubemap texture, sampler.
	public void SetPipeline(IRenderPipeline pipeline, IBindGroup bindGroup)
	{
		mPipeline = pipeline;
		mBindGroup = bindGroup;
	}

	/// Enables or disables the skybox.
	public void SetEnabled(bool enabled)
	{
		mEnabled = enabled;
	}

	public override void Setup(RenderGraphBuilder builder)
	{
		// Read color (we render on top of existing content)
		ReadTexture(mColorTarget);
		WriteTexture(mColorTarget);

		// Read depth for depth testing
		ReadTexture(mDepthTarget);
	}

	public override void Execute(RenderGraphContext context)
	{
		if (!mEnabled || mPipeline == null || mBindGroup == null)
			return;

		let colorView = context.GetTextureView(mColorTarget);
		let depthView = context.GetTextureView(mDepthTarget);

		if (colorView == null)
			return;

		// Color attachment (load existing content)
		RenderPassColorAttachment[1] colorAttachments = .(
			.()
			{
				View = colorView,
				LoadOp = .Load,
				StoreOp = .Store,
				ClearValue = default
			}
		);

		// Depth attachment (read-only for depth test)
		RenderPassDepthStencilAttachment depthAttachment = default;
		RenderPassDepthStencilAttachment* depthAttachmentPtr = null;

		if (depthView != null)
		{
			depthAttachment = .()
			{
				View = depthView,
				DepthLoadOp = .Load,
				DepthStoreOp = .Store,
				DepthClearValue = 0.0f,
				StencilLoadOp = .Load,
				StencilStoreOp = .Store,
				StencilClearValue = 0
			};
			depthAttachmentPtr = &depthAttachment;
		}

		RenderPassDescriptor passDesc = .(colorAttachments);
		if (depthAttachmentPtr != null)
			passDesc.DepthStencilAttachment = *depthAttachmentPtr;

		let renderPass = context.CommandEncoder.BeginRenderPass(&passDesc);
		if (renderPass == null)
			return;

		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroup);

		// Draw fullscreen triangle (vertices generated in shader using SV_VertexID)
		renderPass.Draw(3, 1, 0, 0);

		renderPass.End();
	}

	/// Returns true if skybox rendering is enabled.
	public bool IsEnabled => mEnabled;
}
