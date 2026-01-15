namespace Sedulous.RendererNG;

using System;
using System.Collections;

/// A render pass in the render graph.
class RenderPass
{
	/// Pass name for debugging.
	public String Name ~ delete _;

	/// Type of pass.
	public PassType Type;

	/// Pass flags.
	public PassFlags Flags;

	/// Color attachments for graphics passes.
	public List<ColorAttachment> ColorAttachments = new .() ~ delete _;

	/// Depth-stencil attachment (optional).
	public DepthStencilAttachment? DepthStencil;

	/// Resources read by this pass.
	public List<ResourceRead> Reads = new .() ~ delete _;

	/// Resources written by this pass.
	public List<ResourceWrite> Writes = new .() ~ delete _;

	/// Execution callback for graphics passes.
	public PassExecuteCallback ExecuteCallback ~ delete _;

	/// Execution callback for compute passes.
	public ComputePassExecuteCallback ComputeCallback ~ delete _;

	/// Whether this pass has been culled.
	public bool IsCulled;

	/// Execution order after topological sort.
	public int32 ExecutionOrder;

	/// Passes that must execute before this one.
	public List<PassHandle> Dependencies = new .() ~ delete _;

	public this(StringView name, PassType type)
	{
		Name = new String(name);
		Type = type;
		IsCulled = false;
		ExecutionOrder = -1;
	}

	/// Adds a color attachment.
	public void AddColorAttachment(ColorAttachment attachment)
	{
		ColorAttachments.Add(attachment);
	}

	/// Sets the depth-stencil attachment.
	public void SetDepthStencil(DepthStencilAttachment attachment)
	{
		DepthStencil = attachment;
	}

	/// Adds a resource read dependency.
	public void AddRead(RGResourceHandle handle, ResourceUsage usage)
	{
		Reads.Add(.() { Handle = handle, Usage = usage });
	}

	/// Adds a resource write dependency.
	public void AddWrite(RGResourceHandle handle, ResourceUsage usage)
	{
		Writes.Add(.() { Handle = handle, Usage = usage });
	}

	/// Returns true if this pass writes to any resources.
	public bool HasSideEffects => Writes.Count > 0 || ColorAttachments.Count > 0 || DepthStencil.HasValue;

	/// Returns true if this pass should never be culled.
	public bool NeverCull => (Flags & .NeverCull) != 0;

	/// Gets all output resource handles.
	public void GetOutputs(List<RGResourceHandle> outputs)
	{
		for (let attachment in ColorAttachments)
			outputs.Add(attachment.Handle);

		if (DepthStencil.HasValue)
			outputs.Add(DepthStencil.Value.Handle);

		for (let write in Writes)
			outputs.Add(write.Handle);
	}

	/// Gets all input resource handles.
	public void GetInputs(List<RGResourceHandle> inputs)
	{
		for (let read in Reads)
			inputs.Add(read.Handle);

		// Depth buffer read-only counts as input
		if (DepthStencil.HasValue && DepthStencil.Value.ReadOnly)
			inputs.Add(DepthStencil.Value.Handle);
	}
}
