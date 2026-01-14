namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;

/// Frame-based render graph that manages resource allocation and pass execution.
/// Resources are automatically pooled and reused across frames.
class RenderGraph
{
	private IDevice mDevice;
	private List<RenderPass> mPasses = new .() ~ DeleteContainerAndItems!(_);
	private RenderGraphBuilder mBuilder = new .() ~ delete _;
	private RenderGraphContext mContext = new .() ~ delete _;
	private DeferredDeletionQueue mDeletionQueue = new .() ~ delete _;
	private TransientResourcePool mResourcePool ~ delete _;

	// Resource tracking
	private Dictionary<uint32, RenderGraphResource> mResources = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	private int32 mFrameIndex = 0;
	private bool mCompiled = false;
	private List<int32> mExecutionOrder = new .() ~ delete _;

	/// Creates a render graph for the given device.
	public this(IDevice device)
	{
		mDevice = device;
		mContext.Device = device;
		mResourcePool = new TransientResourcePool(device);
		mBuilder.SetResources(mResources);
		mContext.SetResources(mResources);
	}

	/// Begins a new frame, resetting the graph for recording.
	public void BeginFrame(int32 frameIndex)
	{
		mFrameIndex = frameIndex;
		mContext.FrameIndex = frameIndex;
		mDeletionQueue.BeginFrame(frameIndex);
		mResourcePool.BeginFrame(frameIndex);

		// Clear passes from previous frame
		ClearAndDeleteItems!(mPasses);

		// Clear resources from previous frame
		for (let kv in mResources)
			delete kv.value;
		mResources.Clear();

		mBuilder.Reset();
		mExecutionOrder.Clear();
		mCompiled = false;
	}

	/// Adds a render pass to the graph.
	public T AddPass<T>(T pass) where T : RenderPass
	{
		pass.PassIndex = (int32)mPasses.Count;
		mPasses.Add(pass);
		return pass;
	}

	/// Imports an external texture into the graph.
	public RenderGraphTextureHandle ImportTexture(StringView name, ITexture texture, ITextureView view = null)
	{
		return mBuilder.ImportTexture(name, texture, view);
	}

	/// Imports an external buffer into the graph.
	public RenderGraphBufferHandle ImportBuffer(StringView name, IBuffer buffer)
	{
		return mBuilder.ImportBuffer(name, buffer);
	}

	/// Compiles the render graph, resolving dependencies and allocating resources.
	public Result<void> Compile()
	{
		if (mCompiled)
			return .Ok;

		// Setup phase: let passes declare their resources and dependencies
		for (let pass in mPasses)
		{
			pass.ClearDependencies();
			pass.Setup(mBuilder);
		}

		// Build dependency graph and track resource lifetimes
		BuildResourceLifetimes();

		// Topological sort passes based on dependencies
		if (TopologicalSort() case .Err)
			return .Err;

		// Allocate transient resources from pool
		if (AllocateResources() case .Err)
			return .Err;

		mCompiled = true;
		return .Ok;
	}

	/// Executes the compiled render graph.
	public Result<void> Execute(ICommandEncoder commandEncoder)
	{
		if (!mCompiled)
		{
			if (Compile() case .Err)
				return .Err;
		}

		mContext.CommandEncoder = commandEncoder;

		// Execute passes in sorted order
		for (let passIndex in mExecutionOrder)
		{
			let pass = mPasses[passIndex];
			pass.Execute(mContext);
		}

		return .Ok;
	}

	/// Ends the frame, releasing transient resources.
	public void EndFrame()
	{
		mResourcePool.EndFrame();
	}

	/// Queues a resource for deferred deletion.
	public void QueueDelete(IDisposable resource)
	{
		mDeletionQueue.QueueDelete(resource);
	}

	/// Flushes all pending deletions (call on shutdown).
	public void Flush()
	{
		mDeletionQueue.Flush();
		mResourcePool.Clear();
	}

