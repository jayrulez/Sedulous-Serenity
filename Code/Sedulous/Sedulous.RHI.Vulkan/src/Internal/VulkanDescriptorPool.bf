namespace Sedulous.RHI.Vulkan.Internal;

using System;
using Bulkan;

/// Manages Vulkan descriptor pool for allocating descriptor sets.
class VulkanDescriptorPool
{
	private VulkanDevice mDevice;
	private VkDescriptorPool mDescriptorPool;
	private uint32 mMaxSets;

	/// Default pool sizes for each descriptor type.
	private static uint32 sDefaultUniformBuffers = 1000;
	private static uint32 sDefaultStorageBuffers = 1000;
	private static uint32 sDefaultSampledImages = 1000;
	private static uint32 sDefaultStorageImages = 500;
	private static uint32 sDefaultSamplers = 1000;
	private static uint32 sDefaultCombinedImageSamplers = 1000;
	private static uint32 sDefaultMaxSets = 1000;

	public this(VulkanDevice device, uint32 maxSets = 0)
	{
		mDevice = device;
		mMaxSets = maxSets > 0 ? maxSets : sDefaultMaxSets;
		CreateDescriptorPool();
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mDescriptorPool != default)
		{
			VulkanNative.vkDestroyDescriptorPool(mDevice.Device, mDescriptorPool, null);
			mDescriptorPool = default;
		}
	}

	/// Returns true if the pool was created successfully.
	public bool IsValid => mDescriptorPool != default;

	/// Gets the Vulkan descriptor pool handle.
	public VkDescriptorPool DescriptorPool => mDescriptorPool;

	/// Allocates a descriptor set from the pool.
	public Result<VkDescriptorSet> AllocateDescriptorSet(VkDescriptorSetLayout layout)
	{
		var layout;
		VkDescriptorSetAllocateInfo allocInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
				descriptorPool = mDescriptorPool,
				descriptorSetCount = 1,
				pSetLayouts = &layout
			};

		VkDescriptorSet descriptorSet = default;
		if (VulkanNative.vkAllocateDescriptorSets(mDevice.Device, &allocInfo, &descriptorSet) != .VK_SUCCESS)
			return .Err;

		return .Ok(descriptorSet);
	}

	/// Frees a descriptor set back to the pool.
	public void FreeDescriptorSet(VkDescriptorSet descriptorSet)
	{
		var descriptorSet;
		VulkanNative.vkFreeDescriptorSets(mDevice.Device, mDescriptorPool, 1, &descriptorSet);
	}

	/// Resets the entire pool, freeing all descriptor sets.
	public void Reset()
	{
		VulkanNative.vkResetDescriptorPool(mDevice.Device, mDescriptorPool, 0);
	}

	private void CreateDescriptorPool()
	{
		VkDescriptorPoolSize[7] poolSizes = .(
			.() { type = .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount = sDefaultUniformBuffers },
			.() { type = .VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, descriptorCount = sDefaultStorageBuffers },
			.() { type = .VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, descriptorCount = sDefaultSampledImages },
			.() { type = .VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, descriptorCount = sDefaultStorageImages },
			.() { type = .VK_DESCRIPTOR_TYPE_SAMPLER, descriptorCount = sDefaultSamplers },
			.() { type = .VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount = sDefaultCombinedImageSamplers },
			.() { type = .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, descriptorCount = sDefaultUniformBuffers }
		);

		VkDescriptorPoolCreateInfo poolInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
				flags = .VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
				maxSets = mMaxSets,
				poolSizeCount = poolSizes.Count,
				pPoolSizes = &poolSizes
			};

		VulkanNative.vkCreateDescriptorPool(mDevice.Device, &poolInfo, null, &mDescriptorPool);
	}
}
