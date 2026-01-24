namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Profiler;

/// Wrapper for ITexture pointer to enable use as dictionary key.
/// Implements IHashable based on the pointer address.
struct TextureKey : IHashable
{
	public ITexture Texture;

	public this(ITexture texture)
	{
		Texture = texture;
	}

	public int GetHashCode()
	{
		// Hash based on the object's pointer address
		return (int)(void*)Internal.UnsafeCastToPtr(Texture);
	}

	public static bool operator ==(Self lhs, Self rhs)
	{
		// Compare by reference (same object instance)
		return lhs.Texture === rhs.Texture;
	}

	public static bool operator !=(Self lhs, Self rhs)
	{
		return !(lhs == rhs);
	}
}

/// A deferred texture read declaration: "pass X should read resource Y".
class DeferredRead
{
	public String PassName = new .() ~ delete _;
	public RGResourceHandle Handle;
}

/// A pooled transient texture, cached between frames to avoid re-creation.
class PooledTexture
{
	public TextureResourceDesc Desc;
	public ITexture Texture;
	public ITextureView TextureView;
	public ITextureView DepthOnlyView;

	public ~this()
	{
		if (DepthOnlyView != null) delete DepthOnlyView;
		if (TextureView != null) delete TextureView;
		if (Texture != null) delete Texture;
	}

	/// Checks if this pooled texture matches the requested descriptor.
	public bool Matches(TextureResourceDesc desc)
	{
		return Desc.Width == desc.Width &&
			Desc.Height == desc.Height &&
			Desc.Format == desc.Format &&
			Desc.Usage == desc.Usage &&
			Desc.DepthOrArrayLayers == desc.DepthOrArrayLayers &&
			Desc.MipLevels == desc.MipLevels &&
			Desc.SampleCount == desc.SampleCount;
	}
}

/// Render graph that manages pass dependencies and resource lifetimes.
public class RenderGraph : IDisposable
{
	/// Enable verbose logging for layout tracking and barriers.
	private const bool DebugLogLayouts = false;

	private IDevice mDevice;

	// Resources - uses slot-based system where removed resources leave null holes
	private List<RenderGraphResource> mResources = new .() ~ DeleteContainerAndItems!(_);
	private Dictionary<String, RGResourceHandle> mResourceNames = new .() ~ DeleteDictionaryAndKeys!(_);
	private List<int32> mFreeSlots = new .() ~ delete _; // Indices of null slots available for reuse

	// Passes
	private List<RenderPass> mPasses = new .() ~ DeleteContainerAndItems!(_);
	private List<PassHandle> mExecutionOrder = new .() ~ delete _;

	// Frame state
	private bool mIsBuilding = false;
	private bool mIsCompiled = false;

	// Texture layout tracking (by texture pointer, not by resource)
	// This correctly handles imported resources that share the same underlying texture
	private Dictionary<TextureKey, ResourceLayoutState> mTextureLayouts = new .() ~ delete _;

	// Resources that need to be transitioned to Present layout at end of frame (e.g., swapchain)
	private List<RGResourceHandle> mPresentTargets = new .() ~ delete _;

	// Deferred texture reads: (passName, resourceHandle) pairs applied during Compile.
	// Allows a feature to declare "pass X reads resource Y" before that pass exists.
	private List<DeferredRead> mDeferredReads = new .() ~ DeleteContainerAndItems!(_);

	// Deferred deletion queues per frame slot.
	// Transient resources are pushed here instead of being deleted immediately,
	// and flushed the next time the same frame slot is reused (after fence wait).
	private List<RenderGraphResource>[RenderConfig.FrameBufferCount] mDeferredDeletions;

	// Transient texture pool: GPU textures cached between frames to avoid re-creation.
	private List<PooledTexture> mTexturePool = new .() ~ DeleteContainerAndItems!(_);

	// Statistics
	public int32 PassCount => (int32)mPasses.Count;
	public int32 ResourceCount => (int32)mResources.Count;
	public int32 CulledPassCount { get; private set; }

	public this(IDevice device)
	{
		mDevice = device;
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			mDeferredDeletions[i] = new List<RenderGraphResource>();
	}

