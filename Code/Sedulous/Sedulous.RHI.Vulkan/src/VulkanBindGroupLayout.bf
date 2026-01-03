namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of IBindGroupLayout.
class VulkanBindGroupLayout : IBindGroupLayout
{
	private VulkanDevice mDevice;
	private VkDescriptorSetLayout mDescriptorSetLayout;
	private List<BindGroupLayoutEntry> mEntries = new .() ~ delete _;

	public this(VulkanDevice device, BindGroupLayoutDescriptor* descriptor)
	{
		mDevice = device;
		mDescriptorSetLayout = default;  // Explicitly initialize before Vulkan call
		// Copy entries for later use when creating bind groups
		for (let entry in descriptor.Entries)
			mEntries.Add(entry);
		CreateDescriptorSetLayout(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mDescriptorSetLayout != default)
		{
			VulkanNative.vkDestroyDescriptorSetLayout(mDevice.Device, mDescriptorSetLayout, null);
			mDescriptorSetLayout = default;
		}
	}

	/// Returns true if the layout was created successfully.
	public bool IsValid => mDescriptorSetLayout != default;

	/// Gets the Vulkan descriptor set layout handle.
	public VkDescriptorSetLayout DescriptorSetLayout => mDescriptorSetLayout;

	/// Gets the layout entries.
	public Span<BindGroupLayoutEntry> Entries => mEntries;

	private void CreateDescriptorSetLayout(BindGroupLayoutDescriptor* descriptor)
	{
		if (descriptor.Entries.Length == 0)
		{
			// Create empty descriptor set layout
			VkDescriptorSetLayoutCreateInfo layoutInfo = .()
				{
					sType = .VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
					bindingCount = 0,
					pBindings = null
				};

			let result = VulkanNative.vkCreateDescriptorSetLayout(mDevice.Device, &layoutInfo, null, &mDescriptorSetLayout);
			if (result != .VK_SUCCESS)
			{
				mDescriptorSetLayout = default;
			}
			return;
		}

		// Convert to Vulkan bindings with automatic shift based on resource type
		// This matches the shifts applied during shader compilation via DXC's -fvk-*-shift flags
		VkDescriptorSetLayoutBinding* bindings = scope VkDescriptorSetLayoutBinding[descriptor.Entries.Length]*;

		for (int i = 0; i < descriptor.Entries.Length; i++)
		{
			let entry = descriptor.Entries[i];
			// Apply the binding shift based on resource type to match shader compilation
			uint32 shiftedBinding = entry.Binding + VulkanBindingShifts.GetShift(entry.Type);

			bindings[i] = .()
				{
					binding = shiftedBinding,
					descriptorType = VulkanConversions.ToVkDescriptorType(entry.Type),
					descriptorCount = 1,
					stageFlags = VulkanConversions.ToVkShaderStage(entry.Visibility),
					pImmutableSamplers = null
				};
		}

		VkDescriptorSetLayoutCreateInfo layoutInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
				bindingCount = (uint32)descriptor.Entries.Length,
				pBindings = bindings
			};

		let result = VulkanNative.vkCreateDescriptorSetLayout(mDevice.Device, &layoutInfo, null, &mDescriptorSetLayout);
		if (result != .VK_SUCCESS)
		{
			mDescriptorSetLayout = default;
		}
	}
}
