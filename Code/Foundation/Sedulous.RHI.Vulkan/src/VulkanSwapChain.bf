namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of ISwapChain.
class VulkanSwapChain : ISwapChain
{
	private VulkanDevice mDevice;
	private VulkanSurface mSurface;
	private VkSwapchainKHR mSwapChain;
	private TextureFormat mFormat;
	private uint32 mWidth;
	private uint32 mHeight;
	private PresentMode mPresentMode;
	private TextureUsage mUsage;

	private List<VkImage> mImages = new .() ~ delete _;
	private List<VulkanTexture> mTextures = new .() ~ DeleteContainerAndItems!(_);
	private List<VulkanTextureView> mTextureViews = new .() ~ DeleteContainerAndItems!(_);

	private uint32 mCurrentImageIndex = 0;
	private uint32 mCurrentFrameIndex = 0;

	// Per-frame fences for CPU/GPU synchronization (use centralized FrameConfig)
	private const int MAX_FRAMES_IN_FLIGHT = Sedulous.RHI.FrameConfig.MAX_FRAMES_IN_FLIGHT;
	private VkFence[MAX_FRAMES_IN_FLIGHT] mInFlightFences;

	// Per-swapchain-image semaphores (sized dynamically based on image count)
	// Indexed by image index to ensure each image has its own semaphores
	private List<VkSemaphore> mImageAvailableSemaphores = new .() ~ delete _;
	private List<VkSemaphore> mRenderFinishedSemaphores = new .() ~ delete _;

	// Rolling index for acquire semaphores - we don't know which image we'll get
	// until after vkAcquireNextImageKHR, so we cycle through semaphores
	private uint32 mAcquireSemaphoreIndex = 0;

	public this(VulkanDevice device, VulkanSurface surface, SwapChainDescriptor* descriptor)
	{
		mDevice = device;
		mSurface = surface;
		mWidth = descriptor.Width;
		mHeight = descriptor.Height;
		mFormat = descriptor.Format;
		mPresentMode = descriptor.PresentMode;
		mUsage = descriptor.Usage;

		CreateSwapChain();
		CreateSemaphores();
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		mDevice.WaitIdle();

		CleanupSwapChain();
		CleanupSyncObjects();
	}

