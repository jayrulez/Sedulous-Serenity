namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of IBuffer.
class VulkanBuffer : IBuffer
{
	private VulkanDevice mDevice;
	private VkBuffer mBuffer;
	private VkDeviceMemory mMemory;
	private uint64 mSize;
	private BufferUsage mUsage;
	private MemoryAccess mMemoryAccess;
	private void* mMappedPtr;

	public this(VulkanDevice device, BufferDescriptor* descriptor)
	{
		mDevice = device;
		mSize = descriptor.Size;
		mUsage = descriptor.Usage;
		mMemoryAccess = descriptor.MemoryAccess;
		CreateBuffer(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mMappedPtr != null)
		{
			Unmap();
		}

		if (mBuffer != default)
		{
			VulkanNative.vkDestroyBuffer(mDevice.Device, mBuffer, null);
			mBuffer = default;
		}

		if (mMemory != default)
		{
			VulkanNative.vkFreeMemory(mDevice.Device, mMemory, null);
			mMemory = default;
		}
	}

	/// Returns true if the buffer was created successfully.
	public bool IsValid => mBuffer != default && mMemory != default;

	public uint64 Size => mSize;
	public BufferUsage Usage => mUsage;

	/// Gets the Vulkan buffer handle.
	public VkBuffer Buffer => mBuffer;

	/// Gets the Vulkan memory handle.
	public VkDeviceMemory Memory => mMemory;

	public void* Map()
	{
		if (mMappedPtr != null)
			return mMappedPtr;

		// Can only map host-visible memory
		if (mMemoryAccess == .GpuOnly)
			return null;

		void* data = null;
		if (VulkanNative.vkMapMemory(mDevice.Device, mMemory, 0, mSize, 0, &data) == .VK_SUCCESS)
		{
			mMappedPtr = data;
			return data;
		}

		return null;
	}

	public void Unmap()
	{
		if (mMappedPtr != null)
		{
			VulkanNative.vkUnmapMemory(mDevice.Device, mMemory);
			mMappedPtr = null;
		}
	}

	private void CreateBuffer(BufferDescriptor* descriptor)
	{
		// Create buffer
		VkBufferCreateInfo bufferInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
				size = descriptor.Size,
				usage = VulkanConversions.ToVkBufferUsage(descriptor.Usage),
				sharingMode = .VK_SHARING_MODE_EXCLUSIVE
			};

		if (VulkanNative.vkCreateBuffer(mDevice.Device, &bufferInfo, null, &mBuffer) != .VK_SUCCESS)
			return;

		// Get memory requirements
		VkMemoryRequirements memRequirements = .();
		VulkanNative.vkGetBufferMemoryRequirements(mDevice.Device, mBuffer, &memRequirements);

		// Find suitable memory type
		VkMemoryPropertyFlags requiredProps = VulkanConversions.ToVkMemoryProperties(descriptor.MemoryAccess);
		uint32 memoryTypeIndex = FindMemoryType(memRequirements.memoryTypeBits, requiredProps);

		if (memoryTypeIndex == uint32.MaxValue)
		{
			VulkanNative.vkDestroyBuffer(mDevice.Device, mBuffer, null);
			mBuffer = default;
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
			VulkanNative.vkDestroyBuffer(mDevice.Device, mBuffer, null);
			mBuffer = default;
			return;
		}

		// Bind buffer to memory
		if (VulkanNative.vkBindBufferMemory(mDevice.Device, mBuffer, mMemory, 0) != .VK_SUCCESS)
		{
			VulkanNative.vkFreeMemory(mDevice.Device, mMemory, null);
			VulkanNative.vkDestroyBuffer(mDevice.Device, mBuffer, null);
			mBuffer = default;
			mMemory = default;
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
