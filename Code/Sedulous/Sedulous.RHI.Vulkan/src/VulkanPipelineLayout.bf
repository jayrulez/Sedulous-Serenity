namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;

/// Vulkan implementation of IPipelineLayout.
class VulkanPipelineLayout : IPipelineLayout
{
	private VulkanDevice mDevice;
	private VkPipelineLayout mPipelineLayout;
	private List<VulkanBindGroupLayout> mBindGroupLayouts = new .() ~ delete _;

	public this(VulkanDevice device, PipelineLayoutDescriptor* descriptor)
	{
		mDevice = device;
		CreatePipelineLayout(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mPipelineLayout != default)
		{
			VulkanNative.vkDestroyPipelineLayout(mDevice.Device, mPipelineLayout, null);
			mPipelineLayout = default;
		}
		mBindGroupLayouts.Clear();
	}

	/// Returns true if the layout was created successfully.
	public bool IsValid => mPipelineLayout != default;

	/// Gets the Vulkan pipeline layout handle.
	public VkPipelineLayout PipelineLayout => mPipelineLayout;

	/// Gets the bind group layouts.
	public Span<VulkanBindGroupLayout> BindGroupLayouts => mBindGroupLayouts;

	private void CreatePipelineLayout(PipelineLayoutDescriptor* descriptor)
	{
		// Collect descriptor set layouts
		VkDescriptorSetLayout* setLayouts = null;
		int layoutCount = descriptor.BindGroupLayouts.Length;

		if (layoutCount > 0)
		{
			setLayouts = scope VkDescriptorSetLayout[layoutCount]*;
			for (int i = 0; i < layoutCount; i++)
			{
				if (let vkLayout = descriptor.BindGroupLayouts[i] as VulkanBindGroupLayout)
				{
					setLayouts[i] = vkLayout.DescriptorSetLayout;
					mBindGroupLayouts.Add(vkLayout);
				}
				else
				{
					// Invalid layout type
					return;
				}
			}
		}

		VkPipelineLayoutCreateInfo pipelineLayoutInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
				setLayoutCount = (uint32)layoutCount,
				pSetLayouts = setLayouts,
				pushConstantRangeCount = 0,
				pPushConstantRanges = null
			};

		VulkanNative.vkCreatePipelineLayout(mDevice.Device, &pipelineLayoutInfo, null, &mPipelineLayout);
	}
}
