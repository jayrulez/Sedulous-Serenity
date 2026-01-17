namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;

/// Render graph that manages pass dependencies and resource lifetimes.
public class RenderGraph : IDisposable
{
	private IDevice mDevice;

	// Resources
	private List<RenderGraphResource> mResources = new .() ~ DeleteContainerAndItems!(_);
	private Dictionary<String, RGResourceHandle> mResourceNames = new .() ~ DeleteDictionaryAndKeys!(_);

	// Passes
	private List<RenderPass> mPasses = new .() ~ DeleteContainerAndItems!(_);
	private List<PassHandle> mExecutionOrder = new .() ~ delete _;

	// Frame state
	private bool mIsBuilding = false;
	private bool mIsCompiled = false;

	// Statistics
	public int32 PassCount => (int32)mPasses.Count;
	public int32 ResourceCount => (int32)mResources.Count;
	public int32 CulledPassCount { get; private set; }

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Begins building the render graph for a new frame.
	public void BeginFrame()
	{
		// Clear previous frame passes
		for (let pass in mPasses)
			delete pass;
		mPasses.Clear();

		// Reset transient resources
		for (int i = mResources.Count - 1; i >= 0; i--)
		{
			let resource = mResources[i];
			if (resource.IsTransient)
			{
				resource.ReleaseTransient();

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

				delete resource;
				mResources.RemoveAt(i);
			}
			else
			{
				// Reset tracking for imported resources
				resource.RefCount = 0;
				resource.FirstWriter = .Invalid;
				resource.LastReader = .Invalid;
			}
		}

		mExecutionOrder.Clear();
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
	public RGResourceHandle ImportTexture(StringView name, ITexture texture, ITextureView view)
	{
		let nameStr = scope String(name);
		if (mResourceNames.TryGetValue(nameStr, let existing))
			return existing;

		let resource = RenderGraphResource.ImportTexture(name, texture, view);
		return AddResource(resource, name);
	}

	/// Imports an external buffer.
	public RGResourceHandle ImportBuffer(StringView name, IBuffer buffer)
	{
		let nameStr = scope String(name);
		if (mResourceNames.TryGetValue(nameStr, let existing))
			return existing;

		let resource = RenderGraphResource.ImportBuffer(name, buffer);
		return AddResource(resource, name);
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

		// Build resource references
		BuildResourceReferences();

		// Cull unused passes
		CullPasses();

		// Build pass dependencies
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

			if (ExecutePass(pass, commandEncoder) case .Err)
				return .Err;
		}

		return .Ok;
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
		let handle = RGResourceHandle() { Index = (uint32)mResources.Count, Generation = resource.Generation };
		mResources.Add(resource);

		let nameKey = new String(name);
		mResourceNames[nameKey] = handle;

		return handle;
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

	private void BuildDependencies()
	{
		for (int i = 0; i < mPasses.Count; i++)
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
					if (resource.FirstWriter.IsValid && resource.FirstWriter.Index != (uint32)i)
					{
						// Check if dependency already exists
						bool found = false;
						for (let dep in pass.Dependencies)
						{
							if (dep == resource.FirstWriter)
							{
								found = true;
								break;
							}
						}
						if (!found)
							pass.Dependencies.Add(resource.FirstWriter);
					}
				}
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
			if (resource.RefCount > 0 || !resource.IsTransient)
			{
				if (resource.Allocate(mDevice) case .Err)
					return .Err;
			}
		}
		return .Ok;
	}

	private Result<void> ExecutePass(RenderPass pass, ICommandEncoder commandEncoder)
	{
		if (pass.Type == .Graphics)
			return ExecuteGraphicsPass(pass, commandEncoder);
		else if (pass.Type == .Compute)
			return ExecuteComputePass(pass, commandEncoder);

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

		if (pass.ComputeCallback != null)
			pass.ComputeCallback(encoder);

		encoder.End();

		return .Ok;
	}

	public void Dispose()
	{
	}
}
