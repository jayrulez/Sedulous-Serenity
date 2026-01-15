namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;

/// Slot in the bind group pool.
class BindGroupSlot
{
	public IBindGroup BindGroup ~ delete _;
	public uint32 Generation;
	public uint64 LastUsedFrame;
	public bool InUse;
}

/// Pool for managing bind groups with frame-based recycling.
/// Automatically recycles bind groups that haven't been used for N frames.
class BindGroupPool : IDisposable
{
	private IDevice mDevice;

	/// All bind group slots (indexed by handle.Index).
	private List<BindGroupSlot> mSlots = new .() ~ {
		for (let slot in _)
			delete slot;
		delete _;
	};

	/// Free list of available indices.
	private List<uint32> mFreeList = new .() ~ delete _;

	/// Current frame number.
	private uint64 mCurrentFrame = 0;

	/// Frames before unused bind groups are recycled.
	public uint32 RecycleThreshold = 3;

	/// Total bind groups in the pool.
	public int TotalCount => mSlots.Count;

	/// Bind groups currently in use.
	public int ActiveCount
	{
		get
		{
			int count = 0;
			for (let slot in mSlots)
				if (slot.InUse)
					count++;
			return count;
		}
	}

	/// Initializes the bind group pool.
	public void Initialize(IDevice device)
	{
		mDevice = device;
	}

	/// Sets the current frame for tracking.
	public void BeginFrame(uint64 frameIndex)
	{
		mCurrentFrame = frameIndex;
	}

	/// Allocates a new bind group from a layout.
	public Result<BindGroupHandle> Allocate(IBindGroupLayout layout, Span<BindGroupEntry> entries)
	{
		// Try to reuse from free list
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			index = mFreeList.PopBack();
			generation = mSlots[index].Generation + 1;
		}
		else
		{
			// Allocate new slot
			index = (uint32)mSlots.Count;
			generation = 1;
			mSlots.Add(new BindGroupSlot());
		}

		// Create the bind group
		var desc = BindGroupDescriptor();
		desc.Layout = layout;
		desc.Entries = entries;

		switch (mDevice.CreateBindGroup(&desc))
		{
		case .Ok(let bindGroup):
			let slot = mSlots[index];
			if (slot.BindGroup != null)
				delete slot.BindGroup;
			slot.BindGroup = bindGroup;
			slot.Generation = generation;
			slot.LastUsedFrame = mCurrentFrame;
			slot.InUse = true;
			return BindGroupHandle(index, generation);

		case .Err:
			// Put index back on free list
			mFreeList.Add(index);
			return .Err;
		}
	}

	/// Gets the RHI bind group for a handle.
	public IBindGroup Get(BindGroupHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mSlots.Count)
			return null;

		let slot = mSlots[handle.Index];
		if (slot.Generation != handle.Generation || !slot.InUse)
			return null;

		slot.LastUsedFrame = mCurrentFrame;
		return slot.BindGroup;
	}

	/// Releases a bind group back to the pool.
	public void Release(BindGroupHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mSlots.Count)
			return;

		let slot = mSlots[handle.Index];
		if (slot.Generation != handle.Generation || !slot.InUse)
			return;

		slot.InUse = false;
		mFreeList.Add(handle.Index);
	}

	/// Recycles bind groups that haven't been used recently.
	public void RecycleUnused()
	{
		for (uint32 i = 0; i < mSlots.Count; i++)
		{
			let slot = mSlots[i];
			if (slot.InUse && mCurrentFrame - slot.LastUsedFrame > RecycleThreshold)
			{
				slot.InUse = false;
				mFreeList.Add(i);
			}
		}
	}

	/// Clears all bind groups.
	public void Clear()
	{
		for (let slot in mSlots)
		{
			if (slot.BindGroup != null)
			{
				delete slot.BindGroup;
				slot.BindGroup = null;
			}
			slot.InUse = false;
		}
		mFreeList.Clear();
		for (uint32 i = 0; i < mSlots.Count; i++)
			mFreeList.Add(i);
	}

	/// Gets pool statistics.
	public void GetStats(String outStats)
	{
		outStats.AppendF("Bind Group Pool Stats:\n");
		outStats.AppendF("  Total slots: {}\n", mSlots.Count);
		outStats.AppendF("  Active: {}\n", ActiveCount);
		outStats.AppendF("  Free list size: {}\n", mFreeList.Count);
	}

	public void Dispose()
	{
		Clear();
	}
}
