namespace Sedulous.RendererNext;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Simple pass that clears the color and depth targets.
class ClearPass : RenderPass
{
	private RenderGraphTextureHandle mColorTarget;
	private RenderGraphTextureHandle mDepthTarget;
	private Color mClearColor = .(0.0f, 0.0f, 0.0f, 1.0f);
	private uint32 mWidth = 0;
	private uint32 mHeight = 0;

	public this() : base("ClearPass")
	{
	}

	public void SetRenderTarget(RenderGraphTextureHandle color, RenderGraphTextureHandle depth)
	{
		mColorTarget = color;
		mDepthTarget = depth;
	}

	public void SetClearColor(Color color)
	{
		mClearColor = color;
	}

	public void SetViewport(uint32 width, uint32 height)
	{
		mWidth = width;
		mHeight = height;
	}

	public override void Setup(RenderGraphBuilder builder)
	{
		// Declare we write to color
		WriteTexture(mColorTarget);

		// Declare we write to depth (if valid)
		if (mDepthTarget.IsValid)
			WriteTexture(mDepthTarget);
	}

	public override void Execute(RenderGraphContext context)
	{
		let colorView = context.GetTextureView(mColorTarget);
		let depthView = mDepthTarget.IsValid ? context.GetTextureView(mDepthTarget) : null;

		if (colorView == null)
			return;

		// Create render pass descriptor
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = colorView,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = mClearColor
		});

		RenderPassDescriptor passDesc = .(colorAttachments);

		if (depthView != null)
		{
			passDesc.DepthStencilAttachment = .()
			{
				View = depthView,
				DepthLoadOp = .Clear,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f,
				StencilLoadOp = .Clear,
				StencilStoreOp = .Store,
				StencilClearValue = 0
			};
		}

		let renderPass = context.CommandEncoder.BeginRenderPass(&passDesc);
		renderPass.SetViewport(0, 0, mWidth, mHeight, 0, 1);
		renderPass.SetScissorRect(0, 0, mWidth, mHeight);
		renderPass.End();
		delete renderPass;
	}
}
