namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of IRenderPassEncoder.
class VulkanRenderPassEncoder : IRenderPassEncoder
{
	private VulkanDevice mDevice;
	private VkCommandBuffer mCommandBuffer;
	private VulkanRenderPipeline mCurrentPipeline;
	private bool mEnded;

	public this(VulkanDevice device, VkCommandBuffer commandBuffer)
	{
		mDevice = device;
		mCommandBuffer = commandBuffer;
		mEnded = false;
	}

	public void SetPipeline(IRenderPipeline pipeline)
	{
		if (mEnded)
			return;

		if (let vkPipeline = pipeline as VulkanRenderPipeline)
		{
			mCurrentPipeline = vkPipeline;
			VulkanNative.vkCmdBindPipeline(mCommandBuffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, vkPipeline.Pipeline);
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
				.VK_PIPELINE_BIND_POINT_GRAPHICS,
				mCurrentPipeline.[Friend]mLayout.PipelineLayout,
				index,
				1,
				&descriptorSet,
				(uint32)dynamicOffsets.Length,
				dynamicOffsets.Ptr
			);
		}
	}

	public void SetVertexBuffer(uint32 slot, IBuffer buffer, uint64 offset = 0)
	{
		if (mEnded)
			return;

		if (let vkBuffer = buffer as VulkanBuffer)
		{
			var vkBuf = vkBuffer.Buffer;
			var vkOffset = (VkDeviceSize)offset;
			VulkanNative.vkCmdBindVertexBuffers(mCommandBuffer, slot, 1, &vkBuf, (uint64*)&vkOffset);
		}
	}

	public void SetIndexBuffer(IBuffer buffer, IndexFormat format, uint64 offset = 0)
	{
		if (mEnded)
			return;

		if (let vkBuffer = buffer as VulkanBuffer)
		{
			VkIndexType indexType = format == .UInt16 ? .VK_INDEX_TYPE_UINT16 : .VK_INDEX_TYPE_UINT32;
			VulkanNative.vkCmdBindIndexBuffer(mCommandBuffer, vkBuffer.Buffer, (VkDeviceSize)offset, indexType);
		}
	}

	public void SetViewport(float x, float y, float width, float height, float minDepth, float maxDepth)
	{
		if (mEnded)
			return;

		VkViewport viewport = .()
			{
				x = x,
				y = y,
				width = width,
				height = height,
				minDepth = minDepth,
				maxDepth = maxDepth
			};
		VulkanNative.vkCmdSetViewport(mCommandBuffer, 0, 1, &viewport);
	}

	public void SetScissorRect(int32 x, int32 y, uint32 width, uint32 height)
	{
		if (mEnded)
			return;

		VkRect2D scissor = .()
			{
				offset = .() { x = x, y = y },
				extent = .() { width = width, height = height }
			};
		VulkanNative.vkCmdSetScissor(mCommandBuffer, 0, 1, &scissor);
	}

	public void SetBlendConstant(float r, float g, float b, float a)
	{
		if (mEnded)
			return;

		float[4] blendConstants = .(r, g, b, a);
		VulkanNative.vkCmdSetBlendConstants(mCommandBuffer, blendConstants);
	}

	public void SetStencilReference(uint32 reference)
	{
		if (mEnded)
			return;

		VulkanNative.vkCmdSetStencilReference(mCommandBuffer, .VK_STENCIL_FACE_FRONT_AND_BACK, reference);
	}

	public void Draw(uint32 vertexCount, uint32 instanceCount = 1, uint32 firstVertex = 0, uint32 firstInstance = 0)
	{
		if (mEnded)
			return;

		VulkanNative.vkCmdDraw(mCommandBuffer, vertexCount, instanceCount, firstVertex, firstInstance);
	}

	public void DrawIndexed(uint32 indexCount, uint32 instanceCount = 1, uint32 firstIndex = 0, int32 baseVertex = 0, uint32 firstInstance = 0)
	{
		if (mEnded)
			return;

		VulkanNative.vkCmdDrawIndexed(mCommandBuffer, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
	}

	public void DrawIndirect(IBuffer indirectBuffer, uint64 indirectOffset)
	{
		if (mEnded)
			return;

		if (let vkBuffer = indirectBuffer as VulkanBuffer)
		{
			VulkanNative.vkCmdDrawIndirect(mCommandBuffer, vkBuffer.Buffer, (VkDeviceSize)indirectOffset, 1, 0);
		}
	}

	public void DrawIndexedIndirect(IBuffer indirectBuffer, uint64 indirectOffset)
	{
		if (mEnded)
			return;

		if (let vkBuffer = indirectBuffer as VulkanBuffer)
		{
			VulkanNative.vkCmdDrawIndexedIndirect(mCommandBuffer, vkBuffer.Buffer, (VkDeviceSize)indirectOffset, 1, 0);
		}
	}

	public void End()
	{
		if (mEnded)
			return;

		VulkanNative.vkCmdEndRenderPass(mCommandBuffer);
		mEnded = true;
	}
}
