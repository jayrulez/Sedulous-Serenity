namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of ICommandEncoder.
class VulkanCommandEncoder : ICommandEncoder
{
	private VulkanDevice mDevice;
	private VulkanCommandPool mPool;
	private VkCommandBuffer mCommandBuffer;
	private bool mIsRecording;
	private bool mFinished;

	// Track render passes created during encoding for cleanup
	private List<VkRenderPass> mCreatedRenderPasses = new .() ~ delete _;
	private List<VkFramebuffer> mCreatedFramebuffers = new .() ~ delete _;

	public this(VulkanDevice device, VulkanCommandPool pool)
	{
		mDevice = device;
		mPool = pool;
		mIsRecording = false;
		mFinished = false;

		// Allocate command buffer
		if (pool.AllocateCommandBuffer() case .Ok(let cmdBuffer))
		{
			mCommandBuffer = cmdBuffer;
			BeginRecording();
		}
	}

	public ~this()
	{
		Cleanup();
	}

	private void Cleanup()
	{
		// Clean up temporary objects
		for (let fb in mCreatedFramebuffers)
			VulkanNative.vkDestroyFramebuffer(mDevice.Device, fb, null);
		mCreatedFramebuffers.Clear();

		for (let rp in mCreatedRenderPasses)
			VulkanNative.vkDestroyRenderPass(mDevice.Device, rp, null);
		mCreatedRenderPasses.Clear();

		// Free command buffer if not finished (finished transfers ownership)
		if (!mFinished && mCommandBuffer != default && mPool != null)
		{
			mPool.FreeCommandBuffer(mCommandBuffer);
			mCommandBuffer = default;
		}
	}

	/// Returns true if the encoder is valid and recording.
	public bool IsValid => mCommandBuffer != default && mIsRecording;

	private void BeginRecording()
	{
		VkCommandBufferBeginInfo beginInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
				flags = .VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
			};

