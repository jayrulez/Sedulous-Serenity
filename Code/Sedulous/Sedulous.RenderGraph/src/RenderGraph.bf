using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Foundation.Mathematics;

namespace Sedulous.RenderGraph;

using internal Sedulous.RenderGraph;

/// Callback for setting up a pass (declaring resource dependencies).
public delegate void PassSetupCallback(RenderGraphBuilder builder);

/// A frame graph that describes rendering work as a DAG of passes with
/// declared resource dependencies.
///
/// Usage per frame:
///   1. Reset()
///   2. Import external resources (ImportTexture, ImportBuffer)
///   3. Create transient resources (CreateTexture, CreateBuffer)
///   4. Declare passes (AddRasterPass, AddComputePass, AddTransferPass)
///   5. Compile() — resolves dependencies, culls unused passes, allocates transients
///   6. Execute(device) — inserts barriers, runs passes in order
///
public class RenderGraph
{
	private List<RenderGraphResource> mResources = new .() ~ DeleteContainerAndItems!(_);
	private List<RenderGraphPass> mPasses = new .() ~ DeleteContainerAndItems!(_);
	private List<int32> mExecutionOrder = new .() ~ delete _;
	private TransientResourcePool mPool;
	private bool mCompiled = false;

	public this(TransientResourcePool pool)
	{
		mPool = pool;
	}

	// ===== Resource Declaration =====

	/// Imports an externally managed texture into the graph.
	/// The graph tracks its layout but does not manage its lifetime.
	public ResourceHandle ImportTexture(StringView name, ITexture texture, ITextureView view,
		TextureLayout initialLayout = .Undefined)
	{
		let index = (uint16)mResources.Count;
		let resource = new RenderGraphResource();
		resource.Name.Set(name);
		resource.Type = .Texture;
		resource.Imported = true;
		resource.ImportedTexture = texture;
		resource.ImportedTextureView = view;
		resource.CurrentLayout = initialLayout;
		mResources.Add(resource);
		return ResourceHandle(index, 0);
	}

	/// Imports an externally managed buffer into the graph.
	public ResourceHandle ImportBuffer(StringView name, IBuffer buffer)
	{
		let index = (uint16)mResources.Count;
		let resource = new RenderGraphResource();
		resource.Name.Set(name);
		resource.Type = .Buffer;
		resource.Imported = true;
		resource.ImportedBuffer = buffer;
		mResources.Add(resource);
		return ResourceHandle(index, 0);
	}

	/// Declares a transient texture that lives only within this frame.
	/// The actual GPU resource is allocated during Compile().
	public ResourceHandle CreateTexture(StringView name, TextureDescriptor desc)
	{
		let index = (uint16)mResources.Count;
		let resource = new RenderGraphResource();
		resource.Name.Set(name);
		resource.Type = .Texture;
		resource.Imported = false;
		resource.TextureDesc = desc;
		resource.CurrentLayout = .Undefined;
		mResources.Add(resource);
		return ResourceHandle(index, 0);
	}

	/// Declares a transient buffer that lives only within this frame.
	public ResourceHandle CreateBuffer(StringView name, BufferDescriptor desc)
	{
		let index = (uint16)mResources.Count;
		let resource = new RenderGraphResource();
		resource.Name.Set(name);
		resource.Type = .Buffer;
		resource.Imported = false;
		resource.BufferDesc = desc;
		mResources.Add(resource);
		return ResourceHandle(index, 0);
	}

	// ===== Pass Declaration =====

	/// Adds a raster pass that renders to color/depth attachments.
	public void AddRasterPass(StringView name, PassSetupCallback setup, RasterPassExecute execute)
	{
		let pass = CreatePass(name, .Raster);
		var builder = RenderGraphBuilder(this, pass);
		setup(builder);
		pass.RasterExecute = execute;
		delete setup;
	}

	/// Adds a compute pass that dispatches compute work.
	public void AddComputePass(StringView name, PassSetupCallback setup, ComputePassExecute execute)
	{
		let pass = CreatePass(name, .Compute);
		var builder = RenderGraphBuilder(this, pass);
		setup(builder);
		pass.ComputeExecute = execute;
		delete setup;
	}

	/// Adds a transfer pass for copy/blit operations.
	public void AddTransferPass(StringView name, PassSetupCallback setup, TransferPassExecute execute)
	{
		let pass = CreatePass(name, .Transfer);
		var builder = RenderGraphBuilder(this, pass);
		setup(builder);
		pass.TransferExecute = execute;
		delete setup;
	}

