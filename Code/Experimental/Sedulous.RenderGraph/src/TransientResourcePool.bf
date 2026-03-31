namespace Sedulous.RenderGraph;

using System;
using System.Collections;
using System.Diagnostics;
using Sedulous.RHI;
using static Sedulous.RHI.TextureFormatExt;

/// Manages pooled GPU resources for transient allocations.
/// Resources are reused across frames and aliased within a frame
/// when lifetimes don't overlap.
class TransientResourcePool
{
	/// A pooled texture allocation.
	public class PooledTexture
	{
		public RGTextureDesc Desc;
		public ITexture Texture;
		public ITextureView View;
		/// Which frame-local assignment slot is using this pooled resource (-1 = free).
		public int32 AssignedSlot = -1;
		/// Last-use pass index for the current frame assignment.
		public int32 LastUsePass = -1;
		/// Tracks the resource state after the last frame's execution.
		public ResourceState LastKnownState = .Undefined;
	}

	/// A pooled buffer allocation.
	public class PooledBuffer
	{
		public RGBufferDesc Desc;
		public IBuffer Buffer;
		/// Which frame-local assignment slot is using this pooled resource (-1 = free).
		public int32 AssignedSlot = -1;
		/// Last-use pass index for the current frame assignment.
		public int32 LastUsePass = -1;
		/// Tracks the resource state after the last frame's execution.
		public ResourceState LastKnownState = .Undefined;
	}

	/// An aliasing assignment: maps a transient resource to a pool slot.
	public struct AliasingAssignment
	{
		public uint32 ResourceIndex;
		public int32 PoolIndex;
		public bool IsTexture;
	}

	private List<PooledTexture> mTexturePool = new .() ~ DeleteContainerAndItems!(_);
	private List<PooledBuffer> mBufferPool = new .() ~ DeleteContainerAndItems!(_);

	/// Current frame's aliasing assignments.
	private List<AliasingAssignment> mAssignments = new .() ~ delete _;

	/// Computes aliasing assignments for all transient resources.
	/// Resources are sorted by size (largest first) and greedily assigned to pool slots,
	/// reusing a slot if its previous occupant's lastUse < current resource's firstUse.
	public void ComputeAliasing(List<RenderGraphResource> resources, List<RenderGraphPass> scheduledPasses)
	{
		mAssignments.Clear();

		// Reset all pool slots to free
		for (let pt in mTexturePool)
		{
			pt.AssignedSlot = -1;
			pt.LastUsePass = -1;
		}
		for (let pb in mBufferPool)
		{
			pb.AssignedSlot = -1;
			pb.LastUsePass = -1;
		}

		// Collect transient resources with valid lifetimes
		let transients = scope List<RenderGraphResource>();
		for (let resource in resources)
		{
			if (!resource.IsImported && resource.FirstUsePass >= 0)
				transients.Add(resource);
		}

		// Sort by size (largest first) for better bin packing
		transients.Sort(scope (a, b) =>
		{
			let sizeA = GetResourceSize(a);
			let sizeB = GetResourceSize(b);
			return sizeB <=> sizeA;
		});

		// Greedy assignment
		for (let resource in transients)
		{
			if (resource.IsTexture)
				AssignTexture(resource);
			else
				AssignBuffer(resource);
		}
	}

	/// Allocates actual GPU resources for all assignments that don't have backing yet.
	/// Must be called with a valid device.
	public void AllocateGpuResources(IDevice device)
	{
		if (device == null) return;

		for (let pt in mTexturePool)
		{
			if (pt.Texture == null && pt.AssignedSlot >= 0)
			{
				// Determine usage flags from format
				TextureUsage usage;
				if (pt.Desc.Format.IsDepthStencil())
					usage = .DepthStencil | .Sampled | .CopySrc | .CopyDst;
				else
					usage = .Sampled | .RenderTarget | .CopySrc | .CopyDst | .Storage;

				let desc = TextureDesc.Tex2D(pt.Desc.Format, pt.Desc.Width, pt.Desc.Height,
					usage, pt.Desc.MipLevelCount, pt.Desc.Name);

				if (device.CreateTexture(desc) case .Ok(let tex))
				{
					pt.Texture = tex;
					if (device.CreateTextureView(tex, .()) case .Ok(let view))
						pt.View = view;
					pt.LastKnownState = tex.InitialState;
				}
			}
		}

		for (let pb in mBufferPool)
		{
			if (pb.Buffer == null && pb.AssignedSlot >= 0)
			{
				let desc = BufferDesc()
				{
					Size = pb.Desc.Size,
					Usage = pb.Desc.Usage | .CopySrc | .CopyDst,
					Label = pb.Desc.Name
				};

				if (device.CreateBuffer(desc) case .Ok(let buf))
					pb.Buffer = buf;
			}
		}
	}

	/// Maps a transient resource to its pooled GPU texture.
	public PooledTexture GetPooledTexture(uint32 resourceIndex)
	{
		for (let assignment in mAssignments)
		{
			if (assignment.ResourceIndex == resourceIndex && assignment.IsTexture)
			{
				if (assignment.PoolIndex >= 0 && assignment.PoolIndex < mTexturePool.Count)
					return mTexturePool[assignment.PoolIndex];
			}
		}
		return null;
	}