		if (VulkanNative.vkBeginCommandBuffer(mCommandBuffer, &beginInfo) == .VK_SUCCESS)
		{
			mIsRecording = true;
		}
	}

	public IRenderPassEncoder BeginRenderPass(RenderPassDescriptor* descriptor)
	{
		if (!mIsRecording || mFinished)
			return null;

		// Create render pass
		VkRenderPass renderPass = default;
		if (!CreateRenderPass(descriptor, out renderPass))
			return null;

		mCreatedRenderPasses.Add(renderPass);

		// Create framebuffer
		VkFramebuffer framebuffer = default;
		uint32 width = 0;
		uint32 height = 0;
		if (!CreateFramebuffer(descriptor, renderPass, out framebuffer, out width, out height))
			return null;

		mCreatedFramebuffers.Add(framebuffer);

		// Build clear values
		List<VkClearValue> clearValues = scope .();
		for (let colorAttachment in descriptor.ColorAttachments)
		{
			VkClearValue clearValue = .();
			clearValue.color = .() { float32 = .(colorAttachment.ClearValue.R, colorAttachment.ClearValue.G, colorAttachment.ClearValue.B, colorAttachment.ClearValue.A) };
			clearValues.Add(clearValue);
		}

		if (descriptor.DepthStencilAttachment.HasValue)
		{
			let ds = descriptor.DepthStencilAttachment.Value;
			VkClearValue clearValue = .();
			clearValue.depthStencil = .() { depth = ds.DepthClearValue, stencil = ds.StencilClearValue };
			clearValues.Add(clearValue);
		}

		// Begin render pass
		VkRenderPassBeginInfo renderPassInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
				renderPass = renderPass,
				framebuffer = framebuffer,
				renderArea = .() { offset = .() { x = 0, y = 0 }, extent = .() { width = width, height = height } },
				clearValueCount = (uint32)clearValues.Count,
				pClearValues = clearValues.Ptr
			};

		VulkanNative.vkCmdBeginRenderPass(mCommandBuffer, &renderPassInfo, .VK_SUBPASS_CONTENTS_INLINE);

		return new VulkanRenderPassEncoder(mDevice, mCommandBuffer);
	}

	public IComputePassEncoder BeginComputePass()
	{
		if (!mIsRecording || mFinished)
			return null;

		return new VulkanComputePassEncoder(mDevice, mCommandBuffer);
	}

	public void CopyBufferToBuffer(IBuffer source, uint64 sourceOffset, IBuffer destination, uint64 destinationOffset, uint64 size)
	{
		if (!mIsRecording || mFinished)
			return;

		let srcBuffer = source as VulkanBuffer;
		let dstBuffer = destination as VulkanBuffer;

		if (srcBuffer == null || dstBuffer == null)
			return;

		VkBufferCopy copyRegion = .()
			{
				srcOffset = sourceOffset,
				dstOffset = destinationOffset,
				size = size
			};

		VulkanNative.vkCmdCopyBuffer(mCommandBuffer, srcBuffer.Buffer, dstBuffer.Buffer, 1, &copyRegion);
	}

	public void CopyBufferToTexture(IBuffer source, ITexture destination, BufferTextureCopyInfo* copyInfo)
	{
		if (!mIsRecording || mFinished)
			return;

		let srcBuffer = source as VulkanBuffer;
		let dstTexture = destination as VulkanTexture;

		if (srcBuffer == null || dstTexture == null || copyInfo == null)
			return;

		VkBufferImageCopy region = .()
			{
				bufferOffset = copyInfo.BufferLayout.Offset,
				bufferRowLength = copyInfo.BufferLayout.BytesPerRow / GetFormatBytesPerPixel(dstTexture.Format),
				bufferImageHeight = copyInfo.BufferLayout.RowsPerImage,
				imageSubresource = .()
				{
					aspectMask = VulkanConversions.GetAspectFlags(dstTexture.Format),
					mipLevel = copyInfo.TextureMipLevel,
					baseArrayLayer = copyInfo.TextureArrayLayer,
					layerCount = 1
				},
				imageOffset = .() { x = (int32)copyInfo.TextureOrigin.X, y = (int32)copyInfo.TextureOrigin.Y, z = (int32)copyInfo.TextureOrigin.Z },
				imageExtent = .() { width = copyInfo.CopySize.Width, height = copyInfo.CopySize.Height, depth = copyInfo.CopySize.Depth }
			};

		VulkanNative.vkCmdCopyBufferToImage(mCommandBuffer, srcBuffer.Buffer, dstTexture.Image, .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
	}

	public void CopyTextureToBuffer(ITexture source, IBuffer destination, BufferTextureCopyInfo* copyInfo)
	{
		if (!mIsRecording || mFinished)
			return;

		let srcTexture = source as VulkanTexture;
		let dstBuffer = destination as VulkanBuffer;

		if (srcTexture == null || dstBuffer == null || copyInfo == null)
			return;

		VkBufferImageCopy region = .()
			{
				bufferOffset = copyInfo.BufferLayout.Offset,
				bufferRowLength = copyInfo.BufferLayout.BytesPerRow / GetFormatBytesPerPixel(srcTexture.Format),
				bufferImageHeight = copyInfo.BufferLayout.RowsPerImage,
				imageSubresource = .()
				{
					aspectMask = VulkanConversions.GetAspectFlags(srcTexture.Format),
					mipLevel = copyInfo.TextureMipLevel,
					baseArrayLayer = copyInfo.TextureArrayLayer,
					layerCount = 1
				},
				imageOffset = .() { x = (int32)copyInfo.TextureOrigin.X, y = (int32)copyInfo.TextureOrigin.Y, z = (int32)copyInfo.TextureOrigin.Z },
				imageExtent = .() { width = copyInfo.CopySize.Width, height = copyInfo.CopySize.Height, depth = copyInfo.CopySize.Depth }
			};

		VulkanNative.vkCmdCopyImageToBuffer(mCommandBuffer, srcTexture.Image, .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, dstBuffer.Buffer, 1, &region);
	}

	public void CopyTextureToTexture(ITexture source, ITexture destination, TextureCopyInfo* copyInfo)
	{
		if (!mIsRecording || mFinished)
			return;

		let srcTexture = source as VulkanTexture;
		let dstTexture = destination as VulkanTexture;

		if (srcTexture == null || dstTexture == null || copyInfo == null)
			return;

		VkImageCopy region = .()
			{
				srcSubresource = .()
				{
					aspectMask = VulkanConversions.GetAspectFlags(srcTexture.Format),
					mipLevel = copyInfo.SrcMipLevel,
					baseArrayLayer = copyInfo.SrcArrayLayer,
					layerCount = 1
				},
				srcOffset = .() { x = (int32)copyInfo.SrcOrigin.X, y = (int32)copyInfo.SrcOrigin.Y, z = (int32)copyInfo.SrcOrigin.Z },
				dstSubresource = .()
				{
					aspectMask = VulkanConversions.GetAspectFlags(dstTexture.Format),
					mipLevel = copyInfo.DstMipLevel,
					baseArrayLayer = copyInfo.DstArrayLayer,
					layerCount = 1
				},
				dstOffset = .() { x = (int32)copyInfo.DstOrigin.X, y = (int32)copyInfo.DstOrigin.Y, z = (int32)copyInfo.DstOrigin.Z },
				extent = .() { width = copyInfo.CopySize.Width, height = copyInfo.CopySize.Height, depth = copyInfo.CopySize.Depth }
			};

		VulkanNative.vkCmdCopyImage(mCommandBuffer, srcTexture.Image, .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, dstTexture.Image, .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
	}

	public void TextureBarrier(ITexture texture, TextureLayout oldLayout, TextureLayout newLayout)
	{
		if (!mIsRecording || mFinished)
			return;

		let vkTexture = texture as VulkanTexture;
		if (vkTexture == null)
			return;

		VkImageLayout vkOldLayout = ToVkImageLayout(oldLayout);
		VkImageLayout vkNewLayout = ToVkImageLayout(newLayout);

		// Determine access masks and pipeline stages based on layouts
		VkAccessFlags srcAccess = default;
		VkAccessFlags dstAccess = default;
		VkPipelineStageFlags srcStage = default;
		VkPipelineStageFlags dstStage = default;

		// Source layout access
		switch (oldLayout)
		{
		case .Undefined:
			srcAccess = 0;
			srcStage = .VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
		case .ColorAttachment:
			srcAccess = .VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
			srcStage = .VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		case .DepthStencilAttachment:
			srcAccess = .VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
			srcStage = .VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
		case .ShaderReadOnly:
			srcAccess = .VK_ACCESS_SHADER_READ_BIT;
			srcStage = .VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
		case .TransferSrc:
			srcAccess = .VK_ACCESS_TRANSFER_READ_BIT;
			srcStage = .VK_PIPELINE_STAGE_TRANSFER_BIT;
		case .TransferDst:
			srcAccess = .VK_ACCESS_TRANSFER_WRITE_BIT;
			srcStage = .VK_PIPELINE_STAGE_TRANSFER_BIT;
		case .Present:
			srcAccess = 0;
			srcStage = .VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
		case .General:
			srcAccess = .VK_ACCESS_MEMORY_READ_BIT | .VK_ACCESS_MEMORY_WRITE_BIT;
			srcStage = .VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
		}

		// Destination layout access
		switch (newLayout)
		{
		case .Undefined:
			dstAccess = 0;
			dstStage = .VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
		case .ColorAttachment:
			dstAccess = .VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | .VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
			dstStage = .VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		case .DepthStencilAttachment:
			dstAccess = .VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | .VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
			dstStage = .VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
		case .ShaderReadOnly:
			dstAccess = .VK_ACCESS_SHADER_READ_BIT;
			dstStage = .VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
		case .TransferSrc:
			dstAccess = .VK_ACCESS_TRANSFER_READ_BIT;
			dstStage = .VK_PIPELINE_STAGE_TRANSFER_BIT;
		case .TransferDst:
			dstAccess = .VK_ACCESS_TRANSFER_WRITE_BIT;
			dstStage = .VK_PIPELINE_STAGE_TRANSFER_BIT;
		case .Present:
			dstAccess = 0;
			dstStage = .VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
		case .General:
			dstAccess = .VK_ACCESS_MEMORY_READ_BIT | .VK_ACCESS_MEMORY_WRITE_BIT;
			dstStage = .VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
		}

		VkImageMemoryBarrier barrier = .()
		{
			sType = .VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
			oldLayout = vkOldLayout,
			newLayout = vkNewLayout,
			srcQueueFamilyIndex = VulkanNative.VK_QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = VulkanNative.VK_QUEUE_FAMILY_IGNORED,
			image = vkTexture.Image,
			subresourceRange = .()
			{
				aspectMask = VulkanConversions.GetAspectFlags(vkTexture.Format),
				baseMipLevel = 0,
				levelCount = vkTexture.MipLevelCount,
				baseArrayLayer = 0,
				layerCount = 1
			},
			srcAccessMask = srcAccess,
			dstAccessMask = dstAccess
		};

		VulkanNative.vkCmdPipelineBarrier(
			mCommandBuffer,
			srcStage,
			dstStage,
			0,
			0, null,
			0, null,
			1, &barrier
		);
	}

	private static VkImageLayout ToVkImageLayout(TextureLayout layout)
	{
		switch (layout)
		{
		case .Undefined: return .VK_IMAGE_LAYOUT_UNDEFINED;
		case .General: return .VK_IMAGE_LAYOUT_GENERAL;
		case .ColorAttachment: return .VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
		case .DepthStencilAttachment: return .VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		case .ShaderReadOnly: return .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
		case .TransferSrc: return .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
		case .TransferDst: return .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
		case .Present: return .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
		}
	}

	public void GenerateMipmaps(ITexture texture)
	{
		if (!mIsRecording || mFinished)
			return;

		let vkTexture = texture as VulkanTexture;
		if (vkTexture == null)
			return;

		let mipLevels = vkTexture.MipLevelCount;
		if (mipLevels <= 1)
			return; // Nothing to generate

		int32 mipWidth = (int32)vkTexture.Width;
		int32 mipHeight = (int32)vkTexture.Height;
		let aspectMask = VulkanConversions.GetAspectFlags(vkTexture.Format);

		// Transition mip level 0 to transfer_src
		// Use UNDEFINED as old layout to handle any previous state (WriteTexture leaves it in SHADER_READ_ONLY)
		VkImageMemoryBarrier barrier = .()
		{
			sType = .VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
			srcQueueFamilyIndex = VulkanNative.VK_QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = VulkanNative.VK_QUEUE_FAMILY_IGNORED,
			image = vkTexture.Image,
			subresourceRange = .()
			{
				aspectMask = aspectMask,
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1
			},
			oldLayout = .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, // WriteTexture leaves it in this state
			newLayout = .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
			srcAccessMask = .VK_ACCESS_SHADER_READ_BIT,
			dstAccessMask = .VK_ACCESS_TRANSFER_READ_BIT
		};

		VulkanNative.vkCmdPipelineBarrier(
			mCommandBuffer,
			.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
			.VK_PIPELINE_STAGE_TRANSFER_BIT,
			0,
			0, null,
			0, null,
			1, &barrier
		);

		// Generate each mip level by blitting from the previous level
		for (uint32 i = 1; i < mipLevels; i++)
		{
			// Transition current mip level to transfer dst
			barrier.subresourceRange.baseMipLevel = i;
			barrier.oldLayout = .VK_IMAGE_LAYOUT_UNDEFINED;
			barrier.newLayout = .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
			barrier.srcAccessMask = 0;
			barrier.dstAccessMask = .VK_ACCESS_TRANSFER_WRITE_BIT;

			VulkanNative.vkCmdPipelineBarrier(
				mCommandBuffer,
				.VK_PIPELINE_STAGE_TRANSFER_BIT,
				.VK_PIPELINE_STAGE_TRANSFER_BIT,
				0,
				0, null,
				0, null,
				1, &barrier
			);

			// Calculate destination dimensions
			int32 dstWidth = mipWidth > 1 ? mipWidth / 2 : 1;
			int32 dstHeight = mipHeight > 1 ? mipHeight / 2 : 1;

			// Blit from previous level to current level
			VkImageBlit blit = .()
			{
				srcSubresource = .()
				{
					aspectMask = aspectMask,
					mipLevel = i - 1,
					baseArrayLayer = 0,
					layerCount = 1
				},
				srcOffsets = .(
					.() { x = 0, y = 0, z = 0 },
					.() { x = mipWidth, y = mipHeight, z = 1 }
				),
				dstSubresource = .()
				{
					aspectMask = aspectMask,
					mipLevel = i,
					baseArrayLayer = 0,
					layerCount = 1
				},
				dstOffsets = .(
					.() { x = 0, y = 0, z = 0 },
					.() { x = dstWidth, y = dstHeight, z = 1 }
				)
			};

			VulkanNative.vkCmdBlitImage(
				mCommandBuffer,
				vkTexture.Image, .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
				vkTexture.Image, .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
				1, &blit,
				.VK_FILTER_LINEAR
			);

			// Transition current mip level to transfer src for the next iteration
			barrier.oldLayout = .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
			barrier.newLayout = .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
			barrier.srcAccessMask = .VK_ACCESS_TRANSFER_WRITE_BIT;
			barrier.dstAccessMask = .VK_ACCESS_TRANSFER_READ_BIT;

			VulkanNative.vkCmdPipelineBarrier(
				mCommandBuffer,
				.VK_PIPELINE_STAGE_TRANSFER_BIT,
				.VK_PIPELINE_STAGE_TRANSFER_BIT,
				0,
				0, null,
				0, null,
				1, &barrier
			);

			// Update dimensions for next iteration
			mipWidth = dstWidth;
			mipHeight = dstHeight;
		}

		// Transition all mip levels to shader read optimal
		barrier.subresourceRange.baseMipLevel = 0;
		barrier.subresourceRange.levelCount = mipLevels;
		barrier.oldLayout = .VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
		barrier.newLayout = .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
		barrier.srcAccessMask = .VK_ACCESS_TRANSFER_READ_BIT;
		barrier.dstAccessMask = .VK_ACCESS_SHADER_READ_BIT;

		VulkanNative.vkCmdPipelineBarrier(
			mCommandBuffer,
			.VK_PIPELINE_STAGE_TRANSFER_BIT,
			.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
			0,
			0, null,
			0, null,
			1, &barrier
		);
	}

	public void ResetQuerySet(IQuerySet querySet, uint32 firstQuery, uint32 queryCount)
	{
		if (!mIsRecording || mFinished)
			return;

		let vkQuerySet = querySet as VulkanQuerySet;
		if (vkQuerySet == null)
			return;

		VulkanNative.vkCmdResetQueryPool(mCommandBuffer, vkQuerySet.QueryPool, firstQuery, queryCount);
	}

	public void WriteTimestamp(IQuerySet querySet, uint32 queryIndex)
	{
		if (!mIsRecording || mFinished)
			return;

		let vkQuerySet = querySet as VulkanQuerySet;
		if (vkQuerySet == null || vkQuerySet.Type != .Timestamp)
			return;

		// Write timestamp at the bottom of the pipeline (after all previous commands complete)
		VulkanNative.vkCmdWriteTimestamp(mCommandBuffer, .VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, vkQuerySet.QueryPool, queryIndex);
	}

	public void BeginQuery(IQuerySet querySet, uint32 queryIndex)
	{
		if (!mIsRecording || mFinished)
			return;

		let vkQuerySet = querySet as VulkanQuerySet;
		if (vkQuerySet == null)
			return;

		// Timestamp queries use WriteTimestamp, not Begin/End
		if (vkQuerySet.Type == .Timestamp)
			return;

		// Note: VK_QUERY_CONTROL_PRECISE_BIT requires the occlusionQueryPrecise device feature
		// We use default (non-precise) for broader compatibility
		VulkanNative.vkCmdBeginQuery(mCommandBuffer, vkQuerySet.QueryPool, queryIndex, 0);
	}

	public void EndQuery(IQuerySet querySet, uint32 queryIndex)
	{
		if (!mIsRecording || mFinished)
			return;

		let vkQuerySet = querySet as VulkanQuerySet;
		if (vkQuerySet == null)
			return;

		// Timestamp queries use WriteTimestamp, not Begin/End
		if (vkQuerySet.Type == .Timestamp)
			return;

		VulkanNative.vkCmdEndQuery(mCommandBuffer, vkQuerySet.QueryPool, queryIndex);
	}

	public void ResolveQuerySet(IQuerySet querySet, uint32 firstQuery, uint32 queryCount, IBuffer destination, uint64 destinationOffset)
	{
		if (!mIsRecording || mFinished)
			return;

		let vkQuerySet = querySet as VulkanQuerySet;
		let vkBuffer = destination as VulkanBuffer;
		if (vkQuerySet == null || vkBuffer == null)
			return;

		VkQueryResultFlags flags = .VK_QUERY_RESULT_64_BIT | .VK_QUERY_RESULT_WAIT_BIT;

		uint64 stride;
		switch (vkQuerySet.Type)
		{
		case .Timestamp, .Occlusion:
			stride = sizeof(uint64);
		case .PipelineStatistics:
			stride = (uint64)sizeof(PipelineStatistics);
		}

		VulkanNative.vkCmdCopyQueryPoolResults(
			mCommandBuffer,
			vkQuerySet.QueryPool,
			firstQuery,
			queryCount,
			vkBuffer.Buffer,
			destinationOffset,
			stride,
			flags
		);
	}

	public ICommandBuffer Finish()
	{
		if (!mIsRecording || mFinished)
			return null;

		if (VulkanNative.vkEndCommandBuffer(mCommandBuffer) != .VK_SUCCESS)
			return null;

		mIsRecording = false;
		mFinished = true;

		let cmdBuffer = new VulkanCommandBuffer(mDevice, mPool, mCommandBuffer);

		// Transfer ownership of render passes and framebuffers to the command buffer
		// They must stay alive until GPU is done executing the command buffer
		cmdBuffer.TakeOwnership(mCreatedRenderPasses, mCreatedFramebuffers);

		// Clear our lists so we don't double-delete in Cleanup()
		mCreatedRenderPasses.Clear();
		mCreatedFramebuffers.Clear();

		return cmdBuffer;
	}

	private bool CreateRenderPass(RenderPassDescriptor* descriptor, out VkRenderPass renderPass)
	{
		renderPass = default;

		List<VkAttachmentDescription> attachments = scope .();
		List<VkAttachmentReference> colorRefs = scope .();
		VkAttachmentReference depthRef = .();
		bool hasDepth = false;

		// Color attachments
		for (let colorAttachment in descriptor.ColorAttachments)
		{
			if (colorAttachment.View == null)
				continue;

			let vkView = colorAttachment.View as VulkanTextureView;
			if (vkView == null)
				continue;

			// Determine final layout - swap chain textures need PRESENT_SRC_KHR
			VkImageLayout finalLayout = .VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
			if (let vkTexture = vkView.Texture as VulkanTexture)
			{
				if (vkTexture.IsSwapChainTexture)
					finalLayout = .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
			}

			uint32 index = (uint32)attachments.Count;
			attachments.Add(.()
				{
					format = VulkanConversions.ToVkFormat(vkView.Format),
					samples = .VK_SAMPLE_COUNT_1_BIT,
					loadOp = ToVkLoadOp(colorAttachment.LoadOp),
					storeOp = ToVkStoreOp(colorAttachment.StoreOp),
					stencilLoadOp = .VK_ATTACHMENT_LOAD_OP_DONT_CARE,
					stencilStoreOp = .VK_ATTACHMENT_STORE_OP_DONT_CARE,
					initialLayout = colorAttachment.LoadOp == .Load ? .VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : .VK_IMAGE_LAYOUT_UNDEFINED,
					finalLayout = finalLayout
				});

			colorRefs.Add(.()
				{
					attachment = index,
					layout = .VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
				});
		}

		// Depth attachment
		if (descriptor.DepthStencilAttachment.HasValue)
		{
			let ds = descriptor.DepthStencilAttachment.Value;
			if (ds.View != null)
			{
				let vkView = ds.View as VulkanTextureView;
				if (vkView != null)
				{
					uint32 index = (uint32)attachments.Count;
					bool hasStencil = VulkanConversions.HasStencilComponent(vkView.Format);

					attachments.Add(.()
						{
							format = VulkanConversions.ToVkFormat(vkView.Format),
							samples = .VK_SAMPLE_COUNT_1_BIT,
							loadOp = ToVkLoadOp(ds.DepthLoadOp),
							storeOp = ToVkStoreOp(ds.DepthStoreOp),
							stencilLoadOp = hasStencil ? ToVkLoadOp(ds.StencilLoadOp) : .VK_ATTACHMENT_LOAD_OP_DONT_CARE,
							stencilStoreOp = hasStencil ? ToVkStoreOp(ds.StencilStoreOp) : .VK_ATTACHMENT_STORE_OP_DONT_CARE,
							initialLayout = ds.DepthLoadOp == .Load ? .VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL : .VK_IMAGE_LAYOUT_UNDEFINED,
							finalLayout = .VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
						});

					depthRef = .()
						{
							attachment = index,
							layout = .VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
						};
					hasDepth = true;
				}
			}
		}

		if (attachments.Count == 0)
			return false;

		VkSubpassDescription subpass = .()
			{
				pipelineBindPoint = .VK_PIPELINE_BIND_POINT_GRAPHICS,
				colorAttachmentCount = (uint32)colorRefs.Count,
				pColorAttachments = colorRefs.Ptr,
				pDepthStencilAttachment = hasDepth ? &depthRef : null
			};

		VkSubpassDependency dependency = .()
			{
				srcSubpass = VulkanNative.VK_SUBPASS_EXTERNAL,
				dstSubpass = 0,
				srcStageMask = .VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | .VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
				dstStageMask = .VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | .VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
				srcAccessMask = 0,
				dstAccessMask = .VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | .VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT
			};

		VkRenderPassCreateInfo renderPassInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
				attachmentCount = (uint32)attachments.Count,
				pAttachments = attachments.Ptr,
				subpassCount = 1,
				pSubpasses = &subpass,
				dependencyCount = 1,
				pDependencies = &dependency
			};

		return VulkanNative.vkCreateRenderPass(mDevice.Device, &renderPassInfo, null, &renderPass) == .VK_SUCCESS;
	}

	private bool CreateFramebuffer(RenderPassDescriptor* descriptor, VkRenderPass renderPass, out VkFramebuffer framebuffer, out uint32 width, out uint32 height)
	{
		framebuffer = default;
		width = 0;
		height = 0;

		List<VkImageView> attachmentViews = scope .();

		// Collect image views and determine dimensions
		for (let colorAttachment in descriptor.ColorAttachments)
		{
			if (colorAttachment.View == null)
				continue;

			let vkView = colorAttachment.View as VulkanTextureView;
			if (vkView == null)
				continue;

			attachmentViews.Add(vkView.ImageView);

			if (let vkTexture = vkView.Texture as VulkanTexture)
			{
				width = vkTexture.Width;
				height = vkTexture.Height;
			}
		}

		if (descriptor.DepthStencilAttachment.HasValue)
		{
			let ds = descriptor.DepthStencilAttachment.Value;
			if (ds.View != null)
			{
				let vkView = ds.View as VulkanTextureView;
				if (vkView != null)
				{
					attachmentViews.Add(vkView.ImageView);

					if (width == 0 || height == 0)
					{
						if (let vkTexture = vkView.Texture as VulkanTexture)
						{
							width = vkTexture.Width;
							height = vkTexture.Height;
						}
					}
				}
			}
		}

		if (attachmentViews.Count == 0 || width == 0 || height == 0)
			return false;

		VkFramebufferCreateInfo framebufferInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
				renderPass = renderPass,
				attachmentCount = (uint32)attachmentViews.Count,
				pAttachments = attachmentViews.Ptr,
				width = width,
				height = height,
				layers = 1
			};

		return VulkanNative.vkCreateFramebuffer(mDevice.Device, &framebufferInfo, null, &framebuffer) == .VK_SUCCESS;
	}

	private static VkAttachmentLoadOp ToVkLoadOp(LoadOp op)
	{
		switch (op)
		{
		case .Clear: return .VK_ATTACHMENT_LOAD_OP_CLEAR;
		case .Load: return .VK_ATTACHMENT_LOAD_OP_LOAD;
		case .DontCare: return .VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		}
	}

	private static VkAttachmentStoreOp ToVkStoreOp(StoreOp op)
	{
		switch (op)
		{
		case .Store: return .VK_ATTACHMENT_STORE_OP_STORE;
		case .Discard: return .VK_ATTACHMENT_STORE_OP_DONT_CARE;
		}
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
