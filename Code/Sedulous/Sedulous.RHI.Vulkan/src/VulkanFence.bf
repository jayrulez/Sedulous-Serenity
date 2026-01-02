namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;

/// Vulkan implementation of IFence.
class VulkanFence : IFence
{
	private VulkanDevice mDevice;
	private VkFence mFence;

	public this(VulkanDevice device, bool signaled = false)
	{
		mDevice = device;
		CreateFence(signaled);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mFence != default)
		{
			VulkanNative.vkDestroyFence(mDevice.Device, mFence, null);
			mFence = default;
		}
	}

	/// Returns true if the fence was created successfully.
	public bool IsValid => mFence != default;

	/// Gets the Vulkan fence handle.
	public VkFence Fence => mFence;

	public bool IsSignaled
	{
		get
		{
			if (mFence == default)
				return false;

			return VulkanNative.vkGetFenceStatus(mDevice.Device, mFence) == .VK_SUCCESS;
		}
	}

	public bool Wait(uint64 timeoutNanoseconds = uint64.MaxValue)
	{
		if (mFence == default)
			return false;

		var fence = mFence;
		return VulkanNative.vkWaitForFences(mDevice.Device, 1, &fence, VkBool32.True, timeoutNanoseconds) == .VK_SUCCESS;
	}

	public void Reset()
	{
		if (mFence == default)
			return;

		var fence = mFence;
		VulkanNative.vkResetFences(mDevice.Device, 1, &fence);
	}

	private void CreateFence(bool signaled)
	{
		VkFenceCreateInfo fenceInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
				flags = signaled ? .VK_FENCE_CREATE_SIGNALED_BIT : 0
			};

		VulkanNative.vkCreateFence(mDevice.Device, &fenceInfo, null, &mFence);
	}
}
