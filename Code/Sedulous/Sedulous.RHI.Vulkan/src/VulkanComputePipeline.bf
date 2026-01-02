namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;

/// Vulkan implementation of IComputePipeline.
class VulkanComputePipeline : IComputePipeline
{
	private VulkanDevice mDevice;
	private VulkanPipelineLayout mLayout;
	private VkPipeline mPipeline;

	public this(VulkanDevice device, ComputePipelineDescriptor* descriptor)
	{
		mDevice = device;
		mLayout = descriptor.Layout as VulkanPipelineLayout;
		CreatePipeline(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mPipeline != default)
		{
			VulkanNative.vkDestroyPipeline(mDevice.Device, mPipeline, null);
			mPipeline = default;
		}
	}

	/// Returns true if the pipeline was created successfully.
	public bool IsValid => mPipeline != default;

	public IPipelineLayout Layout => mLayout;

	/// Gets the Vulkan pipeline handle.
	public VkPipeline Pipeline => mPipeline;

	private void CreatePipeline(ComputePipelineDescriptor* descriptor)
	{
		if (mLayout == null || !mLayout.IsValid)
			return;

		if (descriptor.Compute.Module == null)
			return;

		let vkModule = descriptor.Compute.Module as VulkanShaderModule;
		if (vkModule == null || !vkModule.IsValid)
			return;

		String entryPoint = scope .(descriptor.Compute.EntryPoint);

		VkPipelineShaderStageCreateInfo shaderStage = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
				stage = .VK_SHADER_STAGE_COMPUTE_BIT,
				module = vkModule.ShaderModule,
				pName = entryPoint.CStr()
			};

		VkComputePipelineCreateInfo pipelineInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
				stage = shaderStage,
				layout = mLayout.PipelineLayout,
				basePipelineHandle = default,
				basePipelineIndex = -1
			};

		VulkanNative.vkCreateComputePipelines(mDevice.Device, default, 1, &pipelineInfo, null, &mPipeline);
	}
}
