namespace Sedulous.RenderGraph;

using System;
using System.Collections;
using System.Diagnostics;
using Sedulous.RHI;

/// Callback signature for pass setup. Receives a RenderGraphBuilder to declare resource accesses.
typealias RGSetupCallback = delegate void(RenderGraphBuilder builder);

/// A cross-queue synchronization point.
/// The source queue signals a fence value after its pass; the destination queue waits before its pass.
struct QueueSyncPoint
{
	public QueueType SrcQueue;
	public QueueType DstQueue;
	/// Scheduled pass index of the source (signal after this pass's queue submits).
	public int32 SrcPassIndex;
	/// Scheduled pass index of the destination (wait before this pass's queue submits).
	public int32 DstPassIndex;
	/// Timeline fence value for this sync point.
	public uint64 FenceValue;
}

/// Main render graph orchestrator.
/// Manages pass declarations, resource tracking, compilation, and execution.
class RenderGraph
{
	/// All passes declared this frame.
	private List<RenderGraphPass> mPasses = new .() ~ DeleteContainerAndItems!(_);

	/// All resources (imported + transient) declared this frame.
	private List<RenderGraphResource> mResources = new .() ~ DeleteContainerAndItems!(_);

	/// Resource index counter (0 is reserved for invalid).
	private uint32 mNextResourceIndex = 1;

	/// Scheduled pass order after compilation.
	private List<RenderGraphPass> mScheduledPasses = new .() ~ delete _;

	/// Resource registry for pass execution.
	private ResourceRegistry mRegistry ~ delete _;

	/// Reusable builder instance.
	private RenderGraphBuilder mBuilder ~ delete _;

	/// Solved barriers per pass (populated during Compile).
	private List<BarrierSolver.PassBarriers> mPassBarriers = new .() ~ { BarrierSolver.FreeBarriers(_); delete _; }

	/// Transient resource pool — persists across frames for reuse.
	private TransientResourcePool mPool = new .() ~ delete _;

	/// Per-queue command pools created during Execute (cleaned up on Reset).
	private ICommandPool[3] mCommandPools; // indexed by QueueType ordinal

	/// Timeline fence for cross-queue synchronization.
	private IFence mTimelineFence;
	private uint64 mFenceValue;

	/// Cross-queue sync points computed during Compile.
	private List<QueueSyncPoint> mSyncPoints = new .() ~ delete _;

	/// Device reference for cleanup.
	private IDevice mDevice;

	/// Whether Compile() has been called this frame.
	private bool mIsCompiled;

	public this()
	{
		mRegistry = new ResourceRegistry(this);
		mBuilder = new RenderGraphBuilder(this, null);
	}

	// =========================================================================
	// Setup phase — declare passes and import resources
	// =========================================================================

	/// Imports an external texture into the render graph.
	/// The graph does not own the texture — caller is responsible for its lifetime.
	public RGTexture ImportTexture(ITexture texture, ITextureView view, ResourceState initialState)
	{
		let resource = new RenderGraphResource(mNextResourceIndex++, "imported_texture", true);
		resource.IsImported = true;
		resource.ImportedTexture = texture;
		resource.ImportedTextureView = view;
		resource.InitialState = initialState;
		mResources.Add(resource);
		return resource.AsTexture();
	}

	/// Imports an external texture with a debug name.
	public RGTexture ImportTexture(StringView name, ITexture texture, ITextureView view, ResourceState initialState)
	{
		let resource = new RenderGraphResource(mNextResourceIndex++, name, true);
		resource.IsImported = true;
		resource.ImportedTexture = texture;
		resource.ImportedTextureView = view;
		resource.InitialState = initialState;
		mResources.Add(resource);
		return resource.AsTexture();
	}

