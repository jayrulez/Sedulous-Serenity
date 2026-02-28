using System;
using Sedulous.RHI;
using Sedulous.Foundation.Mathematics;

namespace Sedulous.RenderGraph;

using internal Sedulous.RenderGraph;

/// Builder API for declaring resource dependencies within a pass.
///
/// The builder is passed to the setup callback of AddRasterPass/AddComputePass/
/// AddTransferPass. It allows the pass to declare which resources it reads,
/// writes, and uses as attachments.
///
public struct RenderGraphBuilder
{
	private RenderGraph mGraph;
	private RenderGraphPass mPass;

	internal this(RenderGraph graph, RenderGraphPass pass)
	{
		mGraph = graph;
		mPass = pass;
	}

	/// Declares that this pass reads a resource.
	/// Returns the handle (same version) for the read dependency.
	public ResourceHandle Read(ResourceHandle handle)
	{
		mPass.Reads.Add(handle);
		mGraph.[Friend]TrackResourceUsage(handle.Index, mPass.Index);
		return handle;
	}

	/// Declares that this pass writes to a resource.
	/// Returns a new handle with an incremented version.
	public ResourceHandle Write(ResourceHandle handle)
	{
		let newHandle = mGraph.[Friend]IncrementVersion(handle);
		mPass.Writes.Add(newHandle);
		mGraph.[Friend]TrackResourceUsage(handle.Index, mPass.Index);
		return newHandle;
	}

	/// Declares a color attachment for a raster pass.
	/// Implicitly declares a write dependency.
	public ResourceHandle SetColorAttachment(int index, ResourceHandle handle,
		LoadOp loadOp = .Clear, Color? clearColor = null)
	{
		let newHandle = mGraph.[Friend]IncrementVersion(handle);
		let attachment = PassColorAttachment(newHandle, loadOp)
		{
			ClearColor = clearColor ?? .(0.0f, 0.0f, 0.0f, 1.0f)
		};

		// Ensure the list is large enough
		while (mPass.ColorAttachments.Count <= index)
			mPass.ColorAttachments.Add(default);
		mPass.ColorAttachments[index] = attachment;

		mPass.Writes.Add(newHandle);
		mGraph.[Friend]TrackResourceUsage(handle.Index, mPass.Index);
		return newHandle;
	}

	/// Declares a depth/stencil attachment for a raster pass.
	/// Implicitly declares a write dependency (unless read-only).
	public ResourceHandle SetDepthStencilAttachment(ResourceHandle handle,
		LoadOp loadOp = .Clear, float clearDepth = 1.0f, bool readOnly = false)
	{
		ResourceHandle resultHandle;
		if (readOnly)
		{
			resultHandle = handle;
			mPass.Reads.Add(handle);
		}
		else
		{
			resultHandle = mGraph.[Friend]IncrementVersion(handle);
			mPass.Writes.Add(resultHandle);
		}

		mPass.DepthStencilAttachment = PassDepthStencilAttachment(resultHandle, loadOp)
		{
			DepthClearValue = clearDepth,
			ReadOnly = readOnly
		};

		mGraph.[Friend]TrackResourceUsage(handle.Index, mPass.Index);
		return resultHandle;
	}

	/// Marks this pass as having a side effect (e.g. presenting to screen).
	/// Side-effect passes are never culled.
	public void SideEffect()
	{
		mPass.HasSideEffect = true;
	}
}
