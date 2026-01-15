namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Fluent builder for configuring render passes.
struct PassBuilder
{
	private RenderGraph mGraph;
	private PassHandle mPassHandle;

	public this(RenderGraph graph, PassHandle handle)
	{
		mGraph = graph;
		mPassHandle = handle;
	}

	/// Returns the pass handle.
	public PassHandle Handle => mPassHandle;

	/// Sets a color attachment.
	public Self SetColorAttachment(int slot, RGResourceHandle handle, LoadOp loadOp = .Clear, StoreOp storeOp = .Store)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			// Ensure we have enough slots
			while (pass.ColorAttachments.Count <= slot)
				pass.ColorAttachments.Add(.());

			ColorAttachment attachment;
			attachment.Handle = handle;
			attachment.LoadOp = loadOp;
			attachment.StoreOp = storeOp;
			attachment.ClearColor = .Black;
			attachment.MipLevel = 0;
			attachment.ArrayLayer = 0;

			pass.ColorAttachments[slot] = attachment;

			// Register write dependency
			pass.AddWrite(handle, .RenderTarget);
		}
		return this;
	}

	/// Sets a color attachment with clear color.
	public Self SetColorAttachment(int slot, RGResourceHandle handle, Color clearColor, LoadOp loadOp = .Clear, StoreOp storeOp = .Store)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			while (pass.ColorAttachments.Count <= slot)
				pass.ColorAttachments.Add(.());

			ColorAttachment attachment;
			attachment.Handle = handle;
			attachment.LoadOp = loadOp;
			attachment.StoreOp = storeOp;
			attachment.ClearColor = clearColor;
			attachment.MipLevel = 0;
			attachment.ArrayLayer = 0;

			pass.ColorAttachments[slot] = attachment;
			pass.AddWrite(handle, .RenderTarget);
		}
		return this;
	}

	/// Sets the depth-stencil attachment.
	public Self SetDepthAttachment(RGResourceHandle handle, LoadOp loadOp = .Clear, StoreOp storeOp = .Store)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			DepthStencilAttachment attachment;
			attachment.Handle = handle;
			attachment.DepthLoadOp = loadOp;
			attachment.DepthStoreOp = storeOp;
			attachment.StencilLoadOp = .DontCare;
			attachment.StencilStoreOp = .Discard;
			attachment.ClearDepth = 1.0f;
			attachment.ClearStencil = 0;
			attachment.ReadOnly = false;

			pass.SetDepthStencil(attachment);
			pass.AddWrite(handle, .DepthStencil);
		}
		return this;
	}

	/// Sets the depth-stencil attachment with clear values.
	public Self SetDepthAttachment(RGResourceHandle handle, float clearDepth, LoadOp loadOp = .Clear, StoreOp storeOp = .Store)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			DepthStencilAttachment attachment;
			attachment.Handle = handle;
			attachment.DepthLoadOp = loadOp;
			attachment.DepthStoreOp = storeOp;
			attachment.StencilLoadOp = .DontCare;
			attachment.StencilStoreOp = .Discard;
			attachment.ClearDepth = clearDepth;
			attachment.ClearStencil = 0;
			attachment.ReadOnly = false;

			pass.SetDepthStencil(attachment);
			pass.AddWrite(handle, .DepthStencil);
		}
		return this;
	}

	/// Sets a read-only depth attachment (for depth testing without writing).
	public Self SetDepthAttachmentReadOnly(RGResourceHandle handle)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			DepthStencilAttachment attachment;
			attachment.Handle = handle;
			attachment.DepthLoadOp = .Load;
			attachment.DepthStoreOp = .Discard;
			attachment.StencilLoadOp = .DontCare;
			attachment.StencilStoreOp = .Discard;
			attachment.ClearDepth = 1.0f;
			attachment.ClearStencil = 0;
			attachment.ReadOnly = true;

			pass.SetDepthStencil(attachment);
			pass.AddRead(handle, .DepthStencil);
		}
		return this;
	}

	/// Declares a texture read dependency.
	public Self ReadTexture(RGResourceHandle handle, ResourceUsage usage = .ShaderRead)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			pass.AddRead(handle, usage);
		}
		return this;
	}

	/// Declares a buffer read dependency.
	public Self ReadBuffer(RGResourceHandle handle, ResourceUsage usage = .ShaderRead)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			pass.AddRead(handle, usage);
		}
		return this;
	}

	/// Declares a texture write dependency.
	public Self WriteTexture(RGResourceHandle handle, ResourceUsage usage = .UnorderedAccess)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			pass.AddWrite(handle, usage);
		}
		return this;
	}

	/// Declares a buffer write dependency.
	public Self WriteBuffer(RGResourceHandle handle, ResourceUsage usage = .UnorderedAccess)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			pass.AddWrite(handle, usage);
		}
		return this;
	}

	/// Sets pass flags.
	public Self SetFlags(PassFlags flags)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			pass.Flags = flags;
		}
		return this;
	}

	/// Sets the execution callback for graphics passes.
	public Self SetExecute(PassExecuteCallback callback)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			if (pass.ExecuteCallback != null)
				delete pass.ExecuteCallback;
			pass.ExecuteCallback = callback;
		}
		return this;
	}

	/// Sets the execution callback for compute passes.
	public Self SetComputeExecute(ComputePassExecuteCallback callback)
	{
		if (let pass = mGraph.[Friend]GetPass(mPassHandle))
		{
			if (pass.ComputeCallback != null)
				delete pass.ComputeCallback;
			pass.ComputeCallback = callback;
		}
		return this;
	}
}