	// ===== Compilation =====

	/// Compiles the render graph: resolves dependencies, culls unused passes,
	/// determines resource lifetimes, and allocates transient resources.
	public Result<void> Compile(IDevice device)
	{
		if (mCompiled)
			return .Ok;

		// Step 1: Determine execution order (currently just declaration order
		// since passes are declared in dependency order by the setup callbacks)
		mExecutionOrder.Clear();
		for (int32 i = 0; i < (int32)mPasses.Count; i++)
			mExecutionOrder.Add(i);

		// Step 2: Cull unused passes (back-propagate from side-effect passes)
		CullPasses();

		// Step 3: Compute resource lifetimes
		ComputeResourceLifetimes();

		// Step 4: Allocate transient resources
		if (AllocateTransientResources(device) case .Err)
			return .Err;

		mCompiled = true;
		return .Ok;
	}

	/// Executes the compiled render graph, inserting barriers and dispatching passes.
	/// Returns the submitted command buffer. Caller owns the returned buffer and must
	/// defer deletion until the GPU has finished executing it (typically next frame after fence wait).
	public ICommandBuffer Execute(IDevice device)
	{
		if (!mCompiled)
			return null;

		let encoder = device.CreateCommandEncoder();

		for (let passIndex in mExecutionOrder)
		{
			let pass = mPasses[passIndex];
			if (pass.Culled)
				continue;

			switch (pass.Type)
			{
			case .Raster:
				ExecuteRasterPass(encoder, pass);
			case .Compute:
				ExecuteComputePass(encoder, pass);
			case .Transfer:
				ExecuteTransferPass(encoder, pass);
			}
		}

		let commandBuffer = encoder.Finish();
		device.Queue.Submit(commandBuffer);
		delete encoder;
		return commandBuffer;
	}

	/// Executes the compiled render graph with a swap chain for presentation sync.
	/// Returns the submitted command buffer. Caller owns the returned buffer and must
	/// defer deletion until the GPU has finished executing it (typically next frame after fence wait).
	public ICommandBuffer Execute(IDevice device, ISwapChain swapChain)
	{
		if (!mCompiled)
			return null;

		let encoder = device.CreateCommandEncoder();

		for (let passIndex in mExecutionOrder)
		{
			let pass = mPasses[passIndex];
			if (pass.Culled)
				continue;

			switch (pass.Type)
			{
			case .Raster:
				ExecuteRasterPass(encoder, pass);
			case .Compute:
				ExecuteComputePass(encoder, pass);
			case .Transfer:
				ExecuteTransferPass(encoder, pass);
			}
		}

		let commandBuffer = encoder.Finish();
		device.Queue.Submit(commandBuffer, swapChain);
		delete encoder;
		return commandBuffer;
	}

	/// Resets the graph for the next frame.
	/// Must be called at the start of each frame before declaring new passes.
	public void Reset()
	{
		DeleteContainerAndItems!(mPasses);
		mPasses = new .();
		DeleteContainerAndItems!(mResources);
		mResources = new .();
		mExecutionOrder.Clear();
		mCompiled = false;
	}

	// ===== Internal: Pass Helpers =====

	private RenderGraphPass CreatePass(StringView name, PassType type)
	{
		let pass = new RenderGraphPass();
		pass.Name.Set(name);
		pass.Type = type;
		pass.Index = (int32)mPasses.Count;
		mPasses.Add(pass);
		return pass;
	}

	/// Increments the version of a resource handle (called by builder on write).
	private ResourceHandle IncrementVersion(ResourceHandle handle)
	{
		if (handle.Index < mResources.Count)
		{
			let resource = mResources[handle.Index];
			resource.CurrentVersion++;
			return ResourceHandle(handle.Index, resource.CurrentVersion);
		}
		return handle;
	}

	/// Tracks resource usage for lifetime computation.
	private void TrackResourceUsage(uint16 resourceIndex, int32 passIndex)
	{
		if (resourceIndex < mResources.Count)
		{
			let resource = mResources[resourceIndex];
			if (resource.FirstPassIndex < 0)
				resource.FirstPassIndex = passIndex;
			resource.LastPassIndex = Math.Max(resource.LastPassIndex, passIndex);
		}
	}

	// ===== Internal: Compilation =====

