namespace Sedulous.RHI;

using System;
using Sedulous.Mathematics;

/// Describes a color attachment in a render pass.
struct RenderPassColorAttachment
{
	/// Texture view to render to.
	public ITextureView View;
	/// Texture view for MSAA resolve (null if not resolving).
	public ITextureView ResolveTarget;
	/// Operation when loading the attachment.
	public LoadOp LoadOp;
	/// Operation when storing the attachment.
	public StoreOp StoreOp;
	/// Clear color (when LoadOp is Clear).
	public Color ClearValue;

	public this()
	{
		View = null;
		ResolveTarget = null;
		LoadOp = .Clear;
		StoreOp = .Store;
		ClearValue = .(0.0f, 0.0f, 0.0f, 1.0f);
	}

	public this(ITextureView view, LoadOp loadOp = .Clear, StoreOp storeOp = .Store)
	{
		View = view;
		ResolveTarget = null;
		LoadOp = loadOp;
		StoreOp = storeOp;
		ClearValue = .(0.0f, 0.0f, 0.0f, 1.0f);
	}
}

/// Describes a depth/stencil attachment in a render pass.
struct RenderPassDepthStencilAttachment
{
	/// Texture view to use for depth/stencil.
	public ITextureView View;
	/// Operation when loading depth.
	public LoadOp DepthLoadOp;
	/// Operation when storing depth.
	public StoreOp DepthStoreOp;
	/// Clear depth value (when DepthLoadOp is Clear).
	public float DepthClearValue;
	/// Make depth read-only.
	public bool DepthReadOnly;
	/// Operation when loading stencil.
	public LoadOp StencilLoadOp;
	/// Operation when storing stencil.
	public StoreOp StencilStoreOp;
	/// Clear stencil value (when StencilLoadOp is Clear).
	public uint32 StencilClearValue;
	/// Make stencil read-only.
	public bool StencilReadOnly;

	public this()
	{
		View = null;
		DepthLoadOp = .Clear;
		DepthStoreOp = .Store;
		DepthClearValue = 1.0f;
		DepthReadOnly = false;
		StencilLoadOp = .Clear;
		StencilStoreOp = .Store;
		StencilClearValue = 0;
		StencilReadOnly = false;
	}

	public this(ITextureView view, LoadOp depthLoadOp = .Clear, StoreOp depthStoreOp = .Store)
	{
		View = view;
		DepthLoadOp = depthLoadOp;
		DepthStoreOp = depthStoreOp;
		DepthClearValue = 1.0f;
		DepthReadOnly = false;
		StencilLoadOp = .Clear;
		StencilStoreOp = .Store;
		StencilClearValue = 0;
		StencilReadOnly = false;
	}
}

/// Describes a render pass.
struct RenderPassDescriptor
{
	/// Color attachments.
	public Span<RenderPassColorAttachment> ColorAttachments;
	/// Depth/stencil attachment (optional).
	public RenderPassDepthStencilAttachment? DepthStencilAttachment;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		ColorAttachments = default;
		DepthStencilAttachment = null;
		Label = default;
	}

	public this(Span<RenderPassColorAttachment> colorAttachments)
	{
		ColorAttachments = colorAttachments;
		DepthStencilAttachment = null;
		Label = default;
	}
}
