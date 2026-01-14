namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Depth pre-pass that renders scene depth without color output.
/// Used for early-Z optimization and depth buffer preparation.
class DepthPrePass : RenderPass
{
	private RenderGraphTextureHandle mDepthTarget;
	private List<DrawCommand> mDrawCommands ~ delete _;
	private IBuffer mCameraBuffer;
	private IRenderPipeline mPipeline;
	private IBindGroup mBindGroup;
	private CameraData mCameraData;
	private uint32 mWidth = 0;
	private uint32 mHeight = 0;

	public this() : base("DepthPrePass")
	{
		mDrawCommands = new .();
	}

	/// Sets the depth target for this pass.
	public void SetDepthTarget(RenderGraphTextureHandle depthTarget)
	{
		mDepthTarget = depthTarget;
	}

	/// Sets the camera uniform buffer.
	public void SetCameraBuffer(IBuffer cameraBuffer)
	{
		mCameraBuffer = cameraBuffer;
	}

	/// Sets the camera data for this pass.
	public void SetCameraData(CameraData data)
	{
		mCameraData = data;
	}

	/// Sets the pipeline and bind group for rendering.
	public void SetPipeline(IRenderPipeline pipeline, IBindGroup bindGroup)
	{
		mPipeline = pipeline;
		mBindGroup = bindGroup;
	}

	/// Sets the viewport dimensions.
	public void SetViewport(uint32 width, uint32 height)
	{
		mWidth = width;
		mHeight = height;
	}

	/// Adds a draw command to the pass.
	public void AddDrawCommand(DrawCommand cmd)
	{
		mDrawCommands.Add(cmd);
	}

	/// Sets draw commands from a span.
	public void SetDrawCommands(Span<DrawCommand> commands)
	{
		mDrawCommands.Clear();
		for (let cmd in commands)
			mDrawCommands.Add(cmd);
	}

	/// Clears all draw commands.
	public void ClearDrawCommands()
	{
		mDrawCommands.Clear();
	}

	public override void Setup(RenderGraphBuilder builder)
	{
		// Declare depth target write
		WriteTexture(mDepthTarget);
	}

	public override void Execute(RenderGraphContext context)
	{
		if (mPipeline == null || mDrawCommands.Count == 0)
			return;

		let depthView = context.GetTextureView(mDepthTarget);
		if (depthView == null)
			return;

		// Begin render pass with depth-only attachment
		RenderPassColorAttachment[0] colorAttachments = .();

		RenderPassDepthStencilAttachment depthAttachment = .()
		{
			View = depthView,
			DepthLoadOp = .Clear,
			DepthStoreOp = .Store,
			DepthClearValue = 0.0f,  // Reverse-Z: clear to 0
			StencilLoadOp = .Clear,
			StencilStoreOp = .Store,
			StencilClearValue = 0
		};

		RenderPassDescriptor passDesc = .(colorAttachments);
		passDesc.DepthStencilAttachment = depthAttachment;

		let renderPass = context.CommandEncoder.BeginRenderPass(&passDesc);
		if (renderPass == null)
			return;

		renderPass.SetPipeline(mPipeline);

		if (mBindGroup != null)
			renderPass.SetBindGroup(0, mBindGroup);

		// Execute draw commands
		for (let cmd in mDrawCommands)
		{
			if (cmd.VertexBuffer == null)
				continue;

			renderPass.SetVertexBuffer(0, cmd.VertexBuffer);

			if (cmd.IndexBuffer != null && cmd.IndexCount > 0)
			{
				renderPass.SetIndexBuffer(cmd.IndexBuffer, .UInt32);
				renderPass.DrawIndexed(cmd.IndexCount, cmd.InstanceCount, cmd.IndexOffset, (int32)cmd.VertexOffset, cmd.FirstInstance);
			}
			else if (cmd.VertexCount > 0)
			{
				renderPass.Draw(cmd.VertexCount, cmd.InstanceCount, cmd.VertexOffset, cmd.FirstInstance);
			}
		}

		renderPass.End();
	}

	/// Number of draw commands queued.
	public int32 DrawCommandCount => (int32)mDrawCommands.Count;
}
