namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of ITransferBatch.
/// Accumulates transfer commands in a single command buffer and submits once.
class VulkanTransferBatch : ITransferBatch
{
	private VulkanDevice mDevice;
	private VkQueue mQueue;
	private VulkanCommandPool mPool;
	private VkCommandBuffer mCmdBuffer;
	private bool mCmdBufferActive;
	private List<IBuffer> mStagingBuffers = new .() ~ delete _;

	public this(VulkanDevice device, VkQueue queue, VulkanCommandPool pool)
	{
		mDevice = device;
		mQueue = queue;
		mPool = pool;
		mCmdBuffer = default;
		mCmdBufferActive = false;
	}

	public ~this()
	{
		// Clean up any unsubmitted state
		Cleanup();
	}

	public void WriteTexture(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout,
		Extent3D* writeSize, uint32 mipLevel = 0, uint32 arrayLayer = 0)
	{
		let vkTexture = texture as VulkanTexture;
		if (vkTexture == null || data.Length == 0 || dataLayout == null || writeSize == null)
			return;

		// Ensure command buffer is active
		if (!EnsureCmdBuffer())
			return;

		// Create staging buffer
		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				MemoryAccess = .CpuToGpu
			};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
		{
			if (let vkStaging = stagingBuffer as VulkanBuffer)
			{
				// Copy data to staging buffer
				let ptr = vkStaging.Map();
				if (ptr != null)
				{
					Internal.MemCpy(ptr, data.Ptr, data.Length);
					vkStaging.Unmap();
				}

				// Transition image layout to transfer destination
				VkImageMemoryBarrier barrier = .()
					{
						sType = .VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
						oldLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
						newLayout = .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
						srcQueueFamilyIndex = VulkanNative.VK_QUEUE_FAMILY_IGNORED,
						dstQueueFamilyIndex = VulkanNative.VK_QUEUE_FAMILY_IGNORED,
						image = vkTexture.Image,
						subresourceRange = .()
						{
							aspectMask = VulkanConversions.GetAspectFlags(vkTexture.Format),
							baseMipLevel = mipLevel,
							levelCount = 1,
							baseArrayLayer = arrayLayer,
							layerCount = 1
						},
						srcAccessMask = 0,
						dstAccessMask = .VK_ACCESS_TRANSFER_WRITE_BIT
					};

				VulkanNative.vkCmdPipelineBarrier(
					mCmdBuffer,
					.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
					.VK_PIPELINE_STAGE_TRANSFER_BIT,
					0, 0, null, 0, null, 1, &barrier
				);

				// Copy buffer to image
				VkBufferImageCopy region = .()
					{
						bufferOffset = dataLayout.Offset,
						bufferRowLength = dataLayout.BytesPerRow / VulkanConversions.GetFormatBytesPerPixel(vkTexture.Format),
						bufferImageHeight = dataLayout.RowsPerImage,
						imageSubresource = .()
						{
							aspectMask = VulkanConversions.GetAspectFlags(vkTexture.Format),
							mipLevel = mipLevel,
							baseArrayLayer = arrayLayer,
							layerCount = 1
						},
						imageOffset = .() { x = 0, y = 0, z = 0 },
						imageExtent = .() { width = writeSize.Width, height = writeSize.Height, depth = writeSize.Depth }
					};

				VulkanNative.vkCmdCopyBufferToImage(mCmdBuffer, vkStaging.Buffer, vkTexture.Image, .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

				// Transition image layout to shader read
				barrier.oldLayout = .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
				barrier.newLayout = .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
				barrier.srcAccessMask = .VK_ACCESS_TRANSFER_WRITE_BIT;
				barrier.dstAccessMask = .VK_ACCESS_SHADER_READ_BIT;

				VulkanNative.vkCmdPipelineBarrier(
					mCmdBuffer,
					.VK_PIPELINE_STAGE_TRANSFER_BIT,
					.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
					0, 0, null, 0, null, 1, &barrier
				);
			}

			// Track staging buffer for cleanup after submit
			mStagingBuffers.Add(stagingBuffer);
		}
	}

	public void WriteStagedBuffer(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let vkBuffer = buffer as VulkanBuffer;
		if (vkBuffer == null || !vkBuffer.IsValid || data.Length == 0)
			return;

		// Ensure command buffer is active
		if (!EnsureCmdBuffer())
			return;

		// Create staging buffer
		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				MemoryAccess = .CpuToGpu
			};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
		{
			if (let vkStaging = stagingBuffer as VulkanBuffer)
			{
				let stagingPtr = vkStaging.Map();
				if (stagingPtr != null)
				{
					Internal.MemCpy(stagingPtr, data.Ptr, data.Length);
					vkStaging.Unmap();
				}

				VkBufferCopy copyRegion = .()
					{
						srcOffset = 0,
						dstOffset = offset,
						size = (uint64)data.Length
					};
				VulkanNative.vkCmdCopyBuffer(mCmdBuffer, vkStaging.Buffer, vkBuffer.Buffer, 1, &copyRegion);
			}

			// Track staging buffer for cleanup after submit
			mStagingBuffers.Add(stagingBuffer);
		}
	}

	public void Submit()
	{
		if (!mCmdBufferActive)
			return;

		VulkanNative.vkEndCommandBuffer(mCmdBuffer);

		var cmdBuf = mCmdBuffer;
		VkSubmitInfo submitInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
				commandBufferCount = 1,
				pCommandBuffers = &cmdBuf
			};

		VulkanNative.vkQueueSubmit(mQueue, 1, &submitInfo, default);
		Console.WriteLine(scope $"[GPU Sync] TransferBatch.Submit - vkQueueWaitIdle ({mStagingBuffers.Count} transfers)");
		VulkanNative.vkQueueWaitIdle(mQueue);

		Cleanup();
	}

	/// Lazily allocates and begins the command buffer on first use.
	private bool EnsureCmdBuffer()
	{
		if (mCmdBufferActive)
			return true;

		if (mPool.AllocateCommandBuffer() case .Ok(let cmdBuffer))
		{
			mCmdBuffer = cmdBuffer;

			VkCommandBufferBeginInfo beginInfo = .()
				{
					sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
					flags = .VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
				};

			VulkanNative.vkBeginCommandBuffer(mCmdBuffer, &beginInfo);
			mCmdBufferActive = true;
			return true;
		}

		return false;
	}

	/// Frees the command buffer and all staging buffers.
	private void Cleanup()
	{
		if (mCmdBuffer != default)
		{
			mPool.FreeCommandBuffer(mCmdBuffer);
			mCmdBuffer = default;
		}
		mCmdBufferActive = false;

		for (let staging in mStagingBuffers)
			delete staging;
		mStagingBuffers.Clear();
	}
}
