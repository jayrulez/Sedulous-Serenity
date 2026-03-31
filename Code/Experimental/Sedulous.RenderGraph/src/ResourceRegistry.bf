namespace Sedulous.RenderGraph;

using System;
using System.Collections;
using Sedulous.RHI;

/// Runtime resource registry.
/// Available during pass execution — maps render graph handles to concrete GPU resources.
class ResourceRegistry
{
	private RenderGraph mGraph;

	public this(RenderGraph graph)
	{
		mGraph = graph;
	}

	/// Gets the concrete GPU texture for a render graph texture handle.
	public ITexture GetTexture(RGTexture handle)
	{
		let resource = mGraph.[Friend]GetResource(handle.Index);
		if (resource == null) return null;
		return resource.ImportedTexture;
	}

	/// Gets the concrete GPU texture view for a render graph texture handle.
	public ITextureView GetTextureView(RGTexture handle)
	{
		let resource = mGraph.[Friend]GetResource(handle.Index);
		if (resource == null) return null;
		return resource.ImportedTextureView;
	}

	/// Gets the concrete GPU buffer for a render graph buffer handle.
	public IBuffer GetBuffer(RGBuffer handle)
	{
		let resource = mGraph.[Friend]GetResource(handle.Index);
		if (resource == null) return null;
		return resource.ImportedBuffer;
	}

	/// Builds a RenderPassDesc from the pass's declared render targets and depth/stencil attachment.
	public RenderPassDesc GetRenderPassDesc(RenderGraphPass pass)
	{
		RenderPassDesc desc = .();

		// Build color attachments
		for (int i = 0; i < pass.RenderTargets.Count; i++)
		{
			let rt = pass.RenderTargets[i];
			let resource = mGraph.[Friend]GetResource(rt.Texture.Index);

			desc.ColorAttachments.Add(.()
			{
				View = resource?.ImportedTextureView,
				LoadOp = rt.LoadOp,
				StoreOp = rt.StoreOp,
				ClearValue = rt.ClearColor
			});
		}

		// Build depth/stencil attachment
		if (pass.DepthStencil.HasValue)
		{
			let ds = pass.DepthStencil.Value;
			let resource = mGraph.[Friend]GetResource(ds.Texture.Index);

			desc.DepthStencilAttachment = .()
			{
				View = resource?.ImportedTextureView,
				DepthLoadOp = ds.DepthLoadOp,
				DepthStoreOp = ds.DepthStoreOp,
				DepthClearValue = ds.DepthClearValue,
				DepthReadOnly = ds.DepthReadOnly,
				StencilLoadOp = ds.StencilLoadOp,
				StencilStoreOp = ds.StencilStoreOp,
				StencilClearValue = ds.StencilClearValue,
				StencilReadOnly = ds.StencilReadOnly
			};
		}

		desc.Label = pass.Name;
		return desc;
	}
}
