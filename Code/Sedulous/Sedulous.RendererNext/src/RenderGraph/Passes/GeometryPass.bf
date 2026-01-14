namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Simple geometry rendering pass.
/// Renders a list of meshes with transforms using a single shader.
class GeometryPass : RenderPass
{
	/// Draw item for the geometry pass.
	public struct DrawItem
	{
		public GPUStaticMesh Mesh;
		public Matrix Transform;
		public IBindGroup ObjectBindGroup;
	}

	private RenderGraphTextureHandle mColorTarget;
	private RenderGraphTextureHandle mDepthTarget;
	private uint32 mWidth;
	private uint32 mHeight;

	private IRenderPipeline mPipeline;
	private IBindGroup mCameraBindGroup;
	private List<DrawItem> mDrawItems = new .() ~ delete _;

	public this() : base("GeometryPass")
	{
	}

	/// Sets the render targets.
	public void SetRenderTargets(RenderGraphTextureHandle color, RenderGraphTextureHandle depth, uint32 width, uint32 height)
	{
		mColorTarget = color;
		mDepthTarget = depth;
		mWidth = width;
		mHeight = height;
	}

	/// Sets the pipeline to use.
	public void SetPipeline(IRenderPipeline pipeline)
	{
		mPipeline = pipeline;
	}

	/// Sets the camera bind group (per-frame data).
	public void SetCameraBindGroup(IBindGroup bindGroup)
	{
		mCameraBindGroup = bindGroup;
	}

	/// Adds a draw item.
	public void AddDrawItem(GPUStaticMesh mesh, Matrix transform, IBindGroup objectBindGroup)
	{
		mDrawItems.Add(.() { Mesh = mesh, Transform = transform, ObjectBindGroup = objectBindGroup });
	}

	/// Clears all draw items.
	public void ClearDrawItems()
	{
		mDrawItems.Clear();
	}

	public override void Setup(RenderGraphBuilder builder)
	{
		WriteTexture(mColorTarget);
		if (mDepthTarget.IsValid)
			WriteTexture(mDepthTarget);
	}

	public override void Execute(RenderGraphContext context)
	{
		if (mPipeline == null || mDrawItems.Count == 0)
			return;

		let colorView = context.GetTextureView(mColorTarget);
		let depthView = mDepthTarget.IsValid ? context.GetTextureView(mDepthTarget) : null;

		if (colorView == null)
			return;

		// Create render pass descriptor
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = colorView,
			LoadOp = .Load,  // Preserve existing content (cleared by ClearPass)
			StoreOp = .Store,
			ClearValue = .(0, 0, 0, 1)
		});

		RenderPassDescriptor passDesc = .(colorAttachments);

		if (depthView != null)
		{
			passDesc.DepthStencilAttachment = .()
			{
				View = depthView,
				DepthLoadOp = .Load,
				DepthStoreOp = .Store,
				DepthClearValue = 0.0f,  // Reverse-Z
				StencilLoadOp = .Load,
				StencilStoreOp = .Store,
				StencilClearValue = 0
			};
		}

		let renderPass = context.CommandEncoder.BeginRenderPass(&passDesc);
		renderPass.SetViewport(0, 0, mWidth, mHeight, 0, 1);
		renderPass.SetScissorRect(0, 0, mWidth, mHeight);
		renderPass.SetPipeline(mPipeline);

		// Bind camera data (group 0)
		if (mCameraBindGroup != null)
			renderPass.SetBindGroup(0, mCameraBindGroup);

		// Draw each item
		for (let item in mDrawItems)
		{
			if (item.Mesh == null || item.Mesh.VertexBuffer == null)
				continue;

			// Bind object data (group 1)
			if (item.ObjectBindGroup != null)
				renderPass.SetBindGroup(1, item.ObjectBindGroup);

			// Bind vertex buffer
			renderPass.SetVertexBuffer(0, item.Mesh.VertexBuffer);

			// Draw
			if (item.Mesh.IsIndexed)
			{
				renderPass.SetIndexBuffer(item.Mesh.IndexBuffer, item.Mesh.IndexFormat);
				renderPass.DrawIndexed(item.Mesh.IndexCount, 1, 0, 0, 0);
			}
			else
			{
				renderPass.Draw(item.Mesh.VertexCount, 1, 0, 0);
			}
		}

		renderPass.End();
		delete renderPass;
	}
}
