namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Fluent builder for configuring render passes.
public struct PassBuilder
{
	private RenderGraph mGraph;
	private PassHandle mHandle;

	public this(RenderGraph graph, PassHandle handle)
	{
		mGraph = graph;
		mHandle = handle;
	}

	/// Gets the pass handle.
	public PassHandle Handle => mHandle;

	/// Adds a color attachment to render to.
	public Self WriteColor(RGResourceHandle target, LoadOp loadOp = .Clear, StoreOp storeOp = .Store, Color clearColor = default) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			pass.ColorAttachments.Add(.(target, loadOp, storeOp, clearColor));
		}
		return this;
	}

	/// Adds a depth-stencil attachment.
	public Self WriteDepth(RGResourceHandle target, LoadOp loadOp = .Clear, StoreOp storeOp = .Store, float clearDepth = 1.0f) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			var attachment = RGDepthStencilAttachment(target, loadOp, storeOp);
			attachment.ClearDepth = clearDepth;
			pass.DepthStencil = attachment;
		}
		return this;
	}

	/// Adds a depth attachment for reading only.
	public Self ReadDepth(RGResourceHandle target) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			var attachment = RGDepthStencilAttachment(target, .Load, .Store);
			attachment.ReadOnly = true;
			// Read-only layout cannot use Clear ops - must Load existing content
			attachment.StencilLoadOp = .Load;
			attachment.StencilStoreOp = .Store;
			pass.DepthStencil = attachment;
		}
		return this;
	}

	/// Reads a texture resource.
	public Self ReadTexture(RGResourceHandle texture) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			pass.Reads.Add(texture);
		}
		return this;
	}

	/// Reads a buffer resource.
	public Self ReadBuffer(RGResourceHandle buffer) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			pass.Reads.Add(buffer);
		}
		return this;
	}

	/// Writes to a texture resource (UAV/storage).
	public Self WriteTexture(RGResourceHandle texture) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			pass.Writes.Add(texture);
		}
		return this;
	}

	/// Writes to a buffer resource.
	public Self WriteBuffer(RGResourceHandle buffer) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			pass.Writes.Add(buffer);
		}
		return this;
	}

	/// Adds an explicit dependency on another pass.
	public Self DependsOn(PassHandle other) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			pass.Dependencies.Add(other);
		}
		return this;
	}

	/// Marks this pass as never-cull (e.g., final output).
	public Self NeverCull() mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			pass.NeverCull = true;
		}
		return this;
	}

	/// Sets the execute callback for graphics passes.
	public Self SetExecuteCallback(RenderPassExecuteCallback callback) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			if (pass.ExecuteCallback != null)
				delete pass.ExecuteCallback;
			pass.ExecuteCallback = callback;
		}
		return this;
	}

	/// Sets the execute callback for compute passes.
	public Self SetComputeCallback(ComputePassExecuteCallback callback) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			if (pass.ComputeCallback != null)
				delete pass.ComputeCallback;
			pass.ComputeCallback = callback;
		}
		return this;
	}

	/// Sets the execute callback for copy/transfer passes.
	public Self SetCopyCallback(CopyPassExecuteCallback callback) mut
	{
		if (let pass = mGraph.[Friend]GetPass(mHandle))
		{
			if (pass.CopyCallback != null)
				delete pass.CopyCallback;
			pass.CopyCallback = callback;
		}
		return this;
	}
}