	/// Builds resource lifetime information from pass dependencies.
	private void BuildResourceLifetimes()
	{
		for (let pass in mPasses)
		{
			let passIndex = pass.PassIndex;

			// Track texture reads
			for (let handle in pass.TextureReads)
			{
				if (mResources.TryGetValue(handle.Handle.Index, let resource))
					resource.AddReader(passIndex);
			}

			// Track texture writes
			for (let handle in pass.TextureWrites)
			{
				if (mResources.TryGetValue(handle.Handle.Index, let resource))
					resource.AddWriter(passIndex);
			}

			// Track buffer reads
			for (let handle in pass.BufferReads)
			{
				if (mResources.TryGetValue(handle.Handle.Index, let resource))
					resource.AddReader(passIndex);
			}

			// Track buffer writes
			for (let handle in pass.BufferWrites)
			{
				if (mResources.TryGetValue(handle.Handle.Index, let resource))
					resource.AddWriter(passIndex);
			}
		}
	}

	/// Performs topological sort of passes based on resource dependencies.
	private Result<void> TopologicalSort()
	{
		let passCount = (int32)mPasses.Count;
		if (passCount == 0)
			return .Ok;

		// Build adjacency list: pass -> passes that depend on it
		List<List<int32>> dependents = scope .();
		for (int i = 0; i < passCount; i++)
			dependents.Add(scope:: .());

		// Count incoming edges for each pass
		int32[] inDegree = scope int32[passCount];

		// Build dependency edges from resource read/write relationships
		for (let kv in mResources)
		{
			let resource = kv.value;

			// Writers must execute before readers
			for (let writerIndex in resource.WriterPasses)
			{
				for (let readerIndex in resource.ReaderPasses)
				{
					if (writerIndex != readerIndex)
					{
						dependents[writerIndex].Add(readerIndex);
						inDegree[readerIndex]++;
					}
				}
			}
		}

		// Kahn's algorithm for topological sort
		List<int32> queue = scope .();

		// Start with passes that have no dependencies
		for (int32 i = 0; i < passCount; i++)
		{
			if (inDegree[i] == 0)
				queue.Add(i);
		}

		mExecutionOrder.Clear();

		while (queue.Count > 0)
		{
			let current = queue.PopFront();
			mExecutionOrder.Add(current);

			for (let dependent in dependents[current])
			{
				inDegree[dependent]--;
				if (inDegree[dependent] == 0)
					queue.Add(dependent);
			}
		}

		// Check for cycles
		if (mExecutionOrder.Count != passCount)
		{
			Console.WriteLine("[RenderGraph] Cycle detected in pass dependencies!");
			return .Err;
		}

		return .Ok;
	}

	/// Allocates transient resources from the pool.
	private Result<void> AllocateResources()
	{
		for (let kv in mResources)
		{
			let resource = kv.value;

			// Skip imported resources (already have backing storage)
			if (resource.Lifetime == .Imported)
				continue;

			// Allocate from pool based on type
			switch (resource.Type)
			{
			case .Texture:
				if (mResourcePool.AllocateTexture(resource.TextureDesc) case .Ok(let result))
				{
					resource.Texture = result.texture;
					resource.TextureView = result.view;
				}
				else
				{
					Console.WriteLine(scope $"[RenderGraph] Failed to allocate texture: {resource.Name}");
					return .Err;
				}

			case .Buffer:
				if (mResourcePool.AllocateBuffer(resource.BufferDesc) case .Ok(let buffer))
				{
					resource.Buffer = buffer;
				}
				else
				{
					Console.WriteLine(scope $"[RenderGraph] Failed to allocate buffer: {resource.Name}");
					return .Err;
				}
			}
		}

		return .Ok;
	}

	/// Current frame index.
	public int32 FrameIndex => mFrameIndex;

	/// Number of passes in the graph.
	public int32 PassCount => (int32)mPasses.Count;

	/// Number of resources in the graph.
	public int32 ResourceCount => (int32)mResources.Count;

	/// Gets the resource pool statistics.
	public (int32 textures, int32 buffers, int32 texturesInUse, int32 buffersInUse) GetPoolStats()
	{
		return (
			mResourcePool.PooledTextureCount,
			mResourcePool.PooledBufferCount,
			mResourcePool.TexturesInUse,
			mResourcePool.BuffersInUse
		);
	}
}