	/// Begins building the render graph for a new frame.
	/// frameIndex is the current frame buffer slot (0 to FrameBufferCount-1),
	/// used for deferred resource deletion (safe after fence wait in AcquireNextImage).
	public void BeginFrame(int32 frameIndex)
	{
		// Flush deferred deletions for this frame slot.
		// These resources were used in the previous command buffer for this slot,
		// which has now completed (fence was waited on in AcquireNextImage).
		FlushDeferredDeletions(frameIndex);

		// Clear previous frame passes
		for (let pass in mPasses)
			delete pass;
		mPasses.Clear();

		// Reset transient resources - defer deletion instead of immediate release
		for (int i = 0; i < mResources.Count; i++)
		{
			let resource = mResources[i];
			if (resource == null)
				continue; // Already a free slot

			if (resource.IsTransient)
			{
				// Remove texture layout tracking for this resource before deferring
				if (resource.Type == .Texture && resource.Texture != null)
				{
					let key = TextureKey(resource.Texture);
					mTextureLayouts.Remove(key);
				}

				// Remove name mapping
				for (let kv in mResourceNames)
				{
					if (kv.value.Index == (uint32)i)
					{
						let key = kv.key;
						mResourceNames.Remove(key);
						delete key;
						break;
					}
				}

				// Defer deletion until this frame slot's fence is waited on next time
				mDeferredDeletions[frameIndex].Add(resource);
				mResources[i] = null; // Leave a hole, don't shift indices
				mFreeSlots.Add((int32)i); // Track this slot for reuse
			}
			else
			{
				// Reset tracking for imported resources
				resource.RefCount = 0;
				resource.FirstWriter = .Invalid;
				resource.LastReader = .Invalid;
				// Keep CurrentLayout - imported resources maintain their layout across frames
			}
		}

		mExecutionOrder.Clear();
		mPresentTargets.Clear();
		for (let dr in mDeferredReads) delete dr;
		mDeferredReads.Clear();
		// Note: Do NOT clear mTextureLayouts - texture layout state persists across frames.
		// This is important for swapchain images which cycle through and retain their
		// layout state (e.g., Present after being presented, ColorAttachment after rendering).
		mIsBuilding = true;
		mIsCompiled = false;
		CulledPassCount = 0;
	}

	/// Creates a transient texture resource.
	public RGResourceHandle CreateTexture(StringView name, TextureResourceDesc desc)
	{
		Runtime.Assert(mIsBuilding, "Must call BeginFrame before creating resources");

		let resource = RenderGraphResource.CreateTexture(name, desc);
		return AddResource(resource, name);
	}

	/// Creates a transient buffer resource.
	public RGResourceHandle CreateBuffer(StringView name, BufferResourceDesc desc)
	{
		Runtime.Assert(mIsBuilding, "Must call BeginFrame before creating resources");

		let resource = RenderGraphResource.CreateBuffer(name, desc);
		return AddResource(resource, name);
	}

	/// Imports an external texture.
	/// If a resource with the same name already exists, updates its texture/view references.
	/// This is important for swapchain textures which change each frame.
	public RGResourceHandle ImportTexture(StringView name, ITexture texture, ITextureView view)
	{
		let nameStr = scope String(name);
		if (mResourceNames.TryGetValue(nameStr, let existing))
		{
			// Update the existing resource's texture references
			// This is critical for swapchain textures which cycle between multiple images
			if (let resource = GetResourceByHandle(existing))
			{
				resource.Texture = texture;
				resource.TextureView = view;
			}
			return existing;
		}

		let resource = RenderGraphResource.ImportTexture(name, texture, view);
		return AddResource(resource, name);
	}

	/// Imports an external buffer.
	/// If a resource with the same name already exists, updates its buffer reference.
	public RGResourceHandle ImportBuffer(StringView name, IBuffer buffer)
	{
		let nameStr = scope String(name);
		if (mResourceNames.TryGetValue(nameStr, let existing))
		{
			// Update the existing resource's buffer reference
			if (let resource = GetResourceByHandle(existing))
			{
				resource.Buffer = buffer;
			}
			return existing;
		}

		let resource = RenderGraphResource.ImportBuffer(name, buffer);
		return AddResource(resource, name);
	}

	/// Marks a texture resource to be transitioned to Present layout at end of frame.
	/// Use this for swapchain textures that will be presented.
	public void MarkForPresent(RGResourceHandle handle)
	{
		if (handle.IsValid)
			mPresentTargets.Add(handle);
	}