	/// Imports an external buffer into the render graph.
	/// The graph does not own the buffer — caller is responsible for its lifetime.
	public RGBuffer ImportBuffer(IBuffer buffer, ResourceState initialState)
	{
		let resource = new RenderGraphResource(mNextResourceIndex++, "imported_buffer", false);
		resource.IsImported = true;
		resource.ImportedBuffer = buffer;
		resource.InitialState = initialState;
		mResources.Add(resource);
		return resource.AsBuffer();
	}

	/// Imports an external buffer with a debug name.
	public RGBuffer ImportBuffer(StringView name, IBuffer buffer, ResourceState initialState)
	{
		let resource = new RenderGraphResource(mNextResourceIndex++, name, false);
		resource.IsImported = true;
		resource.ImportedBuffer = buffer;
		resource.InitialState = initialState;
		mResources.Add(resource);
		return resource.AsBuffer();
	}

	/// Adds a render pass to the graph.
	/// The setup callback declares resource accesses and sets the execute callback.
	public void AddPass(StringView name, QueueType queue, RGSetupCallback setup)
	{
		let pass = new RenderGraphPass(name, queue, (int32)mPasses.Count);
		mPasses.Add(pass);

		// Configure the builder for this pass and invoke the setup callback
		mBuilder.[Friend]mPass = pass;
		setup(mBuilder);
	}

	// =========================================================================
	// Compilation — schedule, cull, allocate, solve barriers
	// =========================================================================

	/// Compiles the render graph: schedules passes, culls unused passes,
	/// allocates transient resources, and solves barriers.
	/// Must be called once per frame after all passes are declared.
	public void Compile()
	{
		if (mIsCompiled)
		{
			Debug.WriteLine("RenderGraph: Compile() called more than once this frame");
			return;
		}

		mScheduledPasses.Clear();

		// Phase 2: Topological sort and culling
		ScheduleAndCull();

		// Phase 4: Transient resource aliasing
		mPool.ComputeAliasing(mResources, mScheduledPasses);

		// Phase 3: Barrier solving (after aliasing so pool resources are assigned)
		BarrierSolver.FreeBarriers(mPassBarriers);
		BarrierSolver.Solve(mScheduledPasses, mResources, mPassBarriers);

		// Phase 6: Cross-queue synchronization
		ComputeCrossQueueSync();

		mIsCompiled = true;
	}

