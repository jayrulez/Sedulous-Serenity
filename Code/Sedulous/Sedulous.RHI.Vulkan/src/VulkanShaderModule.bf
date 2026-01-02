namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;

/// Vulkan implementation of IShaderModule.
class VulkanShaderModule : IShaderModule
{
	private VulkanDevice mDevice;
	private VkShaderModule mShaderModule;

	public this(VulkanDevice device, ShaderModuleDescriptor* descriptor)
	{
		mDevice = device;
		CreateShaderModule(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mShaderModule != default)
		{
			VulkanNative.vkDestroyShaderModule(mDevice.Device, mShaderModule, null);
			mShaderModule = default;
		}
	}

	/// Returns true if the shader module was created successfully.
	public bool IsValid => mShaderModule != default;

	/// Gets the Vulkan shader module handle.
	public VkShaderModule ShaderModule => mShaderModule;

	private void CreateShaderModule(ShaderModuleDescriptor* descriptor)
	{
		if (descriptor.Code.Length == 0)
			return;

		// SPIRV code must be aligned to 4 bytes and size must be multiple of 4
		if (descriptor.Code.Length % 4 != 0)
			return;

		VkShaderModuleCreateInfo createInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
				codeSize = (uint)descriptor.Code.Length,
				pCode = (uint32*)descriptor.Code.Ptr
			};

		VulkanNative.vkCreateShaderModule(mDevice.Device, &createInfo, null, &mShaderModule);
	}
}
