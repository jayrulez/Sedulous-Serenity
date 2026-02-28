using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Foundation.Mathematics;

namespace Sedulous.RenderGraph;

/// The type of GPU work a pass performs.
public enum PassType
{
	/// Raster pass — renders to color/depth attachments.
	Raster,
	/// Compute pass — dispatches compute work.
	Compute,
	/// Transfer pass — copies, blits, barriers.
	Transfer
}

/// Callback for executing a raster pass.
public delegate void RasterPassExecute(IRenderPassEncoder encoder);

/// Callback for executing a compute pass.
public delegate void ComputePassExecute(IComputePassEncoder encoder);

/// Callback for executing a transfer pass.
public delegate void TransferPassExecute(ICommandEncoder encoder);

/// A color attachment configuration for a raster pass.
public struct PassColorAttachment
{
	/// The resource handle for the render target.
	public ResourceHandle Handle;
	/// Operation when loading the attachment.
	public LoadOp LoadOp;
	/// Operation when storing the attachment.
	public StoreOp StoreOp;
	/// Clear color (when LoadOp is Clear).
	public Color ClearColor;

	public this(ResourceHandle handle, LoadOp loadOp = .Clear, StoreOp storeOp = .Store)
	{
		Handle = handle;
		LoadOp = loadOp;
		StoreOp = storeOp;
		ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f);
	}
}

/// A depth/stencil attachment configuration for a raster pass.
public struct PassDepthStencilAttachment
{
	/// The resource handle for the depth/stencil buffer.
	public ResourceHandle Handle;
	/// Operation when loading depth.
	public LoadOp DepthLoadOp;
	/// Operation when storing depth.
	public StoreOp DepthStoreOp;
	/// Clear depth value.
	public float DepthClearValue;
	/// Whether the depth attachment is read-only.
	public bool ReadOnly;

	public this(ResourceHandle handle, LoadOp depthLoadOp = .Clear, StoreOp depthStoreOp = .Store)
	{
		Handle = handle;
		DepthLoadOp = depthLoadOp;
		DepthStoreOp = depthStoreOp;
		DepthClearValue = 1.0f;
		ReadOnly = false;
	}
}

/// Internal representation of a render graph pass.
///
/// Passes track their resource dependencies (reads/writes) and contain
/// the execute callback that records GPU commands.
///
internal class RenderGraphPass
{
	/// Debug name for this pass.
	public String Name = new .() ~ delete _;

	/// The type of GPU work this pass performs.
	public PassType Type;

	/// Index of this pass in the graph's pass list.
	public int32 Index;

	// ===== Resource Dependencies =====

	/// Resources read by this pass (with version).
	public List<ResourceHandle> Reads = new .() ~ delete _;

	/// Resources written by this pass (with version).
	public List<ResourceHandle> Writes = new .() ~ delete _;

	// ===== Attachments (Raster only) =====

	/// Color attachment configurations.
	public List<PassColorAttachment> ColorAttachments = new .() ~ delete _;

	/// Depth/stencil attachment configuration (null if none).
	public PassDepthStencilAttachment? DepthStencilAttachment;

	// ===== Execution =====

	/// Raster pass callback.
	public RasterPassExecute RasterExecute ~ delete _;

	/// Compute pass callback.
	public ComputePassExecute ComputeExecute ~ delete _;

	/// Transfer pass callback.
	public TransferPassExecute TransferExecute ~ delete _;

	// ===== Compilation State =====

	/// Reference count for culling (0 = no outputs are used, can be culled).
	public int32 RefCount;

	/// Whether this pass was culled during compilation.
	public bool Culled;

	/// Whether this pass has a side effect (always kept, never culled).
	public bool HasSideEffect;
}
