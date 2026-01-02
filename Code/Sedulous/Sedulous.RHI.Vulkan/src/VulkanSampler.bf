namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of ISampler.
class VulkanSampler : ISampler
{
	private VulkanDevice mDevice;
	private VkSampler mSampler;

	public this(VulkanDevice device, SamplerDescriptor* descriptor)
	{
		mDevice = device;
		CreateSampler(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mSampler != default)
		{
			VulkanNative.vkDestroySampler(mDevice.Device, mSampler, null);
			mSampler = default;
		}
	}

	/// Returns true if the sampler was created successfully.
	public bool IsValid => mSampler != default;

	/// Gets the Vulkan sampler handle.
	public VkSampler Sampler => mSampler;

	private void CreateSampler(SamplerDescriptor* descriptor)
	{
		VkSamplerCreateInfo samplerInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
				magFilter = VulkanConversions.ToVkFilter(descriptor.MagFilter),
				minFilter = VulkanConversions.ToVkFilter(descriptor.MinFilter),
				mipmapMode = VulkanConversions.ToVkSamplerMipmapMode(descriptor.MipmapFilter),
				addressModeU = VulkanConversions.ToVkSamplerAddressMode(descriptor.AddressModeU),
				addressModeV = VulkanConversions.ToVkSamplerAddressMode(descriptor.AddressModeV),
				addressModeW = VulkanConversions.ToVkSamplerAddressMode(descriptor.AddressModeW),
				mipLodBias = 0.0f,
				anisotropyEnable = descriptor.MaxAnisotropy > 1 ? VkBool32.True : VkBool32.False,
				maxAnisotropy = (float)descriptor.MaxAnisotropy,
				compareEnable = descriptor.Compare != .Always ? VkBool32.True : VkBool32.False,
				compareOp = VulkanConversions.ToVkCompareOp(descriptor.Compare),
				minLod = descriptor.LodMinClamp,
				maxLod = descriptor.LodMaxClamp,
				borderColor = .VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK,
				unnormalizedCoordinates = VkBool32.False
			};

		VulkanNative.vkCreateSampler(mDevice.Device, &samplerInfo, null, &mSampler);
	}
}