	/// Declares that a named pass should read a texture resource.
	/// Applied during Compile() so the pass does not need to exist yet.
	/// This inserts a proper layout barrier and dependency edge.
	public void DeferReadTexture(StringView passName, RGResourceHandle handle)
	{
		let entry = new DeferredRead();
		entry.PassName.Set(passName);
		entry.Handle = handle;
		mDeferredReads.Add(entry);
	}

	/// Gets a resource handle by name.
	public RGResourceHandle GetResource(StringView name)
	{
		let nameStr = scope String(name);
		if (mResourceNames.TryGetValue(nameStr, let handle))
			return handle;
		return .Invalid;
	}

	/// Gets the texture view for a resource.
	public ITextureView GetTextureView(RGResourceHandle handle)
	{
		if (let resource = GetResourceByHandle(handle))
			return resource.TextureView;
		return null;
	}

	/// Gets the depth-only texture view for a depth/stencil resource (for shader sampling).
	public ITextureView GetDepthOnlyTextureView(RGResourceHandle handle)
	{
		if (let resource = GetResourceByHandle(handle))
			return resource.DepthOnlyView;
		return null;
	}

	/// Gets the texture for a resource.
	public ITexture GetTexture(RGResourceHandle handle)
	{
		if (let resource = GetResourceByHandle(handle))
			return resource.Texture;
		return null;
	}

	/// Gets the buffer for a resource.
	public IBuffer GetBuffer(RGResourceHandle handle)
	{
		if (let resource = GetResourceByHandle(handle))
			return resource.Buffer;
		return null;
	}

	/// Adds a graphics render pass.
	public PassBuilder AddGraphicsPass(StringView name)
	{
		Runtime.Assert(mIsBuilding, "Must call BeginFrame before adding passes");

		let pass = new RenderPass(name, .Graphics);
		let handle = PassHandle() { Index = (uint32)mPasses.Count };
		mPasses.Add(pass);
		return PassBuilder(this, handle);
	}

	/// Adds a compute pass.
	public PassBuilder AddComputePass(StringView name)
	{
		Runtime.Assert(mIsBuilding, "Must call BeginFrame before adding passes");

		let pass = new RenderPass(name, .Compute);
		let handle = PassHandle() { Index = (uint32)mPasses.Count };
		mPasses.Add(pass);
		return PassBuilder(this, handle);
	}

	/// Adds a copy/transfer pass.
	public PassBuilder AddCopyPass(StringView name)
	{
		Runtime.Assert(mIsBuilding, "Must call BeginFrame before adding passes");

		let pass = new RenderPass(name, .Copy);
		let handle = PassHandle() { Index = (uint32)mPasses.Count };
		mPasses.Add(pass);
		return PassBuilder(this, handle);
	}

	/// Compiles the render graph.
	public Result<void> Compile()
	{
		Runtime.Assert(mIsBuilding, "Must call BeginFrame before Compile");

		mIsBuilding = false;

		// Apply deferred reads to their target passes
		ApplyDeferredReads();

		// Build resource references
		BuildResourceReferences();

		// Cull unused passes
		CullPasses();

		// Build pass dependencies (readers depend on latest writer, writers chain in order)
		BuildDependencies();

		// Topological sort
		if (TopologicalSort() case .Err)
			return .Err;

		// Allocate transient resources
		if (AllocateResources() case .Err)
			return .Err;

		mIsCompiled = true;
		return .Ok;
	}

	/// Executes all passes in order.
	public Result<void> Execute(ICommandEncoder commandEncoder)
	{
		Runtime.Assert(mIsCompiled, "Must call Compile before Execute");

		for (let passHandle in mExecutionOrder)
		{
			let pass = mPasses[passHandle.Index];
			if (pass.IsCulled)
				continue;

			using (SProfiler.Begin(pass.Name))
			{
				// Insert barriers for resources transitioning to this pass's usage
				InsertBarriersForPass(pass, commandEncoder);

				// Execute the pass
				if (ExecutePass(pass, commandEncoder) case .Err)
					return .Err;

				// Update layout state for resources modified by this pass
				UpdateLayoutsAfterPass(pass);
			}
		}

		// Transition present targets to Present layout for presentation
		TransitionPresentTargets(commandEncoder);

		return .Ok;
	}

