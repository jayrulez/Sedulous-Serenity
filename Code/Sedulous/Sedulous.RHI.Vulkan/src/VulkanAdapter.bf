namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;

/// Vulkan implementation of IAdapter.
class VulkanAdapter : IAdapter
{
	private VulkanBackend mBackend;
	private VkPhysicalDevice mPhysicalDevice;
	private AdapterInfo mInfo;

	public this(VulkanBackend backend, VkPhysicalDevice physicalDevice)
	{
		mBackend = backend;
		mPhysicalDevice = physicalDevice;
		QueryDeviceInfo();
	}

	public ~this()
	{
		mInfo.Dispose();
	}

	public AdapterInfo Info => mInfo;

	/// Gets the Vulkan physical device handle.
	public VkPhysicalDevice PhysicalDevice => mPhysicalDevice;

	/// Gets the backend this adapter belongs to.
	public VulkanBackend Backend => mBackend;

	public Result<IDevice> CreateDevice()
	{
		let device = new VulkanDevice(this);
		if (!device.IsInitialized)
		{
			delete device;
			return .Err;
		}
		return .Ok(device);
	}

	/// Finds queue family indices for graphics and present operations.
	public QueueFamilyIndices FindQueueFamilies(VkSurfaceKHR surface = default)
	{
		QueueFamilyIndices indices = default;

		uint32 queueFamilyCount = 0;
		VulkanNative.vkGetPhysicalDeviceQueueFamilyProperties(mPhysicalDevice, &queueFamilyCount, null);

		if (queueFamilyCount == 0)
			return indices;

		VkQueueFamilyProperties* queueFamilies = scope VkQueueFamilyProperties[(int)queueFamilyCount]*;
		VulkanNative.vkGetPhysicalDeviceQueueFamilyProperties(mPhysicalDevice, &queueFamilyCount, queueFamilies);

		for (uint32 i = 0; i < queueFamilyCount; i++)
		{
			let queueFamily = queueFamilies[i];

			// Check for graphics support
			if ((queueFamily.queueFlags & .VK_QUEUE_GRAPHICS_BIT) != 0)
			{
				indices.GraphicsFamily = i;
			}

			// Check for compute support
			if ((queueFamily.queueFlags & .VK_QUEUE_COMPUTE_BIT) != 0)
			{
				indices.ComputeFamily = i;
			}

			// Check for transfer support
			if ((queueFamily.queueFlags & .VK_QUEUE_TRANSFER_BIT) != 0)
			{
				indices.TransferFamily = i;
			}

			// Check for present support if surface provided
			if (surface != default)
			{
				VkBool32 presentSupport = false;
				VulkanNative.vkGetPhysicalDeviceSurfaceSupportKHR(mPhysicalDevice, i, surface, &presentSupport);
				if (presentSupport)
				{
					indices.PresentFamily = i;
				}
			}

			if (indices.IsComplete(surface != default))
				break;
		}

		return indices;
	}

	/// Checks if the required device extensions are supported.
	public bool CheckDeviceExtensionSupport(Span<char8*> requiredExtensions)
	{
		uint32 extensionCount = 0;
		VulkanNative.vkEnumerateDeviceExtensionProperties(mPhysicalDevice, null, &extensionCount, null);

		if (extensionCount == 0)
			return requiredExtensions.Length == 0;

		VkExtensionProperties* availableExtensions = scope VkExtensionProperties[(int)extensionCount]*;
		VulkanNative.vkEnumerateDeviceExtensionProperties(mPhysicalDevice, null, &extensionCount, availableExtensions);

		for (let required in requiredExtensions)
		{
			bool found = false;
			for (uint32 i = 0; i < extensionCount; i++)
			{
				if (String.Equals(required, &availableExtensions[i].extensionName))
				{
					found = true;
					break;
				}
			}
			if (!found)
				return false;
		}

		return true;
	}

	private void QueryDeviceInfo()
	{
		VkPhysicalDeviceProperties properties = .();
		VulkanNative.vkGetPhysicalDeviceProperties(mPhysicalDevice, &properties);

		mInfo = .();
		mInfo.Name.Set(StringView(&properties.deviceName));
		mInfo.VendorId = properties.vendorID;
		mInfo.DeviceId = properties.deviceID;

		switch (properties.deviceType)
		{
		case .VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:
			mInfo.Type = .Discrete;
		case .VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU:
			mInfo.Type = .Integrated;
		case .VK_PHYSICAL_DEVICE_TYPE_CPU:
			mInfo.Type = .Software;
		default:
			mInfo.Type = .Unknown;
		}
	}
}

/// Indices for different queue families.
struct QueueFamilyIndices
{
	public uint32? GraphicsFamily;
	public uint32? ComputeFamily;
	public uint32? TransferFamily;
	public uint32? PresentFamily;

	public bool HasGraphics => GraphicsFamily.HasValue;
	public bool HasCompute => ComputeFamily.HasValue;
	public bool HasTransfer => TransferFamily.HasValue;
	public bool HasPresent => PresentFamily.HasValue;

	public bool IsComplete(bool requirePresent)
	{
		if (!GraphicsFamily.HasValue)
			return false;
		if (requirePresent && !PresentFamily.HasValue)
			return false;
		return true;
	}
}