	/// Executes all scheduled passes.
	/// Allocates GPU resources, inserts barriers, records commands per queue, and submits
	/// with timeline fence synchronization for cross-queue dependencies.
	public void Execute(IDevice device)
	{
		if (!mIsCompiled)
		{
			Debug.WriteLine("RenderGraph: Execute() called before Compile()");
			return;
		}

		if (mScheduledPasses.Count == 0)
			return;

		mDevice = device;

		if (device == null)
		{
			// Headless/test mode — just invoke callbacks without GPU work
			for (let pass in mScheduledPasses)
			{
				// Check runtime condition
				if (pass.Condition != null && !pass.Condition())
					continue;

				if (pass.ExecuteCallback != null)
					pass.ExecuteCallback(null, mRegistry);
			}
			return;
		}

		// Allocate transient resources, wire them, and re-solve barriers
		// with concrete GPU handles (Compile() solves barriers before allocation,
		// so transient resources have null handles in the initial barrier set).
		PrepareExecution(device);

		// Determine which queue types are active
		bool[3] activeQueues = default;
		for (let pass in mScheduledPasses)
			activeQueues[(int)pass.QueueType] = true;

		// Create command pools and encoders for active queues
		ICommandEncoder[3] encoders = default;
		for (int q = 0; q < 3; q++)
		{
			if (!activeQueues[q]) continue;

			switch (device.CreateCommandPool((QueueType)q))
			{
			case .Ok(let pool):
				mCommandPools[q] = pool;
			case .Err:
				Debug.WriteLine(scope $"RenderGraph: Failed to create command pool for queue {q}");
				continue;
			}

			switch (mCommandPools[q].CreateEncoder())
			{
			case .Ok(let enc):
				encoders[q] = enc;
			case .Err:
				Debug.WriteLine(scope $"RenderGraph: Failed to create encoder for queue {q}");
				continue;
			}
		}

		// Create timeline fence if cross-queue sync is needed
		if (mSyncPoints.Count > 0)
		{
			switch (device.CreateFence(0))
			{
			case .Ok(let fence):
				mTimelineFence = fence;
			case .Err:
				Debug.WriteLine("RenderGraph: Failed to create timeline fence for cross-queue sync");
			}
		}

		// Build barrier lookup
		let barrierLookup = scope Dictionary<int32, int32>();
		for (int i = 0; i < mPassBarriers.Count; i++)
			barrierLookup[mPassBarriers[i].PassIndex] = (int32)i;

		// Record all passes into their respective queue encoders
		for (int passIdx = 0; passIdx < mScheduledPasses.Count; passIdx++)
		{
			let pass = mScheduledPasses[passIdx];
			let qIdx = (int)pass.QueueType;
			let encoder = encoders[qIdx];
			if (encoder == null) continue;

			// Insert barriers before this pass (always, even if conditionally skipped,
			// because subsequent passes may depend on the state transitions)
			int32 barrierIdx;
			if (barrierLookup.TryGetValue((int32)passIdx, out barrierIdx))
				EmitBarriers(encoder, mPassBarriers[barrierIdx]);

			// Check runtime condition — skip execution but keep barriers
			if (pass.Condition != null && !pass.Condition())
				continue;

			// Debug label
			{
				float r, g, b;
				GetQueueLabelColor(pass.QueueType, out r, out g, out b);
				encoder.BeginDebugLabel(pass.Name, r, g, b);
			}

			// Invoke pass execute callback
			if (pass.ExecuteCallback != null)
				pass.ExecuteCallback(encoder, mRegistry);

			encoder.EndDebugLabel();
		}

		// Finish and submit each queue's command buffer with sync
		for (int q = 0; q < 3; q++)
		{
			if (encoders[q] == null) continue;

			let cmdBuf = encoders[q].Finish();
			let queue = device.GetQueue((QueueType)q);
			ICommandBuffer[1] cmdBufs = .(cmdBuf);

			// Check if this queue needs to wait on or signal any fence
			let needsSignal = NeedsSignal((QueueType)q);
			let waitValue = GetWaitValue((QueueType)q);
			let signalValue = GetSignalValue((QueueType)q);

			if (mTimelineFence != null && (needsSignal || waitValue > 0))
			{
				if (waitValue > 0)
				{
					IFence[1] waitFences = .(mTimelineFence);
					uint64[1] waitValues = .(waitValue);
					queue.Submit(cmdBufs, waitFences, waitValues,
						needsSignal ? mTimelineFence : null,
						needsSignal ? signalValue : 0);
				}
				else if (needsSignal)
				{
					queue.Submit(cmdBufs, mTimelineFence, signalValue);
				}
			}
			else
			{
				queue.Submit(cmdBufs);
			}

			// Release encoder
			mCommandPools[q].DestroyEncoder(ref encoders[q]);
		}
	}

	/// Emits barriers for a pass into the command encoder.
	private void EmitBarriers(ICommandEncoder encoder, BarrierSolver.PassBarriers pb)
	{
		let texCount = pb.TextureBarriers != null ? pb.TextureBarriers.Count : 0;
		let bufCount = pb.BufferBarriers != null ? pb.BufferBarriers.Count : 0;
		let memCount = pb.MemoryBarriers != null ? pb.MemoryBarriers.Count : 0;

		if (texCount == 0 && bufCount == 0 && memCount == 0)
			return;

		BarrierGroup group = .();

		if (texCount > 0)
		{
			let texBarriers = scope TextureBarrier[texCount];
			for (int i = 0; i < texCount; i++)
				texBarriers[i] = pb.TextureBarriers[i];
			group.TextureBarriers = texBarriers;
		}

		if (bufCount > 0)
		{
			let bufBarriers = scope BufferBarrier[bufCount];
			for (int i = 0; i < bufCount; i++)
				bufBarriers[i] = pb.BufferBarriers[i];
			group.BufferBarriers = bufBarriers;
		}

		if (memCount > 0)
		{
			let memBarriers = scope MemoryBarrier[memCount];
			for (int i = 0; i < memCount; i++)
				memBarriers[i] = pb.MemoryBarriers[i];
			group.MemoryBarriers = memBarriers;
		}

		encoder.Barrier(group);
	}