	/// Maps a transient resource to its pooled GPU buffer.
	public PooledBuffer GetPooledBuffer(uint32 resourceIndex)
	{
		for (let assignment in mAssignments)
		{
			if (assignment.ResourceIndex == resourceIndex && !assignment.IsTexture)
			{
				if (assignment.PoolIndex >= 0 && assignment.PoolIndex < mBufferPool.Count)
					return mBufferPool[assignment.PoolIndex];
			}
		}
		return null;
	}

	/// Destroys all pooled GPU resources. Call when shutting down.
	public void DestroyAll(IDevice device)
	{
		if (device == null) return;

		for (let pt in mTexturePool)
		{
			if (pt.View != null)
				device.DestroyTextureView(ref pt.View);
			if (pt.Texture != null)
				device.DestroyTexture(ref pt.Texture);
		}

		for (let pb in mBufferPool)
		{
			if (pb.Buffer != null)
				device.DestroyBuffer(ref pb.Buffer);
		}
	}

	/// Number of aliasing assignments this frame.
	public int AssignmentCount => mAssignments.Count;

	/// Gets an assignment by index (for testing).
	public AliasingAssignment GetAssignment(int index) => mAssignments[index];

	/// Number of pooled textures.
	public int TexturePoolSize => mTexturePool.Count;

	/// Number of pooled buffers.
	public int BufferPoolSize => mBufferPool.Count;

	// =========================================================================
	// Private implementation
	// =========================================================================

	private void AssignTexture(RenderGraphResource resource)
	{
		// Try to reuse an existing pool slot with matching descriptor
		// whose previous occupant's lifetime doesn't overlap
		for (int i = 0; i < mTexturePool.Count; i++)
		{
			let pooled = mTexturePool[i];
			if (TextureDescMatches(pooled.Desc, resource.TextureDesc) &&
				(pooled.AssignedSlot < 0 || pooled.LastUsePass < resource.FirstUsePass))
			{
				// Reuse this slot
				pooled.AssignedSlot = (int32)mAssignments.Count;
				pooled.LastUsePass = resource.LastUsePass;
				mAssignments.Add(.()
				{
					ResourceIndex = resource.Index,
					PoolIndex = (int32)i,
					IsTexture = true
				});
				return;
			}
		}

		// No reusable slot — create a new pool entry
		let pooled = new PooledTexture();
		pooled.Desc = resource.TextureDesc;
		pooled.AssignedSlot = (int32)mAssignments.Count;
		pooled.LastUsePass = resource.LastUsePass;
		let poolIdx = (int32)mTexturePool.Count;
		mTexturePool.Add(pooled);

		mAssignments.Add(.()
		{
			ResourceIndex = resource.Index,
			PoolIndex = poolIdx,
			IsTexture = true
		});
	}

	private void AssignBuffer(RenderGraphResource resource)
	{
		for (int i = 0; i < mBufferPool.Count; i++)
		{
			let pooled = mBufferPool[i];
			if (BufferDescMatches(pooled.Desc, resource.BufferDesc) &&
				(pooled.AssignedSlot < 0 || pooled.LastUsePass < resource.FirstUsePass))
			{
				pooled.AssignedSlot = (int32)mAssignments.Count;
				pooled.LastUsePass = resource.LastUsePass;
				mAssignments.Add(.()
				{
					ResourceIndex = resource.Index,
					PoolIndex = (int32)i,
					IsTexture = false
				});
				return;
			}
		}

		let pooled = new PooledBuffer();
		pooled.Desc = resource.BufferDesc;
		pooled.AssignedSlot = (int32)mAssignments.Count;
		pooled.LastUsePass = resource.LastUsePass;
		let poolIdx = (int32)mBufferPool.Count;
		mBufferPool.Add(pooled);

		mAssignments.Add(.()
		{
			ResourceIndex = resource.Index,
			PoolIndex = poolIdx,
			IsTexture = false
		});
	}

	private static bool TextureDescMatches(RGTextureDesc a, RGTextureDesc b)
	{
		return a.Format == b.Format &&
			a.Width == b.Width &&
			a.Height == b.Height &&
			a.ArrayLayerCount == b.ArrayLayerCount &&
			a.MipLevelCount == b.MipLevelCount &&
			a.SampleCount == b.SampleCount;
	}

	private static bool BufferDescMatches(RGBufferDesc a, RGBufferDesc b)
	{
		return a.Size == b.Size && a.Usage == b.Usage;
	}

	private static uint64 GetResourceSize(RenderGraphResource resource)
	{
		if (resource.IsTexture)
		{
			let d = resource.TextureDesc;
			// Rough size estimate for sorting
			return (uint64)d.Width * d.Height * d.ArrayLayerCount * d.MipLevelCount * d.SampleCount * 4;
		}
		else
		{
			return resource.BufferDesc.Size;
		}
	}
}
