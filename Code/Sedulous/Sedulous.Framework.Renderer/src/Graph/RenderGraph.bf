namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;

using internal Sedulous.Framework.Renderer;

/// Frame-based render graph for managing passes and resources.
///
/// The render graph:
/// - Tracks resource dependencies between passes
/// - Manages transient resource lifetimes
/// - Automatically inserts barriers for resource transitions
/// - Enables resource aliasing for memory efficiency
class RenderGraph
{
	private IDevice mDevice;
	private List<RenderPass> mPasses = new .() ~ DeleteContainerAndItems!(_);
	private List<ResourceNode> mResources = new .() ~ DeleteContainerAndItems!(_);
	private List<RenderPass> mSortedPasses = new .() ~ delete _;
	private bool mIsCompiled = false;

	// Transient resource pool
	private TransientResourcePool mTransientPool ~ delete _;

	// Frame state
	private uint32 mFrameIndex;
	private float mDeltaTime;
	private float mTotalTime;

	public this(IDevice device)
	{
		mDevice = device;
		mTransientPool = new TransientResourcePool(device);
	}

	/// Begins a new frame, resetting all passes and transient resources.
	public void BeginFrame(uint32 frameIndex, float deltaTime, float totalTime)
	{
		mFrameIndex = frameIndex;
		mDeltaTime = deltaTime;
		mTotalTime = totalTime;

		// Clear previous frame's state
		ClearAndDeleteItems!(mPasses);
		ClearAndDeleteItems!(mResources);
		mSortedPasses.Clear();
		mIsCompiled = false;
	}

	/// Creates a transient texture that lives only for this frame.
	public ResourceHandle CreateTransientTexture(StringView name, TextureDescriptor desc)
	{
		let index = (uint32)mResources.Count;
		let node = new ResourceNode(name, .Texture);
		node.TextureDesc = desc;
		node.IsImported = false;
		mResources.Add(node);
		return .(index, .Texture);
	}

	/// Creates a transient buffer that lives only for this frame.
	public ResourceHandle CreateTransientBuffer(StringView name, BufferDescriptor desc)
	{
		let index = (uint32)mResources.Count;
		let node = new ResourceNode(name, .Buffer);
		node.BufferDesc = desc;
		node.IsImported = false;
		mResources.Add(node);
		return .(index, .Buffer);
	}

	/// Imports an external texture into the graph.
	public ResourceHandle ImportTexture(StringView name, ITexture texture, ITextureView view, TextureLayout initialLayout = .Undefined)
	{
		let index = (uint32)mResources.Count;
		let node = new ResourceNode(name, .Texture);
		node.Texture = texture;
		node.TextureView = view;
		node.IsImported = true;
		node.CurrentLayout = initialLayout;
		mResources.Add(node);
		return .(index, .Texture);
	}

	/// Imports an external buffer into the graph.
	public ResourceHandle ImportBuffer(StringView name, IBuffer buffer)
	{
		let index = (uint32)mResources.Count;
		let node = new ResourceNode(name, .Buffer);
		node.Buffer = buffer;
		node.IsImported = true;
		mResources.Add(node);
		return .(index, .Buffer);
	}

	/// Adds a graphics pass to the graph.
	public PassBuilder AddGraphicsPass(StringView name)
	{
		let pass = new RenderPass(name, .Graphics);
		pass.Index = (uint32)mPasses.Count;
		mPasses.Add(pass);
		return .(this, pass);
	}

	/// Adds a compute pass to the graph.
	public PassBuilder AddComputePass(StringView name)
	{
		let pass = new RenderPass(name, .Compute);
		pass.Index = (uint32)mPasses.Count;
		mPasses.Add(pass);
		return .(this, pass);
	}

	/// Adds a transfer/copy pass to the graph.
	public PassBuilder AddTransferPass(StringView name)
	{
		let pass = new RenderPass(name, .Transfer);
		pass.Index = (uint32)mPasses.Count;
		mPasses.Add(pass);
		return .(this, pass);
	}

	/// Compiles the render graph, allocating resources and computing barriers.
	public void Compile()
	{
		if (mIsCompiled)
			return;

		// For now, use simple linear ordering (passes execute in declaration order)
		// TODO: Implement topological sort for more complex dependency graphs
		mSortedPasses.Clear();
		for (let pass in mPasses)
			mSortedPasses.Add(pass);

		// Allocate transient resources
		AllocateTransientResources();

		// Compute barriers
		ComputeBarriers();

		mIsCompiled = true;
	}

	/// Executes all passes in the graph.
	public void Execute(ICommandEncoder encoder)
	{
		if (!mIsCompiled)
			Compile();

		for (let pass in mSortedPasses)
		{
			ExecutePass(pass, encoder);
		}
	}

	/// Ends the frame, returning transient resources to the pool.
	public void EndFrame()
	{
		// Return transient resources to pool
		for (let node in mResources)
		{
			if (node.IsTransient)
			{
				if (node.Type == .Texture && node.Texture != null)
				{
					mTransientPool.ReturnTexture(node.Texture, node.TextureView, node.TextureDesc);
					node.Texture = null;
					node.TextureView = null;
				}
				else if (node.Type == .Buffer && node.Buffer != null)
				{
					mTransientPool.ReturnBuffer(node.Buffer, node.BufferDesc);
					node.Buffer = null;
				}
			}
		}
	}

	// ===== Internal Methods =====

	private void RecordResourceUsage(ResourceHandle handle, uint32 passIndex)
	{
		if (handle.Index < mResources.Count)
		{
			mResources[handle.Index].RecordUsage(passIndex);
		}
	}