	private static void GetQueueLabelColor(QueueType queue, out float r, out float g, out float b)
	{
		switch (queue)
		{
		case .Graphics: r = 0.4f; g = 0.7f; b = 1.0f;
		case .Compute:  r = 1.0f; g = 0.7f; b = 0.3f;
		case .Transfer: r = 0.5f; g = 1.0f; b = 0.5f;
		}
	}

	private void BeginDebugLabel(ICommandEncoder encoder, StringView label, QueueType queue)
	{
		float r, g, b;
		GetQueueLabelColor(queue, out r, out g, out b);
		encoder.BeginDebugLabel(label, r, g, b);
	}

	/// Allocates GPU resources for transient textures/buffers, wires them
	/// into the resource metadata, and re-solves barriers so they reference
	/// concrete GPU handles. Call after Compile() and before executing passes.
	/// Execute() calls this internally; manual executors must call it explicitly.
	public void PrepareExecution(IDevice device)
	{
		mDevice = device;
		mPool.AllocateGpuResources(device);
		WirePooledResources();

		// Re-solve barriers now that transient resources have concrete GPU handles.
		// Compile() already solved barrier states correctly, but the Texture/Buffer
		// fields in barrier structs are null for transient resources at that point.
		BarrierSolver.FreeBarriers(mPassBarriers);
		BarrierSolver.Solve(mScheduledPasses, mResources, mPassBarriers);

		// Track final states so next frame's barriers start correctly
		TrackFinalResourceStates();
	}

	/// Resets the render graph for the next frame.
	/// Clears all passes and transient resources. Releases command pools.
	/// Caller must ensure all submitted GPU work has completed before calling.
	public void Reset()
	{
		// Release command pools from this frame
		if (mDevice != null)
		{
			for (int q = 0; q < 3; q++)
			{
				if (mCommandPools[q] != null)
				{
					mCommandPools[q].Reset();
					mDevice.DestroyCommandPool(ref mCommandPools[q]);
				}
			}

			if (mTimelineFence != null)
				mDevice.DestroyFence(ref mTimelineFence);
		}

		for (let pass in mPasses)
			delete pass;
		mPasses.Clear();

		for (let resource in mResources)
			delete resource;
		mResources.Clear();

		mScheduledPasses.Clear();
		mSyncPoints.Clear();
		BarrierSolver.FreeBarriers(mPassBarriers);
		mNextResourceIndex = 1;
		mFenceValue = 0;
		mIsCompiled = false;
	}

	/// Destroys the render graph and all pooled resources.
	/// Must be called before the device is destroyed.
	public void Destroy()
	{
		Reset();
		if (mDevice != null)
			mPool.DestroyAll(mDevice);
	}

	// =========================================================================
	// Phase 6: Cross-queue synchronization
	// =========================================================================

