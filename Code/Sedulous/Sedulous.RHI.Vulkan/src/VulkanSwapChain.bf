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
	private VkSemaphore mImageAvailableSemaphore;
	private VkSemaphore mRenderFinishedSemaphore;

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

		if (mImageAvailableSemaphore != default)
		{
			VulkanNative.vkDestroySemaphore(mDevice.Device, mImageAvailableSemaphore, null);
			mImageAvailableSemaphore = default;
		}

		if (mRenderFinishedSemaphore != default)
		{
			VulkanNative.vkDestroySemaphore(mDevice.Device, mRenderFinishedSemaphore, null);
			mRenderFinishedSemaphore = default;
		}
	}

	public TextureFormat Format => mFormat;
	public uint32 Width => mWidth;
	public uint32 Height => mHeight;

	public ITexture CurrentTexture => mTextures.Count > 0 ? mTextures[mCurrentImageIndex] : null;
	public ITextureView CurrentTextureView => mTextureViews.Count > 0 ? mTextureViews[mCurrentImageIndex] : null;

	/// Gets the Vulkan swapchain handle.
	public VkSwapchainKHR SwapChain => mSwapChain;

	/// Gets the image available semaphore for synchronization.
	public VkSemaphore ImageAvailableSemaphore => mImageAvailableSemaphore;

	/// Gets the render finished semaphore for synchronization.
	public VkSemaphore RenderFinishedSemaphore => mRenderFinishedSemaphore;

	/// Gets the current image index.
	public uint32 CurrentImageIndex => mCurrentImageIndex;

	public Result<void> AcquireNextImage()
	{
		var result = VulkanNative.vkAcquireNextImageKHR(
			mDevice.Device,
			mSwapChain,
			uint64.MaxValue,
			mImageAvailableSemaphore,
			default,
			&mCurrentImageIndex
		);

		if (result == .VK_ERROR_OUT_OF_DATE_KHR)
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
		VkSemaphore[1] waitSemaphores = .(mRenderFinishedSemaphore);
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

		if (!CreateSwapChain())
			return .Err;

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
			// Create texture wrapper (doesn't own the image)
			let texture = new VulkanTexture(mDevice, image, mFormat, mWidth, mHeight, .RenderTarget);
			mTextures.Add(texture);

			// Create texture view
			TextureViewDescriptor viewDesc = .()
				{
					Format = mFormat,
					Dimension = .Texture2D,
					BaseMipLevel = 0,
					MipLevelCount = 1,
					BaseArrayLayer = 0,
					ArrayLayerCount = 1
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

		VulkanNative.vkCreateSemaphore(mDevice.Device, &semaphoreInfo, null, &mImageAvailableSemaphore);
		VulkanNative.vkCreateSemaphore(mDevice.Device, &semaphoreInfo, null, &mRenderFinishedSemaphore);
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
