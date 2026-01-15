namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;

/// Type of resource queued for deletion.
enum DeferredResourceType : uint8
{
	Buffer,
	Texture,
	TextureView,
	Sampler,
	BindGroup,
	BindGroupLayout,
	PipelineLayout,
	RenderPipeline,
	ComputePipeline,
	ShaderModule
}

/// Entry in the deferred deletion queue.
struct DeferredDeletionEntry
{
	/// Frame index when the resource was queued for deletion.
	public uint32 QueuedFrame;

	/// Type of resource.
	public DeferredResourceType Type;

	/// Pointer to the resource (cast to appropriate type based on Type).
	public void* Resource;

	public this(uint32 frame, DeferredResourceType type, void* resource)
	{
		QueuedFrame = frame;
		Type = type;
		Resource = resource;
	}
}

/// Deferred deletion queue for GPU resources.
/// Resources are queued for deletion and only actually deleted after
/// a sufficient number of frames have passed to ensure the GPU is done using them.
class DeferredDeletionQueue
{
	private List<DeferredDeletionEntry> mQueue = new .() ~ delete _;
	private uint32 mCurrentFrame = 0;

	/// Gets the number of resources pending deletion.
	public int PendingCount => mQueue.Count;

	/// Updates the current frame index.
	/// Call this at the start of each frame.
	public void BeginFrame(uint32 frameIndex)
	{
		mCurrentFrame = frameIndex;
	}

	/// Queues a buffer for deferred deletion.
	public void QueueBuffer(IBuffer buffer)
	{
		if (buffer != null)
			mQueue.Add(.(mCurrentFrame, .Buffer, Internal.UnsafeCastToPtr(buffer)));
	}

	/// Queues a texture for deferred deletion.
	public void QueueTexture(ITexture texture)
	{
		if (texture != null)
			mQueue.Add(.(mCurrentFrame, .Texture, Internal.UnsafeCastToPtr(texture)));
	}

	/// Queues a texture view for deferred deletion.
	public void QueueTextureView(ITextureView view)
	{
		if (view != null)
			mQueue.Add(.(mCurrentFrame, .TextureView, Internal.UnsafeCastToPtr(view)));
	}

	/// Queues a sampler for deferred deletion.
	public void QueueSampler(ISampler sampler)
	{
		if (sampler != null)
			mQueue.Add(.(mCurrentFrame, .Sampler, Internal.UnsafeCastToPtr(sampler)));
	}

	/// Queues a bind group for deferred deletion.
	public void QueueBindGroup(IBindGroup bindGroup)
	{
		if (bindGroup != null)
			mQueue.Add(.(mCurrentFrame, .BindGroup, Internal.UnsafeCastToPtr(bindGroup)));
	}

	/// Queues a bind group layout for deferred deletion.
	public void QueueBindGroupLayout(IBindGroupLayout layout)
	{
		if (layout != null)
			mQueue.Add(.(mCurrentFrame, .BindGroupLayout, Internal.UnsafeCastToPtr(layout)));
	}

	/// Queues a pipeline layout for deferred deletion.
	public void QueuePipelineLayout(IPipelineLayout layout)
	{
		if (layout != null)
			mQueue.Add(.(mCurrentFrame, .PipelineLayout, Internal.UnsafeCastToPtr(layout)));
	}

	/// Queues a render pipeline for deferred deletion.
	public void QueueRenderPipeline(IRenderPipeline pipeline)
	{
		if (pipeline != null)
			mQueue.Add(.(mCurrentFrame, .RenderPipeline, Internal.UnsafeCastToPtr(pipeline)));
	}

	/// Queues a compute pipeline for deferred deletion.
	public void QueueComputePipeline(IComputePipeline pipeline)
	{
		if (pipeline != null)
			mQueue.Add(.(mCurrentFrame, .ComputePipeline, Internal.UnsafeCastToPtr(pipeline)));
	}

	/// Queues a shader module for deferred deletion.
	public void QueueShaderModule(IShaderModule module)
	{
		if (module != null)
			mQueue.Add(.(mCurrentFrame, .ShaderModule, Internal.UnsafeCastToPtr(module)));
	}

	/// Processes the deletion queue, deleting resources that have been
	/// queued for at least DELETION_DEFER_FRAMES frames.
	/// Call this at the end of each frame after the GPU fence.
	public void ProcessDeletions(uint32 currentFrame)
	{
		int i = 0;
		while (i < mQueue.Count)
		{
			let entry = mQueue[i];

			// Check if enough frames have passed
			let framesSinceQueued = currentFrame - entry.QueuedFrame;
			if (framesSinceQueued >= (uint32)RenderConfig.DELETION_DEFER_FRAMES)
			{
				// Delete the resource
				DeleteResource(entry);

				// Remove from queue (swap with last for O(1) removal)
				mQueue.RemoveAtFast(i);
				// Don't increment i since we swapped in a new element
			}
			else
			{
				i++;
			}
		}
	}

	/// Immediately deletes all queued resources.
	/// Call this during shutdown when the GPU is idle.
	public void FlushAll()
	{
		for (let entry in mQueue)
		{
			DeleteResource(entry);
		}
		mQueue.Clear();
	}

	/// Deletes a single resource based on its type.
	private void DeleteResource(DeferredDeletionEntry entry)
	{
		// All RHI resources implement IDisposable, so we can delete them as Object
		// The type enum is kept for debugging/logging purposes
		if (entry.Resource != null)
		{
			delete (Object)Internal.UnsafeCastToObject(entry.Resource);
		}
	}
}
