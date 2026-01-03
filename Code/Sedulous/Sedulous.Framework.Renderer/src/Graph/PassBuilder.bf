namespace Sedulous.Framework.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Builder for declaring render pass dependencies and configuration.
struct PassBuilder
{
	private RenderGraph mGraph;
	private RenderPass mPass;

	internal this(RenderGraph graph, RenderPass pass)
	{
		mGraph = graph;
		mPass = pass;
	}

	/// Declares that this pass reads from a resource.
	public Self Read(ResourceHandle handle, TextureLayout layout = .ShaderReadOnly) mut
	{
		mPass.Reads.Add(.(handle, .Read, layout));
		mGraph.[Friend]RecordResourceUsage(handle, mPass.Index);
		return this;
	}

	/// Declares that this pass writes to a resource.
	public Self Write(ResourceHandle handle, TextureLayout layout = .General) mut
	{
		mPass.Writes.Add(.(handle, .Write, layout));
		mGraph.[Friend]RecordResourceUsage(handle, mPass.Index);
		return this;
	}

	/// Declares that this pass reads and writes to a resource.
	public Self ReadWrite(ResourceHandle handle, TextureLayout layout = .General) mut
	{
		mPass.Reads.Add(.(handle, .ReadWrite, layout));
		mPass.Writes.Add(.(handle, .ReadWrite, layout));
		mGraph.[Friend]RecordResourceUsage(handle, mPass.Index);
		return this;
	}

	/// Sets a color attachment for this graphics pass.
	public Self SetColorAttachment(int slot, ResourceHandle target, LoadOp load = .Clear, StoreOp store = .Store, Color? clearColor = null) mut
	{
		// Ensure we have enough slots
		while (mPass.ColorAttachments.Count <= slot)
			mPass.ColorAttachments.Add(.(.Invalid));

		var attachment = PassColorAttachment(target, load, store);
		if (clearColor.HasValue)
			attachment.ClearColor = clearColor.Value;

		mPass.ColorAttachments[slot] = attachment;

		// Color attachments are written to
		mPass.Writes.Add(.(target, .Write, .ColorAttachment));
		mGraph.[Friend]RecordResourceUsage(target, mPass.Index);

		return this;
	}

	/// Sets the depth attachment for this graphics pass.
	public Self SetDepthAttachment(ResourceHandle target, LoadOp load = .Clear, StoreOp store = .Store, float clearDepth = 0.0f) mut
	{
		var attachment = PassDepthAttachment(target, load, store);
		attachment.ClearDepth = clearDepth;
		mPass.DepthAttachment = attachment;

		// Depth attachment is written to
		mPass.Writes.Add(.(target, .Write, .DepthStencilAttachment));
		mGraph.[Friend]RecordResourceUsage(target, mPass.Index);

		return this;
	}

	/// Sets the execution callback for this pass.
	public Self SetExecute(PassExecuteDelegate execute) mut
	{
		mPass.Execute = execute;
		return this;
	}
}
