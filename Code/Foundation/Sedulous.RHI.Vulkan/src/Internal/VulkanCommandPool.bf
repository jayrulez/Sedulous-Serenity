namespace Sedulous.RHI.Vulkan.Internal;

using System;
using Bulkan;

/// Manages Vulkan command pools for allocating command buffers.
class VulkanCommandPool
{
	private VulkanDevice mDevice;
	private VkCommandPool mCommandPool;
	private uint32 mQueueFamilyIndex;

	public this(VulkanDevice device, uint32 queueFamilyIndex, bool transient = false)
	{
		mDevice = device;
		mQueueFamilyIndex = queueFamilyIndex;
		CreateCommandPool(transient);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mCommandPool != default)
		{
			VulkanNative.vkDestroyCommandPool(mDevice.Device, mCommandPool, null);
			mCommandPool = default;
		}
	}

	/// Returns true if the pool was created successfully.
	public bool IsValid => mCommandPool != default;

	/// Gets the Vulkan command pool handle.
	public VkCommandPool CommandPool => mCommandPool;

	/// Allocates a primary command buffer from the pool.
	public Result<VkCommandBuffer> AllocateCommandBuffer()
	{
		VkCommandBufferAllocateInfo allocInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
				commandPool = mCommandPool,
				level = .VK_COMMAND_BUFFER_LEVEL_PRIMARY,
				commandBufferCount = 1
			};

		VkCommandBuffer commandBuffer = default;
		if (VulkanNative.vkAllocateCommandBuffers(mDevice.Device, &allocInfo, &commandBuffer) != .VK_SUCCESS)
			return .Err;

		return .Ok(commandBuffer);
	}

	/// Frees a command buffer back to the pool.
	public void FreeCommandBuffer(VkCommandBuffer commandBuffer)
	{
		var commandBuffer;
		VulkanNative.vkFreeCommandBuffers(mDevice.Device, mCommandPool, 1, &commandBuffer);
	}

	/// Resets the entire pool, recycling all command buffers.
	public void Reset()
	{
		VulkanNative.vkResetCommandPool(mDevice.Device, mCommandPool, 0);
	}

	private void CreateCommandPool(bool transient)
	{
		VkCommandPoolCreateFlags flags = .VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
		if (transient)
			flags |= .VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;

		VkCommandPoolCreateInfo poolInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
				flags = flags,
				queueFamilyIndex = mQueueFamilyIndex
			};

		VulkanNative.vkCreateCommandPool(mDevice.Device, &poolInfo, null, &mCommandPool);
	}
}