	/// Culls passes that don't contribute to any side-effect.
	/// Works backwards: side-effect passes are roots, their read dependencies
	/// are traced back to mark contributing passes as needed.
	private void CullPasses()
	{
		// Reset ref counts
		for (let pass in mPasses)
		{
			pass.RefCount = pass.HasSideEffect ? 1 : 0;
			pass.Culled = false;
		}

		// Build a map: resource handle → writing pass
		Dictionary<int, int32> resourceWriter = scope .();
		for (let pass in mPasses)
		{
			for (let write in pass.Writes)
				resourceWriter[write.GetHashCode()] = pass.Index;
		}

		// Back-propagate from passes with refs
		List<int32> stack = scope .();
		for (let pass in mPasses)
		{
			if (pass.RefCount > 0)
				stack.Add(pass.Index);
		}

		while (stack.Count > 0)
		{
			let idx = stack.PopBack();
			let pass = mPasses[idx];

			for (let read in pass.Reads)
			{
				if (resourceWriter.TryGetValue(read.GetHashCode(), let writerIdx))
				{
					let writer = mPasses[writerIdx];
					if (writer.RefCount == 0)
						stack.Add(writerIdx);
					writer.RefCount++;
				}
			}
		}

		// Mark unreferenced passes as culled
		for (let pass in mPasses)
		{
			if (pass.RefCount == 0)
				pass.Culled = true;
		}
	}

	/// Computes first/last pass indices for each resource (for transient lifetimes).
	private void ComputeResourceLifetimes()
	{
		// Already tracked incrementally by TrackResourceUsage during setup.
		// This method can be extended for more sophisticated analysis.
	}

	/// Allocates transient resources from the pool.
	private Result<void> AllocateTransientResources(IDevice device)
	{
		for (let resource in mResources)
		{
			if (resource.Imported)
				continue;

			// Only allocate if actually used
			if (resource.FirstPassIndex < 0)
				continue;

			switch (resource.Type)
			{
			case .Texture:
				if (mPool.AcquireTexture(resource.TextureDesc) case .Ok(let result))
				{
					resource.PhysicalTexture = result.texture;
					resource.PhysicalTextureView = result.view;
				}
				else
					return .Err;
			case .Buffer:
				if (mPool.AcquireBuffer(resource.BufferDesc) case .Ok(let buffer))
					resource.PhysicalBuffer = buffer;
				else
					return .Err;
			}
		}
		return .Ok;
	}

	// ===== Internal: Execution =====

	/// Determines the required texture layout for how a resource is used in a pass.
	private TextureLayout GetRequiredLayout(RenderGraphPass pass, ResourceHandle handle)
	{
		// Check if it's a color attachment
		for (let attachment in pass.ColorAttachments)
		{
			if (attachment.Handle.Index == handle.Index)
				return .ColorAttachment;
		}

		// Check if it's a depth/stencil attachment
		if (pass.DepthStencilAttachment.HasValue)
		{
			let dsa = pass.DepthStencilAttachment.Value;
			if (dsa.Handle.Index == handle.Index)
				return dsa.ReadOnly ? .DepthStencilReadOnly : .DepthStencilAttachment;
		}

		// Check if it's a read (sampled texture)
		for (let read in pass.Reads)
		{
			if (read.Index == handle.Index)
				return .ShaderReadOnly;
		}

		return .General;
	}

	/// Inserts barriers for all resources used by a pass.
	private void InsertBarriers(ICommandEncoder encoder, RenderGraphPass pass)
	{
		// Transition read resources
		for (let read in pass.Reads)
		{
			if (read.Index >= mResources.Count)
				continue;
			let resource = mResources[read.Index];
			if (resource.Type != .Texture)
				continue;
			let texture = resource.Texture;
			if (texture == null)
				continue;

			let requiredLayout = GetRequiredLayout(pass, read);
			if (resource.CurrentLayout != requiredLayout)
			{
				encoder.TextureBarrier(texture, resource.CurrentLayout, requiredLayout);
				resource.CurrentLayout = requiredLayout;
			}
		}

		// Transition write resources (color attachments)
		for (let attachment in pass.ColorAttachments)
		{
			if (attachment.Handle.Index >= mResources.Count)
				continue;
			let resource = mResources[attachment.Handle.Index];
			if (resource.Type != .Texture)
				continue;
			let texture = resource.Texture;
			if (texture == null)
				continue;

			if (resource.CurrentLayout != .ColorAttachment)
			{
				encoder.TextureBarrier(texture, resource.CurrentLayout, .ColorAttachment);
				resource.CurrentLayout = .ColorAttachment;
			}
		}

		// Transition depth/stencil attachment
		if (pass.DepthStencilAttachment.HasValue)
		{
			let dsa = pass.DepthStencilAttachment.Value;
			if (dsa.Handle.Index < mResources.Count)
			{
				let resource = mResources[dsa.Handle.Index];
				if (resource.Type == .Texture)
				{
					let texture = resource.Texture;
					if (texture != null)
					{
						let requiredLayout = dsa.ReadOnly ?
							TextureLayout.DepthStencilReadOnly : TextureLayout.DepthStencilAttachment;
						if (resource.CurrentLayout != requiredLayout)
						{
							encoder.TextureBarrier(texture, resource.CurrentLayout, requiredLayout);
							resource.CurrentLayout = requiredLayout;
						}
					}
				}
			}
		}
	}

