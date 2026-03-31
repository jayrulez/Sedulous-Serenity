namespace Sedulous.RenderGraph;

using System;
using System.Collections;
using Sedulous.RHI;

/// Callback signature for pass execution.
/// Receives the command encoder and the resource registry for resolving handles to GPU resources.
typealias RGExecuteCallback = delegate void(ICommandEncoder encoder, ResourceRegistry registry);

/// A single pass in the render graph.
/// Stores all resource access declarations and the execute callback.
class RenderGraphPass
{
	public String Name ~ delete _;
	public QueueType QueueType;
	public int32 Index;

	/// All resource accesses declared by this pass.
	public List<RGResourceAccess> Accesses = new .() ~ delete _;

	/// Execute callback set by the user during pass setup.
	public RGExecuteCallback ExecuteCallback ~ delete _;

	/// If true, this pass has side effects and must not be culled
	/// even if no other pass reads its outputs.
	public bool HasSideEffects;

	/// Set during scheduling — whether this pass survived culling.
	public bool IsCulled;

	/// Runtime condition — if set and returns false, the pass is skipped during execution.
	/// Unlike culling, conditional passes still participate in scheduling and barrier solving.
	public delegate bool() Condition ~ delete _;

	/// Scheduled execution order (set by PassScheduler).
	public int32 ScheduledOrder = -1;

	/// Render target attachments declared by this pass (slot → resource index).
	public List<RGRenderTarget> RenderTargets = new .() ~ delete _;

	/// Depth/stencil attachment declared by this pass.
	public RGDepthStencil? DepthStencil;

	public this(StringView name, QueueType queueType, int32 index)
	{
		Name = new String(name);
		QueueType = queueType;
		Index = index;
	}

	/// Finds all resources written by this pass.
	public void GetWrittenResources(List<RGResource> outResources)
	{
		for (let access in Accesses)
		{
			if (access.IsWrite)
				outResources.Add(access.Resource);
		}
	}

	/// Finds all resources read by this pass.
	public void GetReadResources(List<RGResource> outResources)
	{
		for (let access in Accesses)
		{
			if (access.IsRead)
				outResources.Add(access.Resource);
		}
	}
}

/// Render target attachment info for a pass.
struct RGRenderTarget
{
	public uint32 Slot;
	public RGTexture Texture;
	public LoadOp LoadOp;
	public StoreOp StoreOp;
	public ClearColor ClearColor;
}

/// Depth/stencil attachment info for a pass.
struct RGDepthStencil
{
	public RGTexture Texture;
	public LoadOp DepthLoadOp;
	public StoreOp DepthStoreOp;
	public float DepthClearValue;
	public bool DepthReadOnly;
	public LoadOp StencilLoadOp;
	public StoreOp StencilStoreOp;
	public uint8 StencilClearValue;
	public bool StencilReadOnly;
}