	/// Detects cross-queue dependencies and creates sync points.
	private void ComputeCrossQueueSync()
	{
		mSyncPoints.Clear();
		mFenceValue = 0;

		for (int dstIdx = 0; dstIdx < mScheduledPasses.Count; dstIdx++)
		{
			let dstPass = mScheduledPasses[dstIdx];

			for (let access in dstPass.Accesses)
			{
				if (!access.IsRead) continue;

				// Find the latest writer of this resource before the destination pass
				let writerPassIdx = FindWriter(access.Resource, dstPass.Index);
				if (writerPassIdx < 0) continue;

				// Find the writer in the scheduled list
				for (int srcIdx = 0; srcIdx < mScheduledPasses.Count; srcIdx++)
				{
					let srcPass = mScheduledPasses[srcIdx];
					if (srcPass.Index != writerPassIdx) continue;
					if (srcPass.QueueType == dstPass.QueueType) break; // same queue, no sync needed

					// Cross-queue dependency detected
					// Check if we already have a sync point for this src→dst queue pair
					bool alreadyExists = false;
					for (let sp in mSyncPoints)
					{
						if (sp.SrcQueue == srcPass.QueueType && sp.DstQueue == dstPass.QueueType &&
							sp.SrcPassIndex == (int32)srcIdx && sp.DstPassIndex == (int32)dstIdx)
						{
							alreadyExists = true;
							break;
						}
					}

					if (!alreadyExists)
					{
						mFenceValue++;
						mSyncPoints.Add(.()
						{
							SrcQueue = srcPass.QueueType,
							DstQueue = dstPass.QueueType,
							SrcPassIndex = (int32)srcIdx,
							DstPassIndex = (int32)dstIdx,
							FenceValue = mFenceValue
						});
					}

					break;
				}
			}
		}
	}

	/// Returns whether the given queue needs to signal the timeline fence.
	private bool NeedsSignal(QueueType queue)
	{
		for (let sp in mSyncPoints)
		{
			if (sp.SrcQueue == queue)
				return true;
		}
		return false;
	}

	/// Returns the maximum fence value this queue needs to wait for before executing.
	private uint64 GetWaitValue(QueueType queue)
	{
		uint64 maxWait = 0;
		for (let sp in mSyncPoints)
		{
			if (sp.DstQueue == queue && sp.FenceValue > maxWait)
				maxWait = sp.FenceValue;
		}
		return maxWait;
	}

	/// Returns the fence value this queue should signal after executing.
	private uint64 GetSignalValue(QueueType queue)
	{
		uint64 maxSignal = 0;
		for (let sp in mSyncPoints)
		{
			if (sp.SrcQueue == queue && sp.FenceValue > maxSignal)
				maxSignal = sp.FenceValue;
		}
		return maxSignal;
	}

	// =========================================================================
	// Internal helpers
	// =========================================================================

	/// Creates a transient texture resource.
	private RenderGraphResource CreateTransientTexture(RGTextureDesc desc)
	{
		let name = desc.Name.IsEmpty ? "transient_texture" : desc.Name;
		let resource = new RenderGraphResource(mNextResourceIndex++, name, true);
		resource.IsImported = false;
		resource.TextureDesc = desc;
		resource.InitialState = .Undefined;
		mResources.Add(resource);
		return resource;
	}

	/// Creates a transient buffer resource.
	private RenderGraphResource CreateTransientBuffer(RGBufferDesc desc)
	{
		let name = desc.Name.IsEmpty ? "transient_buffer" : desc.Name;
		let resource = new RenderGraphResource(mNextResourceIndex++, name, false);
		resource.IsImported = false;
		resource.BufferDesc = desc;
		resource.InitialState = .Undefined;
		mResources.Add(resource);
		return resource;
	}

	/// Wires pooled GPU resources into the resource metadata so the registry can resolve them.
	private void WirePooledResources()
	{
		for (let resource in mResources)
		{
			if (resource.IsImported) continue;

			if (resource.IsTexture)
			{
				let pooled = mPool.GetPooledTexture(resource.Index);
				if (pooled != null)
				{
					resource.ImportedTexture = pooled.Texture;
					resource.ImportedTextureView = pooled.View;
					resource.InitialState = pooled.LastKnownState;
				}
			}
			else
			{
				let pooled = mPool.GetPooledBuffer(resource.Index);
				if (pooled != null)
				{
					resource.ImportedBuffer = pooled.Buffer;
					resource.InitialState = pooled.LastKnownState;
				}
			}
		}
	}