	private void CleanupSyncObjects()
	{
		// Clean up per-image semaphores
		for (let sem in mImageAvailableSemaphores)
		{
			if (sem != default)
				VulkanNative.vkDestroySemaphore(mDevice.Device, sem, null);
		}
		mImageAvailableSemaphores.Clear();

		for (let sem in mRenderFinishedSemaphores)
		{
			if (sem != default)
				VulkanNative.vkDestroySemaphore(mDevice.Device, sem, null);
		}
		mRenderFinishedSemaphores.Clear();

		// Clean up per-frame fences
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (mInFlightFences[i] != default)
			{
				VulkanNative.vkDestroyFence(mDevice.Device, mInFlightFences[i], null);
				mInFlightFences[i] = default;
			}
		}
	}

	public TextureFormat Format => mFormat;
	public uint32 Width => mWidth;
	public uint32 Height => mHeight;

	public ITexture CurrentTexture => mTextures.Count > 0 ? mTextures[mCurrentImageIndex] : null;
	public ITextureView CurrentTextureView => mTextureViews.Count > 0 ? mTextureViews[mCurrentImageIndex] : null;

	/// Gets the Vulkan swapchain handle.
	public VkSwapchainKHR SwapChain => mSwapChain;

	/// Gets the image available semaphore (the one used for the last acquire).
	public VkSemaphore ImageAvailableSemaphore => mImageAvailableSemaphores[mAcquireSemaphoreIndex];

	/// Gets the render finished semaphore for the current image.
	public VkSemaphore RenderFinishedSemaphore => mRenderFinishedSemaphores[mCurrentImageIndex];

	/// Gets the in-flight fence for the current frame.
	public VkFence InFlightFence => mInFlightFences[mCurrentFrameIndex];

	/// Gets the current image index.
	public uint32 CurrentImageIndex => mCurrentImageIndex;

	/// Gets the current frame index (for frame-in-flight tracking).
	public uint32 CurrentFrameIndex => mCurrentFrameIndex;

	/// Gets the number of frames in flight.
	public uint32 FrameCount => MAX_FRAMES_IN_FLIGHT;

	public Result<void> AcquireNextImage()
	{
		// Wait for the current frame's fence to ensure we can reuse its resources
		// Use a timeout to prevent deadlock if previous frame failed to signal the fence
		var fence = mInFlightFences[mCurrentFrameIndex];
		let waitResult = VulkanNative.vkWaitForFences(mDevice.Device, 1, &fence, VkBool32.True, 1000000000); // 1 second timeout in nanoseconds

		if (waitResult == .VK_TIMEOUT)
		{
			// Fence was never signaled - previous frame likely failed
			// Don't call WaitIdle here as it can block indefinitely
			// Just log and continue - the error counter will handle repeated failures
			Console.WriteLine("[Warning] Frame fence timeout - previous frame may have failed");
			// Reset all fences to try to recover
			for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
			{
				var f = mInFlightFences[i];
				VulkanNative.vkResetFences(mDevice.Device, 1, &f);
			}
		}
		else if (waitResult != .VK_SUCCESS)
		{
			return .Err;
		}
		else
		{
			// Only reset if wait succeeded (fence was signaled)
			VulkanNative.vkResetFences(mDevice.Device, 1, &fence);
		}

		// Use the next acquire semaphore in the ring buffer
		// We increment BEFORE acquire so the property returns the right semaphore
		mAcquireSemaphoreIndex = (mAcquireSemaphoreIndex + 1) % (uint32)mImageAvailableSemaphores.Count;

		// Use a timeout for acquire to prevent lockup if swap chain is in bad state
		var result = VulkanNative.vkAcquireNextImageKHR(
			mDevice.Device,
			mSwapChain,
			1000000000, // 1 second timeout
			mImageAvailableSemaphores[mAcquireSemaphoreIndex],
			default,
			&mCurrentImageIndex
		);

		if (result == .VK_TIMEOUT)
		{
			Console.WriteLine("[Warning] Swap chain acquire timeout");
			return .Err;
		}
		else if (result == .VK_ERROR_OUT_OF_DATE_KHR)
		{
			// Swap chain needs to be recreated
			return .Err;
		}
		else if (result != .VK_SUCCESS && result != .VK_SUBOPTIMAL_KHR)
		{
			return .Err;
		}

		return .Ok;
	}

	public Result<void> Present()
	{
		// Use the current image's render finished semaphore
		VkSemaphore[1] waitSemaphores = .(mRenderFinishedSemaphores[mCurrentImageIndex]);
		VkSwapchainKHR[1] swapChains = .(mSwapChain);
		uint32[1] imageIndices = .(mCurrentImageIndex);

		VkPresentInfoKHR presentInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
				waitSemaphoreCount = 1,
				pWaitSemaphores = &waitSemaphores,
				swapchainCount = 1,
				pSwapchains = &swapChains,
				pImageIndices = &imageIndices,
				pResults = null
			};

		let vkQueue = mDevice.Queue as VulkanQueue;
		if (vkQueue == null)
			return .Err;

		var result = VulkanNative.vkQueuePresentKHR(vkQueue.Queue, &presentInfo);

		// Advance to next frame
		mCurrentFrameIndex = (mCurrentFrameIndex + 1) % MAX_FRAMES_IN_FLIGHT;

		if (result == .VK_ERROR_OUT_OF_DATE_KHR || result == .VK_SUBOPTIMAL_KHR)
		{
			return .Err;
		}
		else if (result != .VK_SUCCESS)
		{
			return .Err;
		}

		return .Ok;
	}

	public Result<void> Resize(uint32 width, uint32 height)
	{
		if (width == 0 || height == 0)
			return .Err;

		mWidth = width;
		mHeight = height;

		mDevice.WaitIdle();
		CleanupSwapChain();

		// Clean up semaphores since image count might change
		for (let sem in mImageAvailableSemaphores)
		{
			if (sem != default)
				VulkanNative.vkDestroySemaphore(mDevice.Device, sem, null);
		}
		mImageAvailableSemaphores.Clear();

		for (let sem in mRenderFinishedSemaphores)
		{
			if (sem != default)
				VulkanNative.vkDestroySemaphore(mDevice.Device, sem, null);
		}
		mRenderFinishedSemaphores.Clear();

		if (!CreateSwapChain())
			return .Err;

		// Recreate semaphores for new image count
		VkSemaphoreCreateInfo semaphoreInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
			};

		let imageCount = mImages.Count;
		for (int i = 0; i < imageCount; i++)
		{
			VkSemaphore imageAvailable = default;
			VkSemaphore renderFinished = default;
			VulkanNative.vkCreateSemaphore(mDevice.Device, &semaphoreInfo, null, &imageAvailable);
			VulkanNative.vkCreateSemaphore(mDevice.Device, &semaphoreInfo, null, &renderFinished);
			mImageAvailableSemaphores.Add(imageAvailable);
			mRenderFinishedSemaphores.Add(renderFinished);
		}

		mAcquireSemaphoreIndex = (uint32)(imageCount - 1);
		mCurrentFrameIndex = 0;

		return .Ok;
	}

	private bool CreateSwapChain()
	{
		let vkAdapter = mDevice.Adapter as VulkanAdapter;
		if (vkAdapter == null)
			return false;
		let physicalDevice = vkAdapter.PhysicalDevice;

		// Query surface capabilities
		VkSurfaceCapabilitiesKHR capabilities = ?;
		VulkanNative.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, mSurface.Surface, &capabilities);

		// Choose surface format
		VkSurfaceFormatKHR surfaceFormat = ChooseSurfaceFormat();

		// Choose present mode
		VkPresentModeKHR presentMode = ChoosePresentMode();

		// Choose extent
		VkExtent2D extent = ChooseExtent(&capabilities);
		mWidth = extent.width;
		mHeight = extent.height;

		// Choose image count
		uint32 imageCount = capabilities.minImageCount + 1;
		if (capabilities.maxImageCount > 0 && imageCount > capabilities.maxImageCount)
			imageCount = capabilities.maxImageCount;

		// Create swap chain
		VkSwapchainCreateInfoKHR createInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
				surface = mSurface.Surface,
				minImageCount = imageCount,
				imageFormat = surfaceFormat.format,
				imageColorSpace = surfaceFormat.colorSpace,
				imageExtent = extent,
				imageArrayLayers = 1,
				imageUsage = GetVkImageUsage(),
				imageSharingMode = .VK_SHARING_MODE_EXCLUSIVE,
				queueFamilyIndexCount = 0,
				pQueueFamilyIndices = null,
				preTransform = capabilities.currentTransform,
				compositeAlpha = .VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
				presentMode = presentMode,
				clipped = VkBool32.True,
				oldSwapchain = default
			};

		if (VulkanNative.vkCreateSwapchainKHR(mDevice.Device, &createInfo, null, &mSwapChain) != .VK_SUCCESS)
			return false;

		// Get swap chain images
		uint32 swapImageCount = 0;
		VulkanNative.vkGetSwapchainImagesKHR(mDevice.Device, mSwapChain, &swapImageCount, null);
		mImages.Resize(swapImageCount);
		VulkanNative.vkGetSwapchainImagesKHR(mDevice.Device, mSwapChain, &swapImageCount, mImages.Ptr);

		// Store format
		mFormat = VulkanConversions.ToTextureFormat(surfaceFormat.format);

		// Create texture wrappers and views
		for (let image in mImages)
		{
			// Create texture wrapper (doesn't own the image, is a swap chain texture)
			let texture = new VulkanTexture(mDevice, image, mFormat, mWidth, mHeight, .RenderTarget, true);
			mTextures.Add(texture);

			// Create texture view
			TextureViewDescriptor viewDesc = .()
				{
					Format = mFormat,
					Dimension = .Texture2D,
					BaseMipLevel = 0,
					MipLevelCount = 1,
					BaseArrayLayer = 0,
					ArrayLayerCount = 1,
					Label = scope $"SwapchainTexture{mImages.IndexOf(image)}"
				};

			if (mDevice.CreateTextureView(texture, &viewDesc) case .Ok(let view))
			{
				if (let vkView = view as VulkanTextureView)
					mTextureViews.Add(vkView);
			}
		}

		return true;
	}

	private void CleanupSwapChain()
	{
		// Clean up texture views first
		for (let view in mTextureViews)
			delete view;
		mTextureViews.Clear();

		// Clean up texture wrappers (don't delete images - they're owned by swap chain)
		for (let texture in mTextures)
			delete texture;
		mTextures.Clear();

		mImages.Clear();

		if (mSwapChain != default)
		{
			VulkanNative.vkDestroySwapchainKHR(mDevice.Device, mSwapChain, null);
			mSwapChain = default;
		}
	}

	private void CreateSemaphores()
	{
		VkSemaphoreCreateInfo semaphoreInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
			};

		VkFenceCreateInfo fenceInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
				flags = .VK_FENCE_CREATE_SIGNALED_BIT  // Start signaled so first wait doesn't block forever
			};

		// Create per-frame fences
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			VulkanNative.vkCreateFence(mDevice.Device, &fenceInfo, null, &mInFlightFences[i]);
		}

		// Create per-image semaphores (one for each swapchain image)
		let imageCount = mImages.Count;
		for (int i = 0; i < imageCount; i++)
		{
			VkSemaphore imageAvailable = default;
			VkSemaphore renderFinished = default;
			VulkanNative.vkCreateSemaphore(mDevice.Device, &semaphoreInfo, null, &imageAvailable);
			VulkanNative.vkCreateSemaphore(mDevice.Device, &semaphoreInfo, null, &renderFinished);
			mImageAvailableSemaphores.Add(imageAvailable);
			mRenderFinishedSemaphores.Add(renderFinished);
		}

		// Initialize acquire semaphore index to point to last entry so first increment wraps to 0
		mAcquireSemaphoreIndex = (uint32)(imageCount - 1);
	}

	private VkSurfaceFormatKHR ChooseSurfaceFormat()
	{
		let vkAdapter = mDevice.Adapter as VulkanAdapter;
		if (vkAdapter == null)
			return .() { format = .VK_FORMAT_B8G8R8A8_SRGB, colorSpace = .VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
		let physicalDevice = vkAdapter.PhysicalDevice;

		uint32 formatCount = 0;
		VulkanNative.vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, mSurface.Surface, &formatCount, null);

		if (formatCount == 0)
			return .() { format = .VK_FORMAT_B8G8R8A8_SRGB, colorSpace = .VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };

		List<VkSurfaceFormatKHR> formats = scope .();
		formats.Resize(formatCount);
		VulkanNative.vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, mSurface.Surface, &formatCount, formats.Ptr);

		// Try to find preferred format
		VkFormat preferredFormat = VulkanConversions.ToVkFormat(mFormat);

		for (let format in formats)
		{
			if (format.format == preferredFormat)
				return format;
		}

		// Fallback to common sRGB format
		for (let format in formats)
		{
			if (format.format == .VK_FORMAT_B8G8R8A8_SRGB && format.colorSpace == .VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
				return format;
		}

		// Use first available
		return formats[0];
	}

	private VkPresentModeKHR ChoosePresentMode()
	{
		let vkAdapter = mDevice.Adapter as VulkanAdapter;
		if (vkAdapter == null)
			return .VK_PRESENT_MODE_FIFO_KHR;
		let physicalDevice = vkAdapter.PhysicalDevice;

		uint32 presentModeCount = 0;
		VulkanNative.vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, mSurface.Surface, &presentModeCount, null);

		if (presentModeCount == 0)
			return .VK_PRESENT_MODE_FIFO_KHR;

		List<VkPresentModeKHR> presentModes = scope .();
		presentModes.Resize(presentModeCount);
		VulkanNative.vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, mSurface.Surface, &presentModeCount, presentModes.Ptr);

		VkPresentModeKHR preferredMode = VulkanConversions.ToVkPresentMode(mPresentMode);

		for (let mode in presentModes)
		{
			if (mode == preferredMode)
				return mode;
		}

		// FIFO is guaranteed to be available
		return .VK_PRESENT_MODE_FIFO_KHR;
	}

	private VkExtent2D ChooseExtent(VkSurfaceCapabilitiesKHR* capabilities)
	{
		if (capabilities.currentExtent.width != uint32.MaxValue)
			return capabilities.currentExtent;

		VkExtent2D extent = .()
			{
				width = Math.Clamp(mWidth, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
				height = Math.Clamp(mHeight, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)
			};

		return extent;
	}

	private VkImageUsageFlags GetVkImageUsage()
	{
		VkImageUsageFlags flags = .VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

		if (mUsage.HasFlag(.CopySrc))
			flags |= .VK_IMAGE_USAGE_TRANSFER_SRC_BIT;

		if (mUsage.HasFlag(.CopyDst))
			flags |= .VK_IMAGE_USAGE_TRANSFER_DST_BIT;

		if (mUsage.HasFlag(.Sampled))
			flags |= .VK_IMAGE_USAGE_SAMPLED_BIT;

		return flags;
	}
}
