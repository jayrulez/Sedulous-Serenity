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
		let vkSwapChain = swapChain as VulkanSwapChain;
		if (vkSwapChain == null)
		{
			// Fallback to regular submit if not a Vulkan swap chain
			if (commandBuffers.Length > 0)
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

		// Always submit even with 0 command buffers to maintain synchronization:
		// - Consumes the ImageAvailableSemaphore from AcquireNextImage
		// - Signals RenderFinishedSemaphore for Present
		// - Signals InFlightFence for next frame's fence wait
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
				pCommandBuffers = vkCommandBuffers.Count > 0 ? vkCommandBuffers.Ptr : null,
				signalSemaphoreCount = 1,
				pSignalSemaphores = &signalSemaphores
			};

		// Signal the in-flight fence so we know when this frame's GPU work is done
		let result = VulkanNative.vkQueueSubmit(mQueue, 1, &submitInfo, vkSwapChain.InFlightFence);
		if (result != .VK_SUCCESS)
		{
			Console.WriteLine(scope $"[Error] vkQueueSubmit failed with: {result}");
		}
	}

	public void Submit(ICommandBuffer commandBuffer, ISwapChain swapChain)
	{
		ICommandBuffer[1] buffers = default;
		if (commandBuffer != null)
			buffers = .(commandBuffer);
		Submit(Span<ICommandBuffer>(&buffers, commandBuffer != null ? 1 : 0), swapChain);
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

	public void WriteMappedBuffer(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let vkBuffer = buffer as VulkanBuffer;
		if (vkBuffer == null || !vkBuffer.IsValid || data.Length == 0)
			return;

		let ptr = vkBuffer.Map();
		if (ptr != null)
		{
			Internal.MemCpy((uint8*)ptr + offset, data.Ptr, data.Length);
			vkBuffer.Unmap();
		}
		else
		{
			Runtime.FatalError("WriteMappedBuffer called on non-mappable buffer. Use WriteStagedBufferSync for device-local buffers.");
		}
	}

	public void WriteStagedBufferSync(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let vkBuffer = buffer as VulkanBuffer;
		if (vkBuffer == null || !vkBuffer.IsValid || data.Length == 0)
			return;

		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				Memory = .CpuToGpu
			};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
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
					Console.WriteLine("[GPU Sync] WriteStagedBufferSync - vkQueueWaitIdle");
					VulkanNative.vkQueueWaitIdle(mQueue);

					mTransientPool.FreeCommandBuffer(cmdBuffer);
				}
			}

			delete stagingBuffer;
		}
	}

	public void WriteTextureSync(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout, Extent3D* writeSize, uint32 mipLevel = 0, uint32 arrayLayer = 0)
	{
		let vkTexture = texture as VulkanTexture;
		if (vkTexture == null || data.Length == 0 || dataLayout == null || writeSize == null)
			return;

		// Create staging buffer
		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				Memory = .CpuToGpu
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
					Console.WriteLine("[GPU Sync] WriteTextureSync - vkQueueWaitIdle");
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
		Console.WriteLine("[GPU Sync] WaitIdle - vkQueueWaitIdle");
		VulkanNative.vkQueueWaitIdle(mQueue);
	}

	public Result<ITransferBatch> CreateTransferBatch()
	{
		return .Ok(new VulkanTransferBatch(mDevice, mQueue, mTransientPool));
	}

	public float GetTimestampPeriod()
	{
		// Get the timestamp period from the physical device properties
		if (let vkAdapter = mDevice.Adapter as VulkanAdapter)
		{
			VkPhysicalDeviceProperties properties = .();
			VulkanNative.vkGetPhysicalDeviceProperties(vkAdapter.PhysicalDevice, &properties);
			return properties.limits.timestampPeriod;
		}
		return 1.0f; // Default to 1 nanosecond if we can't get it
	}

	public void ReadMappedBuffer(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let vkBuffer = buffer as VulkanBuffer;
		if (vkBuffer == null || data.Length == 0)
			return;

		let ptr = vkBuffer.Map();
		if (ptr != null)
		{
			Internal.MemCpy(data.Ptr, (uint8*)ptr + offset, data.Length);
			vkBuffer.Unmap();
		}
		else
		{
			Runtime.FatalError("ReadMappedBuffer called on non-mappable buffer. Use ReadStagedBufferSync for device-local buffers.");
		}
	}

	public void ReadStagedBufferSync(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let vkBuffer = buffer as VulkanBuffer;
		if (vkBuffer == null || data.Length == 0)
			return;

		// For device-local buffers, use staging
		BufferDesc stagingDesc = .()
		{
			Size = (uint64)data.Length,
			Usage = .CopyDst,
			Memory = .GpuToCpu
		};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
		{
			if (let vkStaging = stagingBuffer as VulkanBuffer)
			{
				// Copy source to staging
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
						srcOffset = offset,
						dstOffset = 0,
						size = (uint64)data.Length
					};
					VulkanNative.vkCmdCopyBuffer(cmdBuf, vkBuffer.Buffer, vkStaging.Buffer, 1, &copyRegion);

					VulkanNative.vkEndCommandBuffer(cmdBuf);

					VkSubmitInfo submitInfo = .()
					{
						sType = .VK_STRUCTURE_TYPE_SUBMIT_INFO,
						commandBufferCount = 1,
						pCommandBuffers = &cmdBuf
					};

					VulkanNative.vkQueueSubmit(mQueue, 1, &submitInfo, default);
					Console.WriteLine("[GPU Sync] ReadStagedBufferSync - vkQueueWaitIdle");
					VulkanNative.vkQueueWaitIdle(mQueue);

					mTransientPool.FreeCommandBuffer(cmdBuffer);
				}

				// Copy data from staging buffer
				let stagingPtr = vkStaging.Map();
				if (stagingPtr != null)
				{
					Internal.MemCpy(data.Ptr, stagingPtr, data.Length);
					vkStaging.Unmap();
				}
			}

			delete stagingBuffer;
		}
	}

	public void ReadTextureSync(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout, Extent3D* readSize, uint32 mipLevel = 0, uint32 arrayLayer = 0)
	{
		let vkTexture = texture as VulkanTexture;
		if (vkTexture == null || data.Length == 0 || dataLayout == null || readSize == null)
			return;

		// Create staging buffer
		BufferDesc stagingDesc = .()
		{
			Size = (uint64)data.Length,
			Usage = .CopyDst,
			Memory = .GpuToCpu
		};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
		{
			if (let vkStaging = stagingBuffer as VulkanBuffer)
			{
				// Copy texture to staging
				if (mTransientPool.AllocateCommandBuffer() case .Ok(let cmdBuffer))
				{
					var cmdBuf = cmdBuffer;
					VkCommandBufferBeginInfo beginInfo = .()
					{
						sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
						flags = .VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
					};

					VulkanNative.vkBeginCommandBuffer(cmdBuf, &beginInfo);

					// Transition image layout to transfer source
					VkImageMemoryBarrier barrier = .()
					{
						sType = .VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
						oldLayout = .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,  // Assume common case
						newLayout = .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
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
						srcAccessMask = .VK_ACCESS_SHADER_READ_BIT,
						dstAccessMask = .VK_ACCESS_TRANSFER_READ_BIT
					};

					VulkanNative.vkCmdPipelineBarrier(
						cmdBuf,
						.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
						.VK_PIPELINE_STAGE_TRANSFER_BIT,
						0, 0, null, 0, null, 1, &barrier
					);

					// Copy image to buffer
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
						imageExtent = .() { width = readSize.Width, height = readSize.Height, depth = readSize.Depth }
					};

					VulkanNative.vkCmdCopyImageToBuffer(cmdBuf, vkTexture.Image, .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, vkStaging.Buffer, 1, &region);

					// Transition image layout back to shader read
					barrier.oldLayout = .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
					barrier.newLayout = .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
					barrier.srcAccessMask = .VK_ACCESS_TRANSFER_READ_BIT;
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
					Console.WriteLine("[GPU Sync] ReadTextureSync - vkQueueWaitIdle");
					VulkanNative.vkQueueWaitIdle(mQueue);

					mTransientPool.FreeCommandBuffer(cmdBuffer);
				}

				// Copy data from staging buffer
				let ptr = vkStaging.Map();
				if (ptr != null)
				{
					Internal.MemCpy(data.Ptr, ptr, data.Length);
					vkStaging.Unmap();
				}
			}

			delete stagingBuffer;
		}
	}

}