	/// Ensures all marked present targets are in Present layout.
	///
	/// The Vulkan render pass already transitions swapchain attachments to Present via
	/// finalLayout, so this is typically a no-op. Only issues a barrier if the tracked
	/// layout indicates the transition hasn't happened yet.
	///
	/// IMPORTANT: Never use Undefined as the source layout here - that tells the driver
	/// it can discard the image contents, which some drivers (AMD, Intel) will do.
	private void TransitionPresentTargets(ICommandEncoder commandEncoder)
	{
		for (let handle in mPresentTargets)
		{
			if (let resource = GetResourceByHandle(handle))
			{
				if (resource.Type == .Texture && resource.Texture != null)
				{
					let currentLayout = GetTextureLayout(resource.Texture);
					if (currentLayout != .Present)
					{
						// Only issue barrier if not already in Present layout
						commandEncoder.TextureBarrier(resource.Texture, ToTextureLayout(currentLayout), .Present);
						SetTextureLayout(resource.Texture, .Present);
					}
				}
			}
		}
	}

	/// Ends the frame.
	public void EndFrame()
	{
		mIsCompiled = false;
	}

	// ========================================================================
	// Internal Methods
	// ========================================================================

	private RGResourceHandle AddResource(RenderGraphResource resource, StringView name)
	{
		int32 index;

		// Reuse a free slot if available, otherwise append
		if (mFreeSlots.Count > 0)
		{
			index = mFreeSlots.PopBack();
			mResources[index] = resource;
		}
		else
		{
			index = (int32)mResources.Count;
			mResources.Add(resource);
		}

		let handle = RGResourceHandle() { Index = (uint32)index, Generation = resource.Generation };

		let nameKey = new String(name);
		mResourceNames[nameKey] = handle;

		return handle;
	}

	private void ApplyDeferredReads()
	{
		for (let deferred in mDeferredReads)
		{
			for (let pass in mPasses)
			{
				if (StringView(pass.Name) == StringView(deferred.PassName))
				{
					pass.Reads.Add(deferred.Handle);
					break;
				}
			}
		}
	}

