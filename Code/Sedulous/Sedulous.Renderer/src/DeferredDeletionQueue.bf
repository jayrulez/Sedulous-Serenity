namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;

/// Queue for deferred GPU resource deletion.
/// Resources are held for DELETION_DEFER_FRAMES before actual deletion
/// to ensure the GPU has finished using them.
class DeferredDeletionQueue
{
	struct PendingDeletion
	{
		public IDisposable Resource;
		public int32 DeleteAfterFrame;
	}

	private List<PendingDeletion> mPending = new .() ~ delete _;
	private int32 mCurrentFrame = 0;

	/// Call at start of each frame with current frame index.
	public void BeginFrame(int32 frameIndex)
	{
		mCurrentFrame = frameIndex;
		ProcessDeletions();
	}

	/// Queue a resource for deferred deletion.
	public void QueueDelete(IDisposable resource)
	{
		if (resource == null)
			return;

		mPending.Add(.() {
			Resource = resource,
			DeleteAfterFrame = mCurrentFrame + FrameConfig.DELETION_DEFER_FRAMES
		});
	}

	/// Queue multiple resources for deferred deletion.
	public void QueueDelete(params Span<IDisposable> resources)
	{
		for (let resource in resources)
		{
			QueueDelete(resource);
		}
	}

	/// Process deletions that are safe to execute.
	private void ProcessDeletions()
	{
		for (int i = mPending.Count - 1; i >= 0; i--)
		{
			if (mCurrentFrame >= mPending[i].DeleteAfterFrame)
			{
				delete mPending[i].Resource;
				mPending.RemoveAt(i);
			}
		}
	}

	/// Force delete all pending resources (for shutdown).
	public void Flush()
	{
		for (let pending in mPending)
			delete pending.Resource;
		mPending.Clear();
	}

	/// Gets the number of pending deletions.
	public int32 PendingCount => (int32)mPending.Count;
}
