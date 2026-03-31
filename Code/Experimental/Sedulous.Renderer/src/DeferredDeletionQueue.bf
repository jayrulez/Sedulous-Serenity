namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;

/// General-purpose deferred GPU resource deletion queue.
/// Resources are queued for deletion and destroyed after a safe number of
/// frames have elapsed (FrameBufferCount + 1), guaranteeing no in-flight
/// command buffers reference them.
///
/// Usage:
///   queue.Enqueue(device, textureView);   // mark for deferred deletion
///   queue.ProcessDeletions(frameNumber);   // call each BeginFrame
class DeferredDeletionQueue
{
	private enum ResourceType
	{
		Buffer,
		Texture,
		TextureView,
		Sampler,
		BindGroup,
		BindGroupLayout,
		RenderPipeline,
		ComputePipeline,
		PipelineLayout,
		ShaderModule,
	}

	private struct PendingDeletion
	{
		public ResourceType Type;
		public uint64 FrameNumber;
		// Store the resource as a void* since we can't have a union of interfaces.
		// The Type field tells us how to cast and destroy it.
		public void* Resource;
	}

	private List<PendingDeletion> mPending = new .() ~ delete _;
	private IDevice mDevice;

	/// Frames to wait before deleting (in-flight frame count + 1 for safety).
	private uint64 mDeletionDelay;

	public this(IDevice device, int frameBufferCount = RenderConfig.FrameBufferCount)
	{
		mDevice = device;
		mDeletionDelay = (uint64)(frameBufferCount + 1);
	}

	/// Enqueues a buffer for deferred deletion.
	public void Enqueue(uint64 frameNumber, IBuffer resource)
	{
		if (resource == null) return;
		mPending.Add(.() { Type = .Buffer, FrameNumber = frameNumber, Resource = Internal.UnsafeCastToPtr(resource) });
	}

	/// Enqueues a texture for deferred deletion.
	public void Enqueue(uint64 frameNumber, ITexture resource)
	{
		if (resource == null) return;
		mPending.Add(.() { Type = .Texture, FrameNumber = frameNumber, Resource = Internal.UnsafeCastToPtr(resource) });
	}

	/// Enqueues a texture view for deferred deletion.
	public void Enqueue(uint64 frameNumber, ITextureView resource)
	{
		if (resource == null) return;
		mPending.Add(.() { Type = .TextureView, FrameNumber = frameNumber, Resource = Internal.UnsafeCastToPtr(resource) });
	}

	/// Enqueues a sampler for deferred deletion.
	public void Enqueue(uint64 frameNumber, ISampler resource)
	{
		if (resource == null) return;
		mPending.Add(.() { Type = .Sampler, FrameNumber = frameNumber, Resource = Internal.UnsafeCastToPtr(resource) });
	}

	/// Enqueues a bind group for deferred deletion.
	public void Enqueue(uint64 frameNumber, IBindGroup resource)
	{
		if (resource == null) return;
		mPending.Add(.() { Type = .BindGroup, FrameNumber = frameNumber, Resource = Internal.UnsafeCastToPtr(resource) });
	}

	/// Enqueues a bind group layout for deferred deletion.
	public void Enqueue(uint64 frameNumber, IBindGroupLayout resource)
	{
		if (resource == null) return;
		mPending.Add(.() { Type = .BindGroupLayout, FrameNumber = frameNumber, Resource = Internal.UnsafeCastToPtr(resource) });
	}

	/// Enqueues a render pipeline for deferred deletion.
	public void Enqueue(uint64 frameNumber, IRenderPipeline resource)
	{
		if (resource == null) return;
		mPending.Add(.() { Type = .RenderPipeline, FrameNumber = frameNumber, Resource = Internal.UnsafeCastToPtr(resource) });
	}

	/// Enqueues a compute pipeline for deferred deletion.
	public void Enqueue(uint64 frameNumber, IComputePipeline resource)
	{
		if (resource == null) return;
		mPending.Add(.() { Type = .ComputePipeline, FrameNumber = frameNumber, Resource = Internal.UnsafeCastToPtr(resource) });
	}

	/// Enqueues a pipeline layout for deferred deletion.
	public void Enqueue(uint64 frameNumber, IPipelineLayout resource)
	{
		if (resource == null) return;
		mPending.Add(.() { Type = .PipelineLayout, FrameNumber = frameNumber, Resource = Internal.UnsafeCastToPtr(resource) });
	}

	/// Processes pending deletions. Destroys resources whose frame delay has elapsed.
	/// Call once per frame in BeginFrame after the fence wait.
	public void ProcessDeletions(uint64 currentFrame)
	{
		for (int i = mPending.Count - 1; i >= 0; i--)
		{
			let pending = mPending[i];
			if (currentFrame >= pending.FrameNumber + mDeletionDelay)
			{
				DestroyResource(pending);
				mPending.RemoveAtFast(i);
			}
		}
	}

	/// Flushes all pending deletions immediately (call at shutdown when GPU is idle).
	public void Flush()
	{
		for (let pending in mPending)
			DestroyResource(pending);
		mPending.Clear();
	}

	/// Number of pending deletions.
	public int PendingCount => mPending.Count;

	private void DestroyResource(PendingDeletion pending)
	{
		switch (pending.Type)
		{
		case .Buffer:
			var res = (IBuffer)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroyBuffer(ref res);
		case .Texture:
			var res = (ITexture)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroyTexture(ref res);
		case .TextureView:
			var res = (ITextureView)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroyTextureView(ref res);
		case .Sampler:
			var res = (ISampler)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroySampler(ref res);
		case .BindGroup:
			var res = (IBindGroup)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroyBindGroup(ref res);
		case .BindGroupLayout:
			var res = (IBindGroupLayout)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroyBindGroupLayout(ref res);
		case .RenderPipeline:
			var res = (IRenderPipeline)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroyRenderPipeline(ref res);
		case .ComputePipeline:
			var res = (IComputePipeline)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroyComputePipeline(ref res);
		case .PipelineLayout:
			var res = (IPipelineLayout)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroyPipelineLayout(ref res);
		case .ShaderModule:
			var res = (IShaderModule)Internal.UnsafeCastToObject(pending.Resource);
			mDevice.DestroyShaderModule(ref res);
		}
	}
}
