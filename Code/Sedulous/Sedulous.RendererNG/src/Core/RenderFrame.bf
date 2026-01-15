namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Per-frame rendering state.
/// Contains all transient data needed for a single frame of rendering.
/// Created at the start of each frame and discarded at the end.
class RenderFrame
{
	/// Current frame index (for multi-buffering).
	public uint32 FrameIndex;

	/// Time since last frame in seconds.
	public float DeltaTime;

	/// Total elapsed time in seconds.
	public float TotalTime;

	/// Active render views for this frame.
	private List<RenderView> mViews = new .() ~ delete _;

	/// Shadow views for this frame.
	private List<RenderView> mShadowViews = new .() ~ delete _;

	// Transient buffer allocations (to be implemented)
	// private TransientBufferPool mTransientBuffers;

	/// Gets the active render views.
	public Span<RenderView> Views => mViews;

	/// Gets the shadow render views.
	public Span<RenderView> ShadowViews => mShadowViews;

	/// Gets the number of active views.
	public int ViewCount => mViews.Count;

	/// Gets the number of shadow views.
	public int ShadowViewCount => mShadowViews.Count;

	/// Initializes the frame with timing information.
	public void Begin(uint32 frameIndex, float deltaTime, float totalTime)
	{
		FrameIndex = frameIndex;
		DeltaTime = deltaTime;
		TotalTime = totalTime;

		// Clear views from previous frame
		mViews.Clear();
		mShadowViews.Clear();

		// TODO: Reset transient buffer allocator
		// mTransientBuffers.BeginFrame(frameIndex);
	}

	/// Ends the frame.
	public void End()
	{
		// Views are cleared on next Begin()
	}

	/// Adds a camera view for rendering.
	/// @param view The render view to add.
	/// @returns The view slot index.
	public int32 AddView(RenderView view)
	{
		if (mViews.Count >= RenderConfig.MAX_VIEWS)
		{
			// Log warning: max views exceeded
			return -1;
		}

		int32 slot = (int32)mViews.Count;
		mViews.Add(view);
		return slot;
	}

	/// Adds a shadow view for rendering.
	/// @param view The shadow render view to add.
	/// @returns The shadow view slot index.
	public int32 AddShadowView(RenderView view)
	{
		if (mShadowViews.Count >= RenderConfig.MAX_SHADOW_VIEWS)
		{
			// Log warning: max shadow views exceeded
			return -1;
		}

		int32 slot = (int32)mShadowViews.Count;
		mShadowViews.Add(view);
		return slot;
	}

	/// Gets a view by slot index.
	public RenderView GetView(int32 slot)
	{
		if (slot < 0 || slot >= mViews.Count)
			return null;
		return mViews[slot];
	}

	/// Gets a shadow view by slot index.
	public RenderView GetShadowView(int32 slot)
	{
		if (slot < 0 || slot >= mShadowViews.Count)
			return null;
		return mShadowViews[slot];
	}

	/// Gets the main camera view (first view, if any).
	public RenderView MainView => mViews.Count > 0 ? mViews[0] : null;

	// TODO: Transient allocation methods
	// public TransientAllocation AllocateVertices(uint32 count, uint32 stride);
	// public TransientAllocation AllocateIndices(uint32 count);
	// public TransientAllocation AllocateUniform(uint32 size);
	// public TransientAllocation AllocateStorage(uint32 size);
}

/// Transient buffer allocation result.
struct TransientAllocation
{
	/// The buffer containing the allocation.
	public IBuffer Buffer;

	/// Offset into the buffer (bytes).
	public uint32 Offset;

	/// Size of the allocation (bytes).
	public uint32 Size;

	/// Whether this allocation is valid.
	public bool IsValid => Buffer != null;

	/// Invalid allocation constant.
	public static readonly Self Invalid = .();
}
