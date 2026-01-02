namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of IQueue.
class VulkanQueue : IQueue
{
	private VulkanDevice mDevice;
	private VkQueue mQueue;
	private uint32 mFamilyIndex;
	private VulkanCommandPool mTransientPool;

	public this(VulkanDevice device, VkQueue queue, uint32 familyIndex)
	{
		mDevice = device;
		mQueue = queue;
		mFamilyIndex = familyIndex;
		mTransientPool = new VulkanCommandPool(device, familyIndex, true);
	}

	public ~this()
	{
		if (mTransientPool != null)
		{
			delete mTransientPool;
			mTransientPool = null;
		}
	}

	/// Gets the Vulkan queue handle.
	public VkQueue Queue => mQueue;

	/// Gets the queue family index.
	public uint32 FamilyIndex => mFamilyIndex;

	public void Submit(Span<ICommandBuffer> commandBuffers)
	{
		if (commandBuffers.Length == 0)
			return;

		List<VkCommandBuffer> vkCommandBuffers = scope .();
		for (let cmdBuffer in commandBuffers)
		{
			if (let vkCmdBuffer = cmdBuffer as VulkanCommandBuffer)
			{
				if (vkCmdBuffer.IsValid)
					vkCommandBuffers.Add(vkCmdBuffer.CommandBuffer);
			}
		}

		if (vkCommandBuffers.Count == 0)
			return;

		VkSubmitInfo submitInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
				waitSemaphoreCount = 0,
				pWaitSemaphores = null,
				pWaitDstStageMask = null,
				commandBufferCount = (uint32)vkCommandBuffers.Count,
				pCommandBuffers = vkCommandBuffers.Ptr,
				signalSemaphoreCount = 0,
				pSignalSemaphores = null
			};

