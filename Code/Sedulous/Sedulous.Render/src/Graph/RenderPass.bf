namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Type of render pass.
public enum RenderPassType : uint8
{
	Graphics,
	Compute,
	Copy
}

/// Color attachment for a render pass.
public struct RGColorAttachment
{
	public RGResourceHandle Handle;
	public LoadOp LoadOp;
	public StoreOp StoreOp;
	public Color ClearColor;

	public this(RGResourceHandle handle, LoadOp loadOp = .Clear, StoreOp storeOp = .Store, Color clearColor = default)
	{
		Handle = handle;
		LoadOp = loadOp;
		StoreOp = storeOp;
		ClearColor = clearColor;
	}
}

/// Depth-stencil attachment for a render pass.
public struct RGDepthStencilAttachment
{
	public RGResourceHandle Handle;
	public LoadOp DepthLoadOp;
	public StoreOp DepthStoreOp;
	public LoadOp StencilLoadOp;
	public StoreOp StencilStoreOp;
	public float ClearDepth;
	public uint8 ClearStencil;
	public bool ReadOnly;

	public this(RGResourceHandle handle, LoadOp depthLoadOp = .Clear, StoreOp depthStoreOp = .Store)
	{
		Handle = handle;
		DepthLoadOp = depthLoadOp;
		DepthStoreOp = depthStoreOp;
		StencilLoadOp = .Clear;
		StencilStoreOp = .Discard;
		ClearDepth = 1.0f;
		ClearStencil = 0;
		ReadOnly = false;
	}
}

/// Callback for executing a graphics render pass.
public delegate void RenderPassExecuteCallback(IRenderPassEncoder encoder);

/// Callback for executing a compute pass.
public delegate void ComputePassExecuteCallback(IComputePassEncoder encoder);

/// Callback for executing a copy/transfer pass.
public delegate void CopyPassExecuteCallback(ICommandEncoder encoder);

/// A render pass in the render graph.
public class RenderPass
{
	/// Pass name for debugging.
	public String Name = new .() ~ delete _;

	/// Pass type.
	public RenderPassType Type;

	/// Color attachments.
	public List<RGColorAttachment> ColorAttachments = new .() ~ delete _;

	/// Depth-stencil attachment.
	public RGDepthStencilAttachment? DepthStencil;

	/// Resources read by this pass.
	public List<RGResourceHandle> Reads = new .() ~ delete _;

	/// Resources written by this pass.
	public List<RGResourceHandle> Writes = new .() ~ delete _;

	/// Explicit dependencies on other passes.
	public List<PassHandle> Dependencies = new .() ~ delete _;

	/// Whether this pass has been culled.
	public bool IsCulled;

	/// Whether this pass should never be culled (e.g., presents to screen).
	public bool NeverCull;

	/// Execution order after topological sort.
	public int32 ExecutionOrder = -1;

	/// Graphics pass execute callback.
	public RenderPassExecuteCallback ExecuteCallback ~ delete _;

	/// Compute pass execute callback.
	public ComputePassExecuteCallback ComputeCallback ~ delete _;

	/// Copy pass execute callback.
	public CopyPassExecuteCallback CopyCallback ~ delete _;

	public this(StringView name, RenderPassType type)
	{
		Name.Set(name);
		Type = type;
	}

	/// Gets all input resources.
	public void GetInputs(List<RGResourceHandle> outInputs)
	{
		outInputs.AddRange(Reads);

		// Color attachments with Load are also inputs
		for (let attachment in ColorAttachments)
		{
			if (attachment.LoadOp == .Load)
				outInputs.Add(attachment.Handle);
		}

		// Depth attachment with Load is also input
		if (DepthStencil.HasValue && DepthStencil.Value.DepthLoadOp == .Load)
			outInputs.Add(DepthStencil.Value.Handle);
	}

	/// Gets all output resources.
	public void GetOutputs(List<RGResourceHandle> outOutputs)
	{
		outOutputs.AddRange(Writes);

		// Color attachments with Store are outputs
		for (let attachment in ColorAttachments)
		{
			if (attachment.StoreOp == .Store)
				outOutputs.Add(attachment.Handle);
		}

		// Depth attachment with Store is output
		if (DepthStencil.HasValue && DepthStencil.Value.DepthStoreOp == .Store)
			outOutputs.Add(DepthStencil.Value.Handle);
	}
}
