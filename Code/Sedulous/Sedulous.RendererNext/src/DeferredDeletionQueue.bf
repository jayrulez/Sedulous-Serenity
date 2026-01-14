namespace Sedulous.RendererNext;

using System;
using System.Collections;

/// Queue for deferring GPU resource deletion until it's safe.
/// Resources are kept alive for DELETION_DEFER_FRAMES frames to ensure
/// the GPU is no longer using them.
class DeferredDeletionQueue
{
	struct PendingDeletion
	{
		public IDisposable Resource;
		public int32 DeleteAfterFrame;
	}

	private List<PendingDeletion> mPending = new .() ~ delete _;
	private int32 mCurrentFrame = 0;

	/// Call at the start of each frame to process pending deletions.
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

		mPending.Add(.()
		{
			Resource = resource,
			DeleteAfterFrame = mCurrentFrame + FrameConfig.DELETION_DEFER_FRAMES
		});
	}

	/// Process pending deletions, deleting resources that have been deferred long enough.
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

	/// Immediately delete all pending resources (call on shutdown).
	public void Flush()
	{
		for (let pending in mPending)
			delete pending.Resource;
		mPending.Clear();
	}

	/// Number of resources pending deletion.
	public int32 PendingCount => (int32)mPending.Count;
}
