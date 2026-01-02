namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;

/// Vulkan implementation of IComputePassEncoder.
class VulkanComputePassEncoder : IComputePassEncoder
{
	private VulkanDevice mDevice;
	private VkCommandBuffer mCommandBuffer;
	private VulkanComputePipeline mCurrentPipeline;
	private bool mEnded;

	public this(VulkanDevice device, VkCommandBuffer commandBuffer)
	{
		mDevice = device;
		mCommandBuffer = commandBuffer;
		mEnded = false;
	}

	public void SetPipeline(IComputePipeline pipeline)
	{
		if (mEnded)
			return;

		if (let vkPipeline = pipeline as VulkanComputePipeline)
		{
			mCurrentPipeline = vkPipeline;
			VulkanNative.vkCmdBindPipeline(mCommandBuffer, .VK_PIPELINE_BIND_POINT_COMPUTE, vkPipeline.Pipeline);
		}
	}

	public void SetBindGroup(uint32 index, IBindGroup bindGroup, Span<uint32> dynamicOffsets = default)
	{
		if (mEnded || mCurrentPipeline == null)
			return;

		if (let vkBindGroup = bindGroup as VulkanBindGroup)
		{
			var descriptorSet = vkBindGroup.DescriptorSet;
			VulkanNative.vkCmdBindDescriptorSets(
				mCommandBuffer,
				.VK_PIPELINE_BIND_POINT_COMPUTE,
				mCurrentPipeline.[Friend]mLayout.PipelineLayout,
				index,
				1,
				&descriptorSet,
				(uint32)dynamicOffsets.Length,
				dynamicOffsets.Ptr
			);
		}
	}

	public void Dispatch(uint32 workgroupCountX, uint32 workgroupCountY = 1, uint32 workgroupCountZ = 1)
	{
		if (mEnded)
			return;

		VulkanNative.vkCmdDispatch(mCommandBuffer, workgroupCountX, workgroupCountY, workgroupCountZ);
	}

	public void DispatchIndirect(IBuffer indirectBuffer, uint64 indirectOffset)
	{
		if (mEnded)
			return;

		if (let vkBuffer = indirectBuffer as VulkanBuffer)
		{
			VulkanNative.vkCmdDispatchIndirect(mCommandBuffer, vkBuffer.Buffer, (VkDeviceSize)indirectOffset);
		}
	}

	public void End()
	{
		if (mEnded)
			return;

		// Compute passes don't have an explicit end in Vulkan
		// Just mark as ended to prevent further commands
		mEnded = true;
	}
}
