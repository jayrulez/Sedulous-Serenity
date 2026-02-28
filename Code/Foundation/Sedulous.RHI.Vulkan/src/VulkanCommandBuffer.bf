namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of ICommandBuffer.
class VulkanCommandBuffer : ICommandBuffer
{
	private VulkanDevice mDevice;
	private VulkanCommandPool mPool;
	private VkCommandBuffer mCommandBuffer;

	// Owned resources that must be kept alive until GPU is done with the command buffer
	private List<VkRenderPass> mRenderPasses ~ delete _;
	private List<VkFramebuffer> mFramebuffers ~ delete _;

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

	/// Takes ownership of render passes and framebuffers from the encoder.
	public void TakeOwnership(List<VkRenderPass> renderPasses, List<VkFramebuffer> framebuffers)
	{
		mRenderPasses = new List<VkRenderPass>();
		for (let rp in renderPasses)
			mRenderPasses.Add(rp);

		mFramebuffers = new List<VkFramebuffer>();
		for (let fb in framebuffers)
			mFramebuffers.Add(fb);
	}

	public void Dispose()
	{
		// Clean up framebuffers first (they reference render passes)
		if (mFramebuffers != null)
		{
			for (let fb in mFramebuffers)
				VulkanNative.vkDestroyFramebuffer(mDevice.Device, fb, null);
			mFramebuffers.Clear();
		}

		// Clean up render passes
		if (mRenderPasses != null)
		{
			for (let rp in mRenderPasses)
				VulkanNative.vkDestroyRenderPass(mDevice.Device, rp, null);
			mRenderPasses.Clear();
		}

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