	/// After execution, stores the final resource states back to the pool
	/// so next frame's barriers start from the correct state.
	private void TrackFinalResourceStates()
	{
		// Determine each transient resource's final state from its last access
		for (let resource in mResources)
		{
			if (resource.IsImported) continue;

			// Find last access across all scheduled passes
			ResourceState finalState = resource.InitialState;
			for (let pass in mScheduledPasses)
			{
				for (let access in pass.Accesses)
				{
					if (access.Resource.Index == resource.Index)
						finalState = access.ToResourceState();
				}
			}

			if (resource.IsTexture)
			{
				let pooled = mPool.GetPooledTexture(resource.Index);
				if (pooled != null)
					pooled.LastKnownState = finalState;
			}
			else
			{
				let pooled = mPool.GetPooledBuffer(resource.Index);
				if (pooled != null)
					pooled.LastKnownState = finalState;
			}
		}
	}

	/// Looks up a resource by index.
	private RenderGraphResource GetResource(uint32 index)
	{
		for (let resource in mResources)
		{
			if (resource.Index == index)
				return resource;
		}
		return null;
	}

	// =========================================================================
	// Phase 2: Scheduling & Culling
	// =========================================================================

	private void ScheduleAndCull()
	{
		// Step 1: Build dependency edges (read-after-write)
		// For each pass, find which passes wrote the resources it reads.
		let passCount = mPasses.Count;

		// adjacency[i] = list of pass indices that pass i depends on (must execute before i)
		let dependencies = scope List<List<int32>>(passCount);
		for (int i = 0; i < passCount; i++)
			dependencies.Add(scope:: List<int32>());

		for (let pass in mPasses)
		{
			for (let access in pass.Accesses)
			{
				if (access.IsRead)
				{
					// Find the latest pass that wrote this resource before the current pass
					let writerPass = FindWriter(access.Resource, pass.Index);
					if (writerPass >= 0 && writerPass != pass.Index)
					{
						// pass depends on writerPass
						if (!dependencies[pass.Index].Contains((int32)writerPass))
							dependencies[pass.Index].Add((int32)writerPass);
					}
				}
			}
		}

		// Step 2: Topological sort (Kahn's algorithm)
		let inDegree = scope int32[passCount];
		for (int i = 0; i < passCount; i++)
			inDegree[i] = (int32)dependencies[i].Count;

		let queue = scope Queue<int32>();
		for (int i = 0; i < passCount; i++)
		{
			if (inDegree[i] == 0)
				queue.Add((int32)i);
		}

		let sortedOrder = scope List<int32>(passCount);
		while (queue.Count > 0)
		{
			let current = queue.PopFront();
			sortedOrder.Add(current);

			// Find passes that depend on current
			for (int i = 0; i < passCount; i++)
			{
				if (dependencies[i].Contains(current))
				{
					inDegree[i]--;
					if (inDegree[i] == 0)
						queue.Add((int32)i);
				}
			}
		}

		if (sortedOrder.Count != passCount)
		{
			Debug.WriteLine("RenderGraph: Dependency cycle detected! Some passes cannot be scheduled.");
		}

		// Step 3: Pass culling — reverse walk from outputs
		// A pass is retained if:
		// - It has side effects, OR
		// - It writes a resource that is read by a retained pass, OR
		// - It writes an imported resource
		let retained = scope bool[passCount];

		// Mark side-effect passes and passes that write imported resources
		for (let pass in mPasses)
		{
			if (pass.HasSideEffects)
			{
				retained[pass.Index] = true;
				continue;
			}

			// Check if this pass writes to an imported resource
			for (let access in pass.Accesses)
			{
				if (access.IsWrite)
				{
					let resource = GetResource(access.Resource.Index);
					if (resource != null && resource.IsImported)
					{
						retained[pass.Index] = true;
						break;
					}
				}
			}
		}

		// Propagate retention backwards through dependencies
		var changed = true;
		while (changed)
		{
			changed = false;
			for (let passIdx in sortedOrder)
			{
				if (!retained[passIdx])
					continue;

				for (let depIdx in dependencies[passIdx])
				{
					if (!retained[depIdx])
					{
						retained[depIdx] = true;
						changed = true;
					}
				}
			}
		}

		// Step 4: Build final scheduled pass list
		int32 order = 0;
		for (let passIdx in sortedOrder)
		{
			let pass = mPasses[passIdx];
			if (retained[passIdx])
			{
				pass.IsCulled = false;
				pass.ScheduledOrder = order++;
				mScheduledPasses.Add(pass);
			}
			else
			{
				pass.IsCulled = true;
				#if DEBUG
				Debug.WriteLine(scope $"RenderGraph: Pass '{pass.Name}' culled (outputs not consumed)");
				#endif
			}
		}

		// Step 5: Compute resource lifetimes
		for (int i = 0; i < mScheduledPasses.Count; i++)
		{
			let pass = mScheduledPasses[i];
			for (let access in pass.Accesses)
			{
				let resource = GetResource(access.Resource.Index);
				if (resource == null) continue;

				if (resource.FirstUsePass < 0)
					resource.FirstUsePass = (int32)i;
				resource.LastUsePass = (int32)i;
			}
		}
	}