	private ITexture GetResourceTexture(ResourceHandle handle)
	{
		if (handle.Index < mResources.Count && handle.Type == .Texture)
			return mResources[handle.Index].Texture;
		return null;
	}

	private ITextureView GetResourceTextureView(ResourceHandle handle)
	{
		if (handle.Index < mResources.Count && handle.Type == .Texture)
			return mResources[handle.Index].TextureView;
		return null;
	}

	private IBuffer GetResourceBuffer(ResourceHandle handle)
	{
		if (handle.Index < mResources.Count && handle.Type == .Buffer)
			return mResources[handle.Index].Buffer;
		return null;
	}

	private void AllocateTransientResources()
	{
		for (let node in mResources)
		{
			if (!node.IsTransient)
				continue;

			if (node.Type == .Texture)
			{
				let (texture, view) = mTransientPool.AcquireTexture(node.TextureDesc);
				node.Texture = texture;
				node.TextureView = view;
				node.CurrentLayout = .Undefined;
			}
			else if (node.Type == .Buffer)
			{
				node.Buffer = mTransientPool.AcquireBuffer(node.BufferDesc);
			}
		}
	}

	private void ComputeBarriers()
	{
		// Track current layout for each texture resource
		for (let pass in mSortedPasses)
		{
			pass.PreBarriers.Clear();

			// Check reads for required transitions
			for (let dep in pass.Reads)
			{
				if (dep.Handle.Type != .Texture)
					continue;

				let node = mResources[dep.Handle.Index];
				if (node.CurrentLayout != dep.RequiredLayout)
				{
					pass.PreBarriers.Add(.()
					{
						Handle = dep.Handle,
						OldLayout = node.CurrentLayout,
						NewLayout = dep.RequiredLayout
					});
					node.CurrentLayout = dep.RequiredLayout;
				}
			}

			// Check writes for required transitions
			for (let dep in pass.Writes)
			{
				if (dep.Handle.Type != .Texture)
					continue;

				let node = mResources[dep.Handle.Index];
				if (node.CurrentLayout != dep.RequiredLayout)
				{
					pass.PreBarriers.Add(.()
					{
						Handle = dep.Handle,
						OldLayout = node.CurrentLayout,
						NewLayout = dep.RequiredLayout
					});
					node.CurrentLayout = dep.RequiredLayout;
				}
			}
		}
	}

	private void ExecutePass(RenderPass pass, ICommandEncoder encoder)
	{
		// Insert barriers
		for (let barrier in pass.PreBarriers)
		{
			let texture = GetResourceTexture(barrier.Handle);
			if (texture != null)
			{
				encoder.TextureBarrier(texture, barrier.OldLayout, barrier.NewLayout);
			}
		}

		// Execute based on pass type
		switch (pass.Type)
		{
		case .Graphics:
			ExecuteGraphicsPass(pass, encoder);
		case .Compute:
			ExecuteComputePass(pass, encoder);
		case .Transfer:
			ExecuteTransferPass(pass, encoder);
		}
	}

	private void ExecuteGraphicsPass(RenderPass pass, ICommandEncoder encoder)
	{
		// Build render pass descriptor
		var colorAttachments = scope RenderPassColorAttachment[pass.ColorAttachments.Count];
		for (int i = 0; i < pass.ColorAttachments.Count; i++)
		{
			let att = pass.ColorAttachments[i];
			let view = GetResourceTextureView(att.Target);
			colorAttachments[i] = .(view)
			{
				LoadOp = att.LoadOp,
				StoreOp = att.StoreOp,
				ClearValue = att.ClearColor
			};
		}

		RenderPassDescriptor passDesc = .(colorAttachments);

		if (pass.DepthAttachment.HasValue)
		{
			let att = pass.DepthAttachment.Value;
			let view = GetResourceTextureView(att.Target);
			passDesc.DepthStencilAttachment = .(view)
			{
				DepthLoadOp = att.DepthLoadOp,
				DepthStoreOp = att.DepthStoreOp,
				StencilLoadOp = att.StencilLoadOp,
				StencilStoreOp = att.StencilStoreOp,
				DepthClearValue = att.ClearDepth,
				StencilClearValue = att.ClearStencil
			};
		}

		let renderPass = encoder.BeginRenderPass(&passDesc);
		if (renderPass != null)
		{
			defer { renderPass.End(); delete renderPass; }

			if (pass.Execute != null)
			{
				PassExecuteContext ctx = .()
				{
					Graph = this,
					Device = mDevice,
					Encoder = encoder,
					RenderPass = renderPass,
					FrameIndex = mFrameIndex,
					DeltaTime = mDeltaTime,
					TotalTime = mTotalTime
				};
				pass.Execute(ctx);
			}
		}
	}

	private void ExecuteComputePass(RenderPass pass, ICommandEncoder encoder)
	{
		let computePass = encoder.BeginComputePass();
		if (computePass != null)
		{
			defer { computePass.End(); delete computePass; }

			if (pass.Execute != null)
			{
				PassExecuteContext ctx = .()
				{
					Graph = this,
					Device = mDevice,
					Encoder = encoder,
					ComputePass = computePass,
					FrameIndex = mFrameIndex,
					DeltaTime = mDeltaTime,
					TotalTime = mTotalTime
				};
				pass.Execute(ctx);
			}
		}
	}

	private void ExecuteTransferPass(RenderPass pass, ICommandEncoder encoder)
	{
		if (pass.Execute != null)
		{
			PassExecuteContext ctx = .()
			{
				Graph = this,
				Device = mDevice,
				Encoder = encoder,
				FrameIndex = mFrameIndex,
				DeltaTime = mDeltaTime,
				TotalTime = mTotalTime
			};
			pass.Execute(ctx);
		}
	}
}
