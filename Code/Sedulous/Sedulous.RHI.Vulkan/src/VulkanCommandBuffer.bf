namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of ICommandBuffer.
class VulkanCommandBuffer : ICommandBuffer
{
	private VulkanDevice mDevice;
	private VulkanCommandPool mPool;
	private VkCommandBuffer mCommandBuffer;

	public this(VulkanDevice device, VulkanCommandPool pool, VkCommandBuffer commandBuffer)
	{
		mDevice = device;
		mPool = pool;
		mCommandBuffer = commandBuffer;
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mCommandBuffer != default && mPool != null)
		{
			mPool.FreeCommandBuffer(mCommandBuffer);
			mCommandBuffer = default;
		}
	}

	/// Returns true if the command buffer is valid.
	public bool IsValid => mCommandBuffer != default;

	/// Gets the Vulkan command buffer handle.
	public VkCommandBuffer CommandBuffer => mCommandBuffer;
}