	/// Executes a raster pass: inserts barriers, builds RenderPassDescriptor,
	/// begins the pass, calls user callback, ends the pass.
	private void ExecuteRasterPass(ICommandEncoder encoder, RenderGraphPass pass)
	{
		InsertBarriers(encoder, pass);

		// Build color attachments
		int colorCount = pass.ColorAttachments.Count;
		RenderPassColorAttachment[] colorAttachments = scope .[colorCount];

		for (int i = 0; i < colorCount; i++)
		{
			let pa = pass.ColorAttachments[i];
			let resource = mResources[pa.Handle.Index];
			colorAttachments[i] = RenderPassColorAttachment()
			{
				View = resource.TextureView,
				LoadOp = pa.LoadOp,
				StoreOp = pa.StoreOp,
				ClearValue = pa.ClearColor
			};
		}

		// Build descriptor
		RenderPassDescriptor desc = .(colorAttachments)
		{
			Label = pass.Name
		};

		// Add depth/stencil if present
		if (pass.DepthStencilAttachment.HasValue)
		{
			let dsa = pass.DepthStencilAttachment.Value;
			let resource = mResources[dsa.Handle.Index];
			desc.DepthStencilAttachment = RenderPassDepthStencilAttachment()
			{
				View = resource.TextureView,
				DepthLoadOp = dsa.DepthLoadOp,
				DepthStoreOp = dsa.DepthStoreOp,
				DepthClearValue = dsa.DepthClearValue,
				DepthReadOnly = dsa.ReadOnly
			};
		}

		let renderPassEncoder = encoder.BeginRenderPass(&desc);

		if (pass.RasterExecute != null)
			pass.RasterExecute(renderPassEncoder);

		renderPassEncoder.End();

		delete renderPassEncoder;
	}

	/// Executes a compute pass.
	private void ExecuteComputePass(ICommandEncoder encoder, RenderGraphPass pass)
	{
		InsertBarriers(encoder, pass);

		let computeEncoder = encoder.BeginComputePass(pass.Name);

		if (pass.ComputeExecute != null)
			pass.ComputeExecute(computeEncoder);

		computeEncoder.End();
	}

	/// Executes a transfer pass.
	private void ExecuteTransferPass(ICommandEncoder encoder, RenderGraphPass pass)
	{
		InsertBarriers(encoder, pass);

		if (pass.TransferExecute != null)
			pass.TransferExecute(encoder);
	}

	// ===== Queries =====

	/// Gets the number of declared passes.
	public int PassCount => mPasses.Count;

	/// Gets the number of declared resources.
	public int ResourceCount => mResources.Count;

	/// Gets the actual texture for a resource handle (valid after Compile).
	public ITexture GetTexture(ResourceHandle handle)
	{
		if (handle.Index < mResources.Count)
			return mResources[handle.Index].Texture;
		return null;
	}

	/// Gets the actual texture view for a resource handle (valid after Compile).
	public ITextureView GetTextureView(ResourceHandle handle)
	{
		if (handle.Index < mResources.Count)
			return mResources[handle.Index].TextureView;
		return null;
	}

	/// Gets the actual buffer for a resource handle (valid after Compile).
	public IBuffer GetBuffer(ResourceHandle handle)
	{
		if (handle.Index < mResources.Count)
			return mResources[handle.Index].Buffer;
		return null;
	}

	/// Transitions an imported resource to a specific layout.
	/// Useful for transitioning back to Present layout before presenting.
	public void TransitionToPresent(ICommandEncoder encoder, ResourceHandle handle)
	{
		if (handle.Index < mResources.Count)
		{
			let resource = mResources[handle.Index];
			if (resource.Type == .Texture && resource.Texture != null)
			{
				if (resource.CurrentLayout != .Present)
				{
					encoder.TextureBarrier(resource.Texture, resource.CurrentLayout, .Present);
					resource.CurrentLayout = .Present;
				}
			}
		}
	}
}
