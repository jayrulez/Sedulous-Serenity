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
		}
		mDescriptorSet = default;
	}

	/// Returns true if the bind group was created successfully.
	public bool IsValid => mDescriptorSet != default;

	public IBindGroupLayout Layout => mLayout;

	/// Gets the Vulkan descriptor set handle.
	public VkDescriptorSet DescriptorSet => mDescriptorSet;

	/// Checks if a layout entry type is compatible with a bind group entry.
	private static bool IsCompatibleType(BindingType layoutType, BindGroupEntry entry)
	{
		switch (layoutType)
		{
		case .UniformBuffer, .StorageBuffer, .StorageBufferReadWrite:
			return entry.Buffer != null;
		case .SampledTexture, .StorageTexture, .StorageTextureReadWrite:
			return entry.TextureView != null;
		case .Sampler, .ComparisonSampler:
			return entry.Sampler != null;
		}
	}

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

		// Track which layout entries have been matched to avoid double-matching
		bool* matchedLayouts = scope bool[mLayout.Entries.Length]*;
		for (int i = 0; i < mLayout.Entries.Length; i++)
			matchedLayouts[i] = false;

		for (let entry in descriptor.Entries)
		{
			// Find matching layout entry by binding AND resource type
			// Skip already-matched entries to handle multiple buffers with same binding but different types
			BindGroupLayoutEntry* layoutEntry = null;
			int matchedIndex = -1;
			for (int i = 0; i < mLayout.Entries.Length; i++)
			{
				if (matchedLayouts[i])
					continue;

				var le = ref mLayout.Entries[i];
				if (le.Binding == entry.Binding && IsCompatibleType(le.Type, entry))
				{
					layoutEntry = &le;
					matchedIndex = i;
					break;
				}
			}

			if (layoutEntry == null)
				continue;

			matchedLayouts[matchedIndex] = true;

			// Apply the binding shift to match the layout's shifted bindings
			uint32 shiftedBinding = entry.Binding + VulkanBindingShifts.GetShift(layoutEntry.Type);

			VkWriteDescriptorSet write = .()
				{
					sType = .VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
					dstSet = mDescriptorSet,
					dstBinding = shiftedBinding,
					dstArrayElement = 0,
					descriptorCount = 1,
					descriptorType = VulkanConversions.ToVkDescriptorType(layoutEntry.Type, layoutEntry.HasDynamicOffset)
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
