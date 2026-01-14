namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Opaque geometry render pass.
/// Renders all opaque objects with full shading.
class OpaquePass : RenderPass
{
	private RenderGraphTextureHandle mColorTarget;
	private RenderGraphTextureHandle mDepthTarget;
	private List<DrawCommand> mDrawCommands ~ delete _;
	private List<DrawBatch> mBatches ~ delete _;
	private Color mClearColor = .(25, 25, 25, 255);
	private bool mClearColorTarget = true;
	private bool mClearDepthTarget = false;  // Usually depth is pre-cleared by DepthPrePass
	private CameraData mCameraData;
	private uint32 mWidth = 0;
	private uint32 mHeight = 0;
	private PipelineCache mPipelineCache;

	public this() : base("OpaquePass")
	{
		mDrawCommands = new .();
		mBatches = new .();
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

	/// Sets the clear color.
	public void SetClearColor(Color color)
	{
		mClearColor = color;
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

	/// Sets the pipeline cache for dynamic pipeline creation.
	public void SetPipelineCache(PipelineCache cache)
	{
		mPipelineCache = cache;
	}

	/// Sets whether to clear the color target.
	public void SetClearColorTarget(bool clear)
	{
		mClearColorTarget = clear;
	}

	/// Sets whether to clear the depth target.
	public void SetClearDepthTarget(bool clear)
	{
		mClearDepthTarget = clear;
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

	/// Adds a batch of draw commands with shared pipeline/bindgroup.
	public void AddBatch(DrawBatch batch)
	{
		mBatches.Add(batch);
	}

	/// Clears all draw commands and batches.
	public void Clear()
	{
		mDrawCommands.Clear();
		mBatches.Clear();
	}

	public override void Setup(RenderGraphBuilder builder)
	{
		// Declare color target write
		WriteTexture(mColorTarget);

		// Declare depth target read (for depth testing) and write (for depth updates)
		ReadTexture(mDepthTarget);
		WriteTexture(mDepthTarget);
	}

	public override void Execute(RenderGraphContext context)
	{
		let colorView = context.GetTextureView(mColorTarget);
		let depthView = context.GetTextureView(mDepthTarget);

		if (colorView == null)
			return;

		// Color attachment
		RenderPassColorAttachment[1] colorAttachments = .(
			.()
			{
				View = colorView,
				LoadOp = mClearColorTarget ? .Clear : .Load,
				StoreOp = .Store,
				ClearValue = .(
					(float)mClearColor.R / 255.0f,
					(float)mClearColor.G / 255.0f,
					(float)mClearColor.B / 255.0f,
					(float)mClearColor.A / 255.0f
				)
			}
		);

		// Depth attachment (optional)
		RenderPassDepthStencilAttachment depthAttachment = default;
		RenderPassDepthStencilAttachment* depthAttachmentPtr = null;

		if (depthView != null)
		{
			depthAttachment = .()
			{
				View = depthView,
				DepthLoadOp = mClearDepthTarget ? .Clear : .Load,
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

		// Execute batches
		for (let batch in mBatches)
		{
			if (batch.Pipeline == null)
				continue;

			renderPass.SetPipeline(batch.Pipeline);

			if (batch.BindGroup != null)
				renderPass.SetBindGroup(0, batch.BindGroup);

			// Draw commands in this batch
			for (int i = batch.StartIndex; i < batch.StartIndex + batch.Count && i < mDrawCommands.Count; i++)
			{
				let cmd = mDrawCommands[i];
				ExecuteDrawCommand(renderPass, cmd);
			}
		}

		// Execute unbatched draw commands (if any batches specify a pipeline)
		// This is a fallback for simple use cases
		if (mBatches.Count == 0)
		{
			for (let cmd in mDrawCommands)
			{
				ExecuteDrawCommand(renderPass, cmd);
			}
		}

		renderPass.End();
	}

	private void ExecuteDrawCommand(IRenderPassEncoder renderPass, DrawCommand cmd)
	{
		if (cmd.VertexBuffer == null)
			return;

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

	/// Number of draw commands queued.
	public int32 DrawCommandCount => (int32)mDrawCommands.Count;

	/// Number of batches.
	public int32 BatchCount => (int32)mBatches.Count;
}
