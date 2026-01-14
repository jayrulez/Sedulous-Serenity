namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Transparent geometry render pass.
/// Renders transparent objects with alpha blending, sorted back-to-front.
class TransparentPass : RenderPass
{
	private RenderGraphTextureHandle mColorTarget;
	private RenderGraphTextureHandle mDepthTarget;
	private List<DrawCommand> mDrawCommands ~ delete _;
	private List<DrawBatch> mBatches ~ delete _;
	private Vector3 mCameraPosition;
	private bool mSortEnabled = true;
	private CameraData mCameraData;
	private uint32 mWidth = 0;
	private uint32 mHeight = 0;
	private PipelineCache mPipelineCache;

	public this() : base("TransparentPass")
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

	/// Sets the depth target for this pass (read-only for depth testing).
	public void SetDepthTarget(RenderGraphTextureHandle depthTarget)
	{
		mDepthTarget = depthTarget;
	}

	/// Sets the camera data for this pass.
	public void SetCameraData(CameraData data)
	{
		mCameraData = data;
		mCameraPosition = data.Position;
	}

	/// Sets the camera position for sorting.
	public void SetCameraPosition(Vector3 position)
	{
		mCameraPosition = position;
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

	/// Enables or disables back-to-front sorting.
	public void SetSortEnabled(bool enabled)
	{
		mSortEnabled = enabled;
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
		// Read and write color (blending)
		ReadTexture(mColorTarget);
		WriteTexture(mColorTarget);

		// Read depth for depth testing (no write for transparent objects)
		ReadTexture(mDepthTarget);
	}

	public override void Execute(RenderGraphContext context)
	{
		if (mDrawCommands.Count == 0)
			return;

		let colorView = context.GetTextureView(mColorTarget);
		let depthView = context.GetTextureView(mDepthTarget);

		if (colorView == null)
			return;

		// Sort draw commands back-to-front if enabled
		if (mSortEnabled)
			SortDrawCommands();

		// Color attachment (load existing, blend on top)
		RenderPassColorAttachment[1] colorAttachments = .(
			.()
			{
				View = colorView,
				LoadOp = .Load,
				StoreOp = .Store,
				ClearValue = default
			}
		);

		// Depth attachment (read-only - load but don't write)
		RenderPassDepthStencilAttachment depthAttachment = default;
		RenderPassDepthStencilAttachment* depthAttachmentPtr = null;

		if (depthView != null)
		{
			depthAttachment = .()
			{
				View = depthView,
				DepthLoadOp = .Load,
				DepthStoreOp = .Store,  // Store even though we don't write (preserves depth)
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

		// Execute unbatched draw commands
		if (mBatches.Count == 0)
		{
			for (let cmd in mDrawCommands)
			{
				ExecuteDrawCommand(renderPass, cmd);
			}
		}

		renderPass.End();
	}

	/// Sorts draw commands back-to-front based on distance from camera.
	private void SortDrawCommands()
	{
		// Calculate sort keys based on distance from camera
		for (int i = 0; i < mDrawCommands.Count; i++)
		{
			var cmd = mDrawCommands[i];
			let objectPos = cmd.Transform.Translation;
			cmd.SortKey = Vector3.DistanceSquared(objectPos, mCameraPosition);
			mDrawCommands[i] = cmd;
		}

		// Sort back-to-front (larger distance first)
		mDrawCommands.Sort(scope (a, b) => {
			if (a.SortKey > b.SortKey) return -1;
			if (a.SortKey < b.SortKey) return 1;
			return 0;
		});
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
