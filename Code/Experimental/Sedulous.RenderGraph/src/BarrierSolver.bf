namespace Sedulous.RenderGraph;

using System;
using System.Collections;
using System.Diagnostics;
using Sedulous.RHI;

/// Walks the scheduled pass list and inserts barriers between passes
/// based on declared access patterns.
///
/// Algorithm:
/// 1. For each resource, track the "last write" pass and "last known state."
/// 2. Before each pass, for each resource it accesses:
///    - Determine the required ResourceState from the access type.
///    - If the required state differs from the last known state, insert a barrier.
///    - If same state but write-after-write, insert an execution barrier.
/// 3. Batch all barriers for a pass into a single BarrierGroup.
class BarrierSolver
{
	/// Per-resource tracking state.
	private struct ResourceTrack
	{
		public ResourceState CurrentState;
		public int32 LastWritePass;
		public bool WasWritten;
		public QueueType LastQueue;
	}

	/// Barriers to insert before a given pass.
	public struct PassBarriers
	{
		public int32 PassIndex;
		public List<TextureBarrier> TextureBarriers;
		public List<BufferBarrier> BufferBarriers;
		public List<MemoryBarrier> MemoryBarriers;
	}

	/// Solves barriers for all scheduled passes.
	/// Returns a list of PassBarriers, one per scheduled pass that needs barriers.
	public static void Solve(
		List<RenderGraphPass> scheduledPasses,
		List<RenderGraphResource> resources,
		List<PassBarriers> outBarriers)
	{
		// Build resource state tracking map
		let trackMap = scope Dictionary<uint32, ResourceTrack>();
		// Build index→resource lookup for O(1) access
		let resourceMap = scope Dictionary<uint32, RenderGraphResource>();

		for (let resource in resources)
		{
			trackMap[resource.Index] = .()
			{
				CurrentState = resource.InitialState,
				LastWritePass = -1,
				WasWritten = false,
				LastQueue = .Graphics
			};
			resourceMap[resource.Index] = resource;
		}

		for (int passIdx = 0; passIdx < scheduledPasses.Count; passIdx++)
		{
			let pass = scheduledPasses[passIdx];
			List<TextureBarrier> texBarriers = null;
			List<BufferBarrier> bufBarriers = null;
			List<MemoryBarrier> memBarriers = null;

			for (let access in pass.Accesses)
			{
				let resourceIdx = access.Resource.Index;
				ResourceTrack track;
				if (!trackMap.TryGetValue(resourceIdx, out track))
					continue;

				let requiredState = access.ToResourceState();
				let needsTransition = track.CurrentState != requiredState;

				// Write-after-write on same state needs an execution barrier
				let writeAfterWrite = !needsTransition && access.IsWrite && track.WasWritten;

				if (needsTransition)
				{
					RenderGraphResource rgResource;
					if (!resourceMap.TryGetValue(resourceIdx, out rgResource))
						continue;

					if (rgResource.IsTexture)
					{
						if (texBarriers == null)
							texBarriers = new List<TextureBarrier>();

						texBarriers.Add(.()
						{
							Texture = rgResource.ImportedTexture,
							OldState = track.CurrentState,
							NewState = requiredState
						});
					}
					else
					{
						if (bufBarriers == null)
							bufBarriers = new List<BufferBarrier>();

						bufBarriers.Add(.()
						{
							Buffer = rgResource.ImportedBuffer,
							OldState = track.CurrentState,
							NewState = requiredState
						});
					}

					track.CurrentState = requiredState;
				}
				else if (writeAfterWrite)
				{
					// Same state write-after-write: insert a memory barrier
					// to ensure the first write completes before the second begins
					if (memBarriers == null)
						memBarriers = new List<MemoryBarrier>();

					memBarriers.Add(.()
					{
						OldState = track.CurrentState,
						NewState = requiredState
					});
				}

				if (access.IsWrite)
				{
					track.LastWritePass = (int32)passIdx;
					track.WasWritten = true;
				}

				trackMap[resourceIdx] = track;
			}

			if (texBarriers != null || bufBarriers != null || memBarriers != null)
			{
				outBarriers.Add(.()
				{
					PassIndex = (int32)passIdx,
					TextureBarriers = texBarriers,
					BufferBarriers = bufBarriers,
					MemoryBarriers = memBarriers
				});
			}
		}
	}

	/// Frees barrier lists allocated by Solve().
	public static void FreeBarriers(List<PassBarriers> barriers)
	{
		for (var pb in barriers)
		{
			delete pb.TextureBarriers;
			delete pb.BufferBarriers;
			delete pb.MemoryBarriers;
		}
		barriers.Clear();
	}
}