	/// Finds the latest pass that writes the given resource before the specified pass.
	/// Handles read-write chains correctly by returning the most recent writer.
	private int32 FindWriter(RGResource resource, int32 beforePass = int32.MaxValue)
	{
		int32 lastWriter = -1;

		// Check if a resource was created by a pass (WriterPass is set during CreateTexture/CreateBuffer)
		let rgResource = GetResource(resource.Index);
		if (rgResource != null && rgResource.WriterPass >= 0 && rgResource.WriterPass < beforePass)
			lastWriter = rgResource.WriterPass;

		// Scan all explicit write accesses — take the latest writer before the querying pass
		for (let pass in mPasses)
		{
			if (pass.Index >= beforePass) continue;
			for (let access in pass.Accesses)
			{
				if (access.IsWrite && access.Resource.Index == resource.Index)
				{
					if (pass.Index > lastWriter)
						lastWriter = pass.Index;
				}
			}
		}
		return lastWriter;
	}

	// =========================================================================
	// Public accessors for debugging/testing
	// =========================================================================

	/// Number of passes declared this frame.
	public int PassCount => mPasses.Count;

	/// Number of passes that survived culling.
	public int ScheduledPassCount => mScheduledPasses.Count;

	/// Number of resources tracked this frame.
	public int ResourceCount => mResources.Count;

	/// Gets a pass by index.
	public RenderGraphPass GetPass(int index) => mPasses[index];

	/// Gets a scheduled pass by execution order.
	public RenderGraphPass GetScheduledPass(int index) => mScheduledPasses[index];

	/// Whether the graph has been compiled this frame.
	public bool IsCompiled => mIsCompiled;

	/// Solved barriers (populated after Compile). One entry per pass that needs barriers.
	public List<BarrierSolver.PassBarriers> PassBarriers => mPassBarriers;

	/// The transient resource pool (for testing/debugging).
	public TransientResourcePool Pool => mPool;

	/// Cross-queue sync points (for testing/debugging).
	public List<QueueSyncPoint> SyncPoints => mSyncPoints;

	/// All resources tracked this frame (for debug/visualization).
	public List<RenderGraphResource> Resources => mResources;

	/// All passes declared this frame (for debug/validation).
	public List<RenderGraphPass> Passes => mPasses;

	/// Gets the barriers for a specific scheduled pass index, or null if none needed.
	public BarrierSolver.PassBarriers? GetBarriersForPass(int scheduledPassIndex)
	{
		for (let pb in mPassBarriers)
		{
			if (pb.PassIndex == (int32)scheduledPassIndex)
				return pb;
		}
		return null;
	}
}
