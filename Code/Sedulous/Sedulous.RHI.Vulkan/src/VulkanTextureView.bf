namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of ITextureView.
class VulkanTextureView : ITextureView
{
	private VulkanDevice mDevice;
	private VulkanTexture mTexture;
	private VkImageView mImageView;
	private TextureViewDimension mDimension;
	private TextureFormat mFormat;
	private uint32 mBaseMipLevel;
	private uint32 mMipLevelCount;
	private uint32 mBaseArrayLayer;
	private uint32 mArrayLayerCount;
	private String mDebugName ~ delete _;

	public this(VulkanDevice device, VulkanTexture texture, TextureViewDescriptor* descriptor)
	{
		mDevice = device;
		mTexture = texture;
		mDimension = descriptor.Dimension;
		mFormat = descriptor.Format;
		mBaseMipLevel = descriptor.BaseMipLevel;
		mMipLevelCount = descriptor.MipLevelCount;
		mBaseArrayLayer = descriptor.BaseArrayLayer;
		mArrayLayerCount = descriptor.ArrayLayerCount;
		if (descriptor.Label.Ptr != null && descriptor.Label.Length > 0)
			mDebugName = new String(descriptor.Label);
		else
			Runtime.FatalError();
		CreateImageView(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mImageView != default)
		{
			VulkanNative.vkDestroyImageView(mDevice.Device, mImageView, null);
			mImageView = default;
		}
	}

	/// Returns true if the view was created successfully.
	public bool IsValid => mImageView != default;

	public StringView DebugName => mDebugName != null ? mDebugName : "";
	public ITexture Texture => mTexture;
	public TextureViewDimension Dimension => mDimension;
	public TextureFormat Format => mFormat;
	public uint32 BaseMipLevel => mBaseMipLevel;
	public uint32 MipLevelCount => mMipLevelCount;
	public uint32 BaseArrayLayer => mBaseArrayLayer;
	public uint32 ArrayLayerCount => mArrayLayerCount;

	/// Gets the Vulkan image view handle.
	public VkImageView ImageView => mImageView;

	private void CreateImageView(TextureViewDescriptor* descriptor)
	{
		VkImageViewCreateInfo viewInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
				image = mTexture.Image,
				viewType = VulkanConversions.ToVkImageViewType(descriptor.Dimension),
				format = VulkanConversions.ToVkFormat(descriptor.Format),
				components = .()
				{
					r = .VK_COMPONENT_SWIZZLE_IDENTITY,
					g = .VK_COMPONENT_SWIZZLE_IDENTITY,
					b = .VK_COMPONENT_SWIZZLE_IDENTITY,
					a = .VK_COMPONENT_SWIZZLE_IDENTITY
				},
				subresourceRange = .()
				{
					// Use explicit aspect selection for depth/stencil sampled views
					aspectMask = VulkanConversions.GetAspectFlags(descriptor.Format, descriptor.Aspect),
					baseMipLevel = descriptor.BaseMipLevel,
					levelCount = descriptor.MipLevelCount,
					baseArrayLayer = descriptor.BaseArrayLayer,
					layerCount = descriptor.ArrayLayerCount
				}
			};

		VulkanNative.vkCreateImageView(mDevice.Device, &viewInfo, null, &mImageView);
	}
}
