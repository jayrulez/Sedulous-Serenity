namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of ITexture.
class VulkanTexture : ITexture
{
	private VulkanDevice mDevice;
	private VkImage mImage;
	private VkDeviceMemory mMemory;
	private TextureDimension mDimension;
	private TextureFormat mFormat;
	private uint32 mWidth;
	private uint32 mHeight;
	private uint32 mDepth;
	private uint32 mMipLevelCount;
	private uint32 mArrayLayerCount;
	private uint32 mSampleCount;
	private TextureUsage mUsage;
	private bool mOwnsImage;
	private bool mIsSwapChainTexture;
	private String mDebugName ~ delete _;

	/// Creates a texture from a descriptor.
	public this(VulkanDevice device, TextureDescriptor* descriptor)
	{
		mDevice = device;
		mDimension = descriptor.Dimension;
		mFormat = descriptor.Format;
		mWidth = descriptor.Width;
		mHeight = descriptor.Height;
		mDepth = descriptor.Depth;
		mMipLevelCount = descriptor.MipLevelCount;
		mArrayLayerCount = descriptor.ArrayLayerCount;
		mSampleCount = descriptor.SampleCount;
		mUsage = descriptor.Usage;
		mOwnsImage = true;
		if (descriptor.Label.Ptr != null && descriptor.Label.Length > 0)
			mDebugName = new String(descriptor.Label);
		else
			Runtime.FatalError();
		CreateImage(descriptor);
	}

	/// Creates a texture wrapper around an existing VkImage (e.g., from swap chain).
	public this(VulkanDevice device, VkImage image, TextureFormat format, uint32 width, uint32 height, TextureUsage usage, bool isSwapChainTexture = false)
	{
		mDevice = device;
		mImage = image;
		mDimension = .Texture2D;
		mFormat = format;
		mWidth = width;
		mHeight = height;
		mDepth = 1;
		mMipLevelCount = 1;
		mArrayLayerCount = 1;
		mSampleCount = 1;
		mUsage = usage;
		mOwnsImage = false;  // Don't destroy, swap chain owns it
		mIsSwapChainTexture = isSwapChainTexture;
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mOwnsImage)
		{
			if (mImage != default)
			{
				VulkanNative.vkDestroyImage(mDevice.Device, mImage, null);
				mImage = default;
			}

			if (mMemory != default)
			{
				VulkanNative.vkFreeMemory(mDevice.Device, mMemory, null);
				mMemory = default;
			}
		}
	}

	/// Returns true if the texture was created successfully.
	public bool IsValid => mImage != default;

	public StringView DebugName => mDebugName != null ? mDebugName : "";
	public TextureDimension Dimension => mDimension;
	public TextureFormat Format => mFormat;
	public uint32 Width => mWidth;
	public uint32 Height => mHeight;
	public uint32 Depth => mDepth;
	public uint32 MipLevelCount => mMipLevelCount;
	public uint32 ArrayLayerCount => mArrayLayerCount;
	public uint32 SampleCount => mSampleCount;
	public TextureUsage Usage => mUsage;

	/// Gets the Vulkan image handle.
	public VkImage Image => mImage;

	/// Gets the Vulkan memory handle.
	public VkDeviceMemory Memory => mMemory;

	/// Returns true if this is a swap chain texture that needs PRESENT_SRC_KHR layout.
	public bool IsSwapChainTexture => mIsSwapChainTexture;

	private void CreateImage(TextureDescriptor* descriptor)
	{
		// Determine image flags
		VkImageCreateFlags flags = 0;
		// Set cube compatible for single cubemaps (6 layers) and cubemap arrays (multiples of 6)
		if (descriptor.ArrayLayerCount >= 6 && descriptor.ArrayLayerCount % 6 == 0)
			flags |= .VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;

		// Create image
		VkImageCreateInfo imageInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
				flags = flags,
				imageType = VulkanConversions.ToVkImageType(descriptor.Dimension),
				format = VulkanConversions.ToVkFormat(descriptor.Format),
				extent = .()
				{
					width = descriptor.Width,
					height = descriptor.Height,
					depth = descriptor.Depth
				},
				mipLevels = descriptor.MipLevelCount,
				arrayLayers = descriptor.ArrayLayerCount,
				samples = GetSampleCount(descriptor.SampleCount),
				tiling = .VK_IMAGE_TILING_OPTIMAL,
				usage = VulkanConversions.ToVkImageUsage(descriptor.Usage),
				sharingMode = .VK_SHARING_MODE_EXCLUSIVE,
				initialLayout = .VK_IMAGE_LAYOUT_UNDEFINED
			};

		if (VulkanNative.vkCreateImage(mDevice.Device, &imageInfo, null, &mImage) != .VK_SUCCESS)
			return;

		// Get memory requirements
		VkMemoryRequirements memRequirements = .();
		VulkanNative.vkGetImageMemoryRequirements(mDevice.Device, mImage, &memRequirements);

		// Find suitable memory type (always device local for textures)
		uint32 memoryTypeIndex = FindMemoryType(memRequirements.memoryTypeBits, .VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

		if (memoryTypeIndex == uint32.MaxValue)
		{
			VulkanNative.vkDestroyImage(mDevice.Device, mImage, null);
			mImage = default;
			return;
		}

		// Allocate memory
		VkMemoryAllocateInfo allocInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
				allocationSize = memRequirements.size,
				memoryTypeIndex = memoryTypeIndex
			};

		if (VulkanNative.vkAllocateMemory(mDevice.Device, &allocInfo, null, &mMemory) != .VK_SUCCESS)
		{
			VulkanNative.vkDestroyImage(mDevice.Device, mImage, null);
			mImage = default;
			return;
		}

		// Bind image to memory
		if (VulkanNative.vkBindImageMemory(mDevice.Device, mImage, mMemory, 0) != .VK_SUCCESS)
		{
			VulkanNative.vkFreeMemory(mDevice.Device, mMemory, null);
			VulkanNative.vkDestroyImage(mDevice.Device, mImage, null);
			mImage = default;
			mMemory = default;
		}
	}

	private VkSampleCountFlags GetSampleCount(uint32 count)
	{
		switch (count)
		{
		case 1: return .VK_SAMPLE_COUNT_1_BIT;
		case 2: return .VK_SAMPLE_COUNT_2_BIT;
		case 4: return .VK_SAMPLE_COUNT_4_BIT;
		case 8: return .VK_SAMPLE_COUNT_8_BIT;
		case 16: return .VK_SAMPLE_COUNT_16_BIT;
		case 32: return .VK_SAMPLE_COUNT_32_BIT;
		case 64: return .VK_SAMPLE_COUNT_64_BIT;
		default: return .VK_SAMPLE_COUNT_1_BIT;
		}
	}

	private uint32 FindMemoryType(uint32 typeFilter, VkMemoryPropertyFlags properties)
	{
		VkPhysicalDeviceMemoryProperties memProperties = .();
		VulkanNative.vkGetPhysicalDeviceMemoryProperties(mDevice.[Friend]mAdapter.PhysicalDevice, &memProperties);

		for (uint32 i = 0; i < memProperties.memoryTypeCount; i++)
		{
			if ((typeFilter & (1 << i)) != 0 && (memProperties.memoryTypes[i].propertyFlags & properties) == properties)
			{
				return i;
			}
		}

		return uint32.MaxValue;
	}
}