		VulkanNative.vkQueueSubmit(mQueue, 1, &submitInfo, default);
	}

	public void Submit(ICommandBuffer commandBuffer)
	{
		if (commandBuffer != null)
		{
			ICommandBuffer[1] buffers = .(commandBuffer);
			Submit(buffers);
		}
	}

	public void Submit(Span<ICommandBuffer> commandBuffers, ISwapChain swapChain)
	{
		if (commandBuffers.Length == 0)
			return;

		let vkSwapChain = swapChain as VulkanSwapChain;
		if (vkSwapChain == null)
		{
			// Fallback to regular submit if not a Vulkan swap chain
			Submit(commandBuffers);
			return;
		}

		List<VkCommandBuffer> vkCommandBuffers = scope .();
		for (let cmdBuffer in commandBuffers)
		{
			if (let vkCmdBuffer = cmdBuffer as VulkanCommandBuffer)
			{
				if (vkCmdBuffer.IsValid)
					vkCommandBuffers.Add(vkCmdBuffer.CommandBuffer);
			}
		}

		if (vkCommandBuffers.Count == 0)
			return;

		// Set up synchronization with swap chain semaphores
		VkSemaphore[1] waitSemaphores = .(vkSwapChain.ImageAvailableSemaphore);
		VkSemaphore[1] signalSemaphores = .(vkSwapChain.RenderFinishedSemaphore);
		VkPipelineStageFlags[1] waitStages = .(.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);

		VkSubmitInfo submitInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
				waitSemaphoreCount = 1,
				pWaitSemaphores = &waitSemaphores,
				pWaitDstStageMask = &waitStages,
				commandBufferCount = (uint32)vkCommandBuffers.Count,
				pCommandBuffers = vkCommandBuffers.Ptr,
				signalSemaphoreCount = 1,
				pSignalSemaphores = &signalSemaphores
			};

		VulkanNative.vkQueueSubmit(mQueue, 1, &submitInfo, default);
	}

	public void Submit(ICommandBuffer commandBuffer, ISwapChain swapChain)
	{
		if (commandBuffer != null)
		{
			ICommandBuffer[1] buffers = .(commandBuffer);
			Submit(buffers, swapChain);
		}
	}

	/// Submits command buffers and signals a fence when complete.
	public void Submit(Span<ICommandBuffer> commandBuffers, VulkanFence fence)
	{
		if (commandBuffers.Length == 0)
			return;

		List<VkCommandBuffer> vkCommandBuffers = scope .();
		for (let cmdBuffer in commandBuffers)
		{
			if (let vkCmdBuffer = cmdBuffer as VulkanCommandBuffer)
			{
				if (vkCmdBuffer.IsValid)
					vkCommandBuffers.Add(vkCmdBuffer.CommandBuffer);
			}
		}

		if (vkCommandBuffers.Count == 0)
			return;

		VkSubmitInfo submitInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
				commandBufferCount = (uint32)vkCommandBuffers.Count,
				pCommandBuffers = vkCommandBuffers.Ptr
			};

		VkFence vkFence = fence != null ? fence.Fence : default;
		VulkanNative.vkQueueSubmit(mQueue, 1, &submitInfo, vkFence);
	}

	public void WriteBuffer(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let vkBuffer = buffer as VulkanBuffer;
		if (vkBuffer == null || data.Length == 0)
			return;

		// Try mapping directly (works for host-visible buffers)
		let ptr = vkBuffer.Map();
		if (ptr != null)
		{
			Internal.MemCpy((uint8*)ptr + offset, data.Ptr, data.Length);
			vkBuffer.Unmap();
			return;
		}

		// For device-local buffers, use staging
		BufferDescriptor stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				MemoryAccess = .Upload
			};

		if (mDevice.CreateBuffer(&stagingDesc) case .Ok(let stagingBuffer))
		{
			// Copy data to staging buffer
			if (let vkStaging = stagingBuffer as VulkanBuffer)
			{
				let stagingPtr = vkStaging.Map();
				if (stagingPtr != null)
				{
					Internal.MemCpy(stagingPtr, data.Ptr, data.Length);
					vkStaging.Unmap();
				}

				// Copy staging to destination
				if (mTransientPool.AllocateCommandBuffer() case .Ok(let cmdBuffer))
				{
					var cmdBuf = cmdBuffer;
					VkCommandBufferBeginInfo beginInfo = .()
						{
							sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
							flags = .VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
						};

					VulkanNative.vkBeginCommandBuffer(cmdBuf, &beginInfo);

					VkBufferCopy copyRegion = .()
						{
							srcOffset = 0,
							dstOffset = offset,
							size = (uint64)data.Length
						};
					VulkanNative.vkCmdCopyBuffer(cmdBuf, vkStaging.Buffer, vkBuffer.Buffer, 1, &copyRegion);

					VulkanNative.vkEndCommandBuffer(cmdBuf);

					VkSubmitInfo submitInfo = .()
						{
							sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
							commandBufferCount = 1,
							pCommandBuffers = &cmdBuf
						};

					VulkanNative.vkQueueSubmit(mQueue, 1, &submitInfo, default);
					VulkanNative.vkQueueWaitIdle(mQueue);

					mTransientPool.FreeCommandBuffer(cmdBuffer);
				}
			}

			delete stagingBuffer;
		}
	}

	public void WriteTexture(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout, Extent3D* writeSize, uint32 mipLevel = 0, uint32 arrayLayer = 0)
	{
		let vkTexture = texture as VulkanTexture;
		if (vkTexture == null || data.Length == 0 || dataLayout == null || writeSize == null)
			return;

		// Create staging buffer
		BufferDescriptor stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				MemoryAccess = .Upload
			};

		if (mDevice.CreateBuffer(&stagingDesc) case .Ok(let stagingBuffer))
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

				// Copy staging to texture
				if (mTransientPool.AllocateCommandBuffer() case .Ok(let cmdBuffer))
				{
					var cmdBuf = cmdBuffer;
					VkCommandBufferBeginInfo beginInfo = .()
						{
							sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
							flags = .VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
						};

					VulkanNative.vkBeginCommandBuffer(cmdBuf, &beginInfo);

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
						cmdBuf,
						.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
						.VK_PIPELINE_STAGE_TRANSFER_BIT,
						0, 0, null, 0, null, 1, &barrier
					);

					// Copy buffer to image
					VkBufferImageCopy region = .()
						{
							bufferOffset = dataLayout.Offset,
							bufferRowLength = dataLayout.BytesPerRow / GetFormatBytesPerPixel(vkTexture.Format),
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

					VulkanNative.vkCmdCopyBufferToImage(cmdBuf, vkStaging.Buffer, vkTexture.Image, .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

					// Transition image layout to shader read
					barrier.oldLayout = .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
					barrier.newLayout = .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
					barrier.srcAccessMask = .VK_ACCESS_TRANSFER_WRITE_BIT;
					barrier.dstAccessMask = .VK_ACCESS_SHADER_READ_BIT;

					VulkanNative.vkCmdPipelineBarrier(
						cmdBuf,
						.VK_PIPELINE_STAGE_TRANSFER_BIT,
						.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
						0, 0, null, 0, null, 1, &barrier
					);

					VulkanNative.vkEndCommandBuffer(cmdBuf);

					VkSubmitInfo submitInfo = .()
						{
							sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
							commandBufferCount = 1,
							pCommandBuffers = &cmdBuf
						};

					VulkanNative.vkQueueSubmit(mQueue, 1, &submitInfo, default);
					VulkanNative.vkQueueWaitIdle(mQueue);

					mTransientPool.FreeCommandBuffer(cmdBuffer);
				}
			}

			delete stagingBuffer;
		}
	}

	/// Waits for the queue to be idle.
	public void WaitIdle()
	{
		VulkanNative.vkQueueWaitIdle(mQueue);
	}

	private static uint32 GetFormatBytesPerPixel(TextureFormat format)
	{
		switch (format)
		{
		case .R8Unorm, .R8Snorm, .R8Uint, .R8Sint: return 1;
		case .R16Uint, .R16Sint, .R16Float, .RG8Unorm, .RG8Snorm, .RG8Uint, .RG8Sint: return 2;
		case .R32Uint, .R32Sint, .R32Float, .RG16Uint, .RG16Sint, .RG16Float,
			 .RGBA8Unorm, .RGBA8UnormSrgb, .RGBA8Snorm, .RGBA8Uint, .RGBA8Sint,
			 .BGRA8Unorm, .BGRA8UnormSrgb, .RGB10A2Unorm, .RG11B10Float: return 4;
		case .RG32Uint, .RG32Sint, .RG32Float, .RGBA16Uint, .RGBA16Sint, .RGBA16Float: return 8;
		case .RGBA32Uint, .RGBA32Sint, .RGBA32Float: return 16;
		case .Depth16Unorm: return 2;
		case .Depth24Plus, .Depth24PlusStencil8: return 4;
		case .Depth32Float: return 4;
		case .Depth32FloatStencil8: return 8;
		default: return 4;
		}
	}
}
