namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of IBindGroup.
class VulkanBindGroup : IBindGroup
{
	private VulkanDevice mDevice;
	private VulkanBindGroupLayout mLayout;
	private VkDescriptorSet mDescriptorSet;
	private VulkanDescriptorPool mPool;

	public this(VulkanDevice device, VulkanDescriptorPool pool, BindGroupDescriptor* descriptor)
	{
		mDevice = device;
		mPool = pool;
		mLayout = descriptor.Layout as VulkanBindGroupLayout;
		CreateDescriptorSet(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mDescriptorSet != default && mPool != null)
		{
			mPool.FreeDescriptorSet(mDescriptorSet);
			mDescriptorSet = default;
		}
	}

	/// Returns true if the bind group was created successfully.
	public bool IsValid => mDescriptorSet != default;

	public IBindGroupLayout Layout => mLayout;

	/// Gets the Vulkan descriptor set handle.
	public VkDescriptorSet DescriptorSet => mDescriptorSet;

	private void CreateDescriptorSet(BindGroupDescriptor* descriptor)
	{
		if (mLayout == null || !mLayout.IsValid)
			return;

		// Allocate descriptor set
		let result = mPool.AllocateDescriptorSet(mLayout.DescriptorSetLayout);
		if (result case .Err)
			return;
		mDescriptorSet = result.Get();

		// Update descriptor set with resource bindings
		if (descriptor.Entries.Length == 0)
			return;

		List<VkWriteDescriptorSet> writes = scope .();
		List<VkDescriptorBufferInfo> bufferInfos = scope .();
		List<VkDescriptorImageInfo> imageInfos = scope .();

		// Pre-allocate to avoid reallocation invalidating pointers
		bufferInfos.Reserve(descriptor.Entries.Length);
		imageInfos.Reserve(descriptor.Entries.Length);

		for (let entry in descriptor.Entries)
		{
			// Find matching layout entry
			BindGroupLayoutEntry* layoutEntry = null;
			for (var le in ref mLayout.Entries)
			{
				if (le.Binding == entry.Binding)
				{
					layoutEntry = &le;
					break;
				}
			}

			if (layoutEntry == null)
				continue;

			VkWriteDescriptorSet write = .()
				{
					sType = .VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
					dstSet = mDescriptorSet,
					dstBinding = entry.Binding,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = VulkanConversions.ToVkDescriptorType(layoutEntry.Type)
				};

			switch (layoutEntry.Type)
			{
			case .UniformBuffer, .StorageBuffer, .StorageBufferReadWrite:
				if (entry.Buffer != null)
				{
					let vkBuffer = entry.Buffer as VulkanBuffer;
					if (vkBuffer != null)
					{
						bufferInfos.Add(.()
							{
								buffer = vkBuffer.Buffer,
								offset = entry.BufferOffset,
								range = entry.BufferSize > 0 ? entry.BufferSize : vkBuffer.Size - entry.BufferOffset
							});
						write.pBufferInfo = &bufferInfos[bufferInfos.Count - 1];
						writes.Add(write);
					}
				}

			case .SampledTexture, .StorageTexture, .StorageTextureReadWrite:
				if (entry.TextureView != null)
				{
					let vkView = entry.TextureView as VulkanTextureView;
					if (vkView != null)
					{
						imageInfos.Add(.()
							{
								imageView = vkView.ImageView,
								imageLayout = layoutEntry.Type == .SampledTexture ?
									.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL :
									.VK_IMAGE_LAYOUT_GENERAL,
								sampler = default
							});
						write.pImageInfo = &imageInfos[imageInfos.Count - 1];
						writes.Add(write);
					}
				}

			case .Sampler, .ComparisonSampler:
				if (entry.Sampler != null)
				{
					let vkSampler = entry.Sampler as VulkanSampler;
					if (vkSampler != null)
					{
						imageInfos.Add(.()
							{
								imageView = default,
								imageLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
								sampler = vkSampler.Sampler
							});
						write.pImageInfo = &imageInfos[imageInfos.Count - 1];
						writes.Add(write);
					}
				}

			default:
				break;
			}
		}

		if (writes.Count > 0)
		{
			VulkanNative.vkUpdateDescriptorSets(mDevice.Device, (uint32)writes.Count, writes.Ptr, 0, null);
		}
	}
}