	private RenderPass GetPass(PassHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mPasses.Count)
			return null;
		return mPasses[handle.Index];
	}

	private RenderGraphResource GetResourceByHandle(RGResourceHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mResources.Count)
			return null;
		let resource = mResources[handle.Index];
		if (resource == null) // Slot was freed
			return null;
		if (resource.Generation != handle.Generation)
			return null;
		return resource;
	}

	private void BuildResourceReferences()
	{
		for (int i = 0; i < mPasses.Count; i++)
		{
			let pass = mPasses[i];
			let passHandle = PassHandle() { Index = (uint32)i };

			// Track outputs
			List<RGResourceHandle> outputs = scope .();
			pass.GetOutputs(outputs);
			for (let handle in outputs)
			{
				if (let resource = GetResourceByHandle(handle))
				{
					resource.RefCount++;
					if (!resource.FirstWriter.IsValid)
						resource.FirstWriter = passHandle;
				}
			}

			// Track inputs
			List<RGResourceHandle> inputs = scope .();
			pass.GetInputs(inputs);
			for (let handle in inputs)
			{
				if (let resource = GetResourceByHandle(handle))
				{
					resource.RefCount++;
					resource.LastReader = passHandle;
				}
			}
		}
	}

	private void CullPasses()
	{
		// Mark all passes as potentially culled
		for (let pass in mPasses)
			pass.IsCulled = !pass.NeverCull;

		// Work backwards - if a resource is read, mark its writer as needed
		bool changed = true;
		while (changed)
		{
			changed = false;

			for (int i = mPasses.Count - 1; i >= 0; i--)
			{
				let pass = mPasses[i];
				if (pass.IsCulled)
					continue;

				List<RGResourceHandle> inputs = scope .();
				pass.GetInputs(inputs);

				for (let handle in inputs)
				{
					if (let resource = GetResourceByHandle(handle))
					{
						if (resource.FirstWriter.IsValid)
						{
							let writerPass = mPasses[resource.FirstWriter.Index];
							if (writerPass.IsCulled)
							{
								writerPass.IsCulled = false;
								changed = true;
							}
						}
					}
				}
			}
		}

		// Count culled passes
		for (let pass in mPasses)
		{
			if (pass.IsCulled)
				CulledPassCount++;
		}
	}

	/// Builds pass dependencies by tracking the latest writer per resource.
	/// Each reader depends on the most recent writer before it.
	/// Each writer (Load+Store) depends on the previous writer, forming a chain.
	/// This ensures correct execution order for passes sharing resources.
	private void BuildDependencies()
	{
		// Track latest writer per resource (by resource index)
		PassHandle[] latestWriter = scope PassHandle[mResources.Count];
		for (int i = 0; i < latestWriter.Count; i++)
			latestWriter[i] = .Invalid;

		// Iterate passes in insertion order
		for (int i = 0; i < mPasses.Count; i++)
		{
			let pass = mPasses[i];
			if (pass.IsCulled)
				continue;

			let passHandle = PassHandle() { Index = (uint32)i };

			// For each input, depend on the latest writer before this pass
			List<RGResourceHandle> inputs = scope .();
			pass.GetInputs(inputs);

			for (let handle in inputs)
			{
				if (!handle.IsValid || handle.Index >= (uint32)mResources.Count)
					continue;

				let writer = latestWriter[handle.Index];
				if (writer.IsValid && writer.Index != (uint32)i)
				{
					bool found = false;
					for (let dep in pass.Dependencies)
					{
						if (dep == writer)
						{
							found = true;
							break;
						}
					}
					if (!found)
						pass.Dependencies.Add(writer);
				}
			}

			// Update latest writer for each output
			List<RGResourceHandle> outputs = scope .();
			pass.GetOutputs(outputs);

			for (let handle in outputs)
			{
				if (!handle.IsValid || handle.Index >= (uint32)mResources.Count)
					continue;

				latestWriter[handle.Index] = passHandle;
			}
		}
	}

	private Result<void> TopologicalSort()
	{
		mExecutionOrder.Clear();

		// Kahn's algorithm
		int32[] inDegree = scope int32[mPasses.Count];
		for (int i = 0; i < mPasses.Count; i++)
		{
			if (mPasses[i].IsCulled)
			{
				inDegree[i] = -1;
				continue;
			}
			inDegree[i] = (int32)mPasses[i].Dependencies.Count;
		}

		List<PassHandle> queue = scope .();

		for (int i = 0; i < mPasses.Count; i++)
		{
			if (inDegree[i] == 0)
				queue.Add(PassHandle() { Index = (uint32)i });
		}

		while (queue.Count > 0)
		{
			let handle = queue.PopFront();
			mExecutionOrder.Add(handle);
			mPasses[handle.Index].ExecutionOrder = (int32)(mExecutionOrder.Count - 1);

			for (int i = 0; i < mPasses.Count; i++)
			{
				if (inDegree[i] <= 0)
					continue;

				for (let dep in mPasses[i].Dependencies)
				{
					if (dep == handle)
					{
						inDegree[i]--;
						if (inDegree[i] == 0)
							queue.Add(PassHandle() { Index = (uint32)i });
						break;
					}
				}
			}
		}

		// Check for cycles
		int expectedCount = 0;
		for (let pass in mPasses)
		{
			if (!pass.IsCulled)
				expectedCount++;
		}

		if (mExecutionOrder.Count != expectedCount)
			return .Err;

		return .Ok;
	}

	private Result<void> AllocateResources()
	{
		for (let resource in mResources)
		{
			if (resource == null) // Skip freed slots
				continue;

			if (resource.RefCount > 0 || !resource.IsTransient)
			{
				// Try to acquire from pool for transient textures
				if (resource.IsTransient && resource.Type == .Texture && resource.Texture == null)
				{
					if (TryAcquireFromPool(resource))
						continue;
				}

				if (resource.Allocate(mDevice) case .Err)
					return .Err;
			}
		}

		// Discard unmatched pool entries (e.g., from a window resize)
		for (let pooled in mTexturePool)
			delete pooled;
		mTexturePool.Clear();

		return .Ok;
	}

	/// Tries to find a matching texture in the pool and assign it to the resource.
	private bool TryAcquireFromPool(RenderGraphResource resource)
	{
		for (int i = 0; i < mTexturePool.Count; i++)
		{
			let pooled = mTexturePool[i];
			if (pooled.Matches(resource.TextureDesc))
			{
				// Transfer ownership from pool to resource
				resource.Texture = pooled.Texture;
				resource.TextureView = pooled.TextureView;
				resource.DepthOnlyView = pooled.DepthOnlyView;

				// Null out pool entry and remove (don't delete the GPU resources)
				pooled.Texture = null;
				pooled.TextureView = null;
				pooled.DepthOnlyView = null;
				delete pooled;
				mTexturePool.RemoveAt(i);
				return true;
			}
		}
		return false;
	}

	private Result<void> ExecutePass(RenderPass pass, ICommandEncoder commandEncoder)
	{
		if (pass.Type == .Graphics)
			return ExecuteGraphicsPass(pass, commandEncoder);
		else if (pass.Type == .Compute)
			return ExecuteComputePass(pass, commandEncoder);
		else if (pass.Type == .Copy)
			return ExecuteCopyPass(pass, commandEncoder);

		return .Ok;
	}

	private Result<void> ExecuteGraphicsPass(RenderPass pass, ICommandEncoder commandEncoder)
	{
		// Build color attachments
		RenderPassColorAttachment[8] colorAttachments = default;
		int colorAttachmentCount = Math.Min(pass.ColorAttachments.Count, 8);

		for (int i = 0; i < colorAttachmentCount; i++)
		{
			let attachment = pass.ColorAttachments[i];
			if (let resource = GetResourceByHandle(attachment.Handle))
			{
				colorAttachments[i] = .()
				{
					View = resource.TextureView,
					LoadOp = attachment.LoadOp,
					StoreOp = attachment.StoreOp,
					ClearValue = attachment.ClearColor
				};
			}
		}

		// Build render pass descriptor
		var rpDesc = RenderPassDescriptor();
		rpDesc.ColorAttachments = .(&colorAttachments[0], colorAttachmentCount);

		// Depth attachment
		if (pass.DepthStencil.HasValue)
		{
			let attachment = pass.DepthStencil.Value;
			if (let resource = GetResourceByHandle(attachment.Handle))
			{
				rpDesc.DepthStencilAttachment = .()
				{
					View = resource.TextureView,
					DepthLoadOp = attachment.DepthLoadOp,
					DepthStoreOp = attachment.DepthStoreOp,
					StencilLoadOp = attachment.StencilLoadOp,
					StencilStoreOp = attachment.StencilStoreOp,
					DepthClearValue = attachment.ClearDepth,
					StencilClearValue = (uint32)attachment.ClearStencil,
					DepthReadOnly = attachment.ReadOnly,
					StencilReadOnly = attachment.ReadOnly
				};
			}
		}

		// Begin render pass
		let encoder = commandEncoder.BeginRenderPass(&rpDesc);
		if (encoder == null)
			return .Err;
		defer delete encoder;

		// Execute callback
		if (pass.ExecuteCallback != null)
			pass.ExecuteCallback(encoder);

		// End render pass
		encoder.End();

		return .Ok;
	}

	private Result<void> ExecuteComputePass(RenderPass pass, ICommandEncoder commandEncoder)
	{
		let encoder = commandEncoder.BeginComputePass();
		if (encoder == null)
			return .Err;
		defer delete encoder;

		if (pass.ComputeCallback != null)
			pass.ComputeCallback(encoder);

		encoder.End();

		return .Ok;
	}

	private Result<void> ExecuteCopyPass(RenderPass pass, ICommandEncoder commandEncoder)
	{
		// Copy passes execute directly on the command encoder without beginning a sub-pass
		if (pass.CopyCallback != null)
			pass.CopyCallback(commandEncoder);

		return .Ok;
	}

	// ========================================================================
	// Automatic Barrier Insertion
	// ========================================================================

	/// Gets the current layout for a texture, defaulting to Undefined if not tracked.
	private ResourceLayoutState GetTextureLayout(ITexture texture)
	{
		let key = TextureKey(texture);
		if (mTextureLayouts.TryGetValue(key, let layout))
			return layout;
		return .Undefined;
	}

	/// Sets the tracked layout for a texture.
	private void SetTextureLayout(ITexture texture, ResourceLayoutState layout)
	{
		let key = TextureKey(texture);
		mTextureLayouts[key] = layout;
	}

	/// Inserts barriers for resources that need layout transitions before this pass.
	///
	/// IMPORTANT: The Vulkan backend's render pass automatically handles layout transitions
	/// for color and depth attachments via initialLayout/finalLayout. For swapchain textures:
	/// - initialLayout = Undefined (with LoadOp.Clear)
	/// - finalLayout = Present
	///
	/// Therefore, we only insert barriers for:
	/// 1. Shader read textures (need ShaderReadOnly layout)
	/// 2. Storage/UAV writes (need General layout)
	///
	/// Color and depth attachments are handled by the render pass itself.
	private void InsertBarriersForPass(RenderPass pass, ICommandEncoder commandEncoder)
	{
		// Handle shader read textures - need ShaderReadOnly layout
		// These are textures being sampled in shaders, not render targets
		for (let handle in pass.Reads)
		{
			if (let resource = GetResourceByHandle(handle))
			{
				if (resource.Type == .Texture && resource.Texture != null)
				{
					let currentLayout = GetTextureLayout(resource.Texture);

					if (DebugLogLayouts)
						Console.WriteLine("[Barrier] Pass '{}' reading '{}': current={}, need=ShaderReadOnly",
							pass.Name, resource.Name, currentLayout);

					if (currentLayout != .ShaderReadOnly)
					{
						let oldLayout = ToTextureLayout(currentLayout);

						if (DebugLogLayouts)
							Console.WriteLine("[Barrier]   Issuing barrier: {} -> ShaderReadOnly", oldLayout);

						commandEncoder.TextureBarrier(resource.Texture, oldLayout, .ShaderReadOnly);
						SetTextureLayout(resource.Texture, .ShaderReadOnly);
					}
				}
			}
			else
			{
				if (DebugLogLayouts)
					Console.WriteLine("[Barrier] Pass '{}' reading handle {},{}: RESOURCE NOT FOUND",
						pass.Name, handle.Index, handle.Generation);
			}
		}

		// Handle depth attachments - need appropriate depth layout BEFORE render pass starts.
		// Read-only depth uses DepthStencilReadOnly (allows concurrent shader sampling).
		// Writable depth uses DepthStencilAttachment.
		if (pass.DepthStencil.HasValue)
		{
			let depthAtt = pass.DepthStencil.Value;
			if (let resource = GetResourceByHandle(depthAtt.Handle))
			{
				if (resource.Type == .Texture && resource.Texture != null)
				{
					let currentLayout = GetTextureLayout(resource.Texture);
					let targetLayout = depthAtt.ReadOnly ? ResourceLayoutState.DepthStencilReadOnly : ResourceLayoutState.DepthStencilAttachment;

					if (currentLayout != targetLayout && currentLayout != .Undefined)
					{
						let oldLayout = ToTextureLayout(currentLayout);
						let newLayout = ToTextureLayout(targetLayout);

						if (DebugLogLayouts)
							Console.WriteLine("[Barrier]   Issuing depth barrier: {} -> {}", oldLayout, newLayout);

						commandEncoder.TextureBarrier(resource.Texture, oldLayout, newLayout);
						SetTextureLayout(resource.Texture, targetLayout);
					}
				}
			}
		}

		// Handle color attachments - need ColorAttachment layout BEFORE render pass starts
		// Similar to depth attachments, if a color texture was used for shader reading,
		// we need to transition it back to ColorAttachment before the render pass.
		for (let attachment in pass.ColorAttachments)
		{
			if (let resource = GetResourceByHandle(attachment.Handle))
			{
				if (resource.Type == .Texture && resource.Texture != null)
				{
					let currentLayout = GetTextureLayout(resource.Texture);

					// If texture is not already in ColorAttachment (or Undefined/Present for swapchain),
					// we need to transition it explicitly
					if (currentLayout != .ColorAttachment && currentLayout != .Undefined && currentLayout != .Present)
					{
						let oldLayout = ToTextureLayout(currentLayout);

						if (DebugLogLayouts)
							Console.WriteLine("[Barrier]   Issuing color barrier: {} -> ColorAttachment", oldLayout);

						commandEncoder.TextureBarrier(resource.Texture, oldLayout, .ColorAttachment);
						SetTextureLayout(resource.Texture, .ColorAttachment);
					}
				}
			}
		}

		// Handle storage/UAV writes - need General layout
		for (let handle in pass.Writes)
		{
			if (let resource = GetResourceByHandle(handle))
			{
				if (resource.Type == .Texture && resource.Texture != null)
				{
					let currentLayout = GetTextureLayout(resource.Texture);
					if (currentLayout != .General)
					{
						let oldLayout = ToTextureLayout(currentLayout);
						commandEncoder.TextureBarrier(resource.Texture, oldLayout, .General);
						SetTextureLayout(resource.Texture, .General);
					}
				}
			}
		}
	}

	/// Updates resource layouts after a pass has executed.
	/// This is critical for tracking the finalLayout of render pass attachments,
	/// which Vulkan transitions automatically at the end of the render pass.
	private void UpdateLayoutsAfterPass(RenderPass pass)
	{
		// Update depth attachment layout based on whether it was read-only or writable
		if (pass.DepthStencil.HasValue)
		{
			let depthAtt = pass.DepthStencil.Value;
			if (let resource = GetResourceByHandle(depthAtt.Handle))
			{
				if (resource.Type == .Texture && resource.Texture != null)
				{
					let depthLayout = depthAtt.ReadOnly ? ResourceLayoutState.DepthStencilReadOnly : ResourceLayoutState.DepthStencilAttachment;
					if (DebugLogLayouts)
						Console.WriteLine("[Layout] Pass '{}' depth '{}': setting to {}",
							pass.Name, resource.Name, depthLayout);
					SetTextureLayout(resource.Texture, depthLayout);
				}
			}
		}

		// Update color attachment layouts
		// Swapchain textures are transitioned to Present by the render pass finalLayout
		// Non-swapchain textures stay in ColorAttachment
		for (let attachment in pass.ColorAttachments)
		{
			if (let resource = GetResourceByHandle(attachment.Handle))
			{
				if (resource.Type == .Texture && resource.Texture != null)
				{
					// Check if this is a present target (swapchain)
					bool isPresentTarget = false;
					for (let presentHandle in mPresentTargets)
					{
						if (presentHandle.Index == attachment.Handle.Index &&
							presentHandle.Generation == attachment.Handle.Generation)
						{
							isPresentTarget = true;
							break;
						}
					}

					if (isPresentTarget)
					{
						// Swapchain textures are transitioned to Present by the render pass
						SetTextureLayout(resource.Texture, .Present);
					}
					else
					{
						// Non-swapchain color attachments stay in ColorAttachment
						SetTextureLayout(resource.Texture, .ColorAttachment);
					}
				}
			}
		}
	}

	/// Converts ResourceLayoutState to RHI TextureLayout.
	private static TextureLayout ToTextureLayout(ResourceLayoutState state)
	{
		switch (state)
		{
		case .Undefined: return .Undefined;
		case .ColorAttachment: return .ColorAttachment;
		case .DepthStencilAttachment: return .DepthStencilAttachment;
		case .DepthStencilReadOnly: return .DepthStencilReadOnly;
		case .ShaderReadOnly: return .ShaderReadOnly;
		case .General: return .General;
		case .Present: return .Present;
		}
	}

	/// Flushes deferred deletions for a given frame slot.
	private void FlushDeferredDeletions(int32 frameIndex)
	{
		let list = mDeferredDeletions[frameIndex];
		for (let resource in list)
		{
			// Pool texture resources instead of destroying them
			if (resource.Type == .Texture && resource.Texture != null)
			{
				let pooled = new PooledTexture();
				pooled.Desc = resource.TextureDesc;
				pooled.Texture = resource.Texture;
				pooled.TextureView = resource.TextureView;
				pooled.DepthOnlyView = resource.DepthOnlyView;
				mTexturePool.Add(pooled);

				// Null out so destructor doesn't double-free
				resource.Texture = null;
				resource.TextureView = null;
				resource.DepthOnlyView = null;
			}
			else
			{
				resource.ReleaseTransient();
			}
			delete resource;
		}
		list.Clear();
	}

	public void Dispose()
	{
		// Flush all deferred deletion queues on shutdown
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			FlushDeferredDeletions((int32)i);
			delete mDeferredDeletions[i];
		}
	}
}
