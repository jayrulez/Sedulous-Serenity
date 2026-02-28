namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;

/// Vulkan implementation of ISurface.
class VulkanSurface : ISurface
{
	private VkInstance mInstance;
	private VkSurfaceKHR mSurface;

	public this(VkInstance instance, VkSurfaceKHR surface)
	{
		mInstance = instance;
		mSurface = surface;
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mSurface != default && mInstance != default)
		{
			VulkanNative.vkDestroySurfaceKHR(mInstance, mSurface, null);
			mSurface = default;
		}
	}

	/// Gets the Vulkan surface handle.
	public VkSurfaceKHR Surface => mSurface;
}
