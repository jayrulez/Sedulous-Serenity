namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;

/// Vulkan implementation of IBackend.
class VulkanBackend : IBackend
{
	private VkInstance mInstance;
	private VkDebugUtilsMessengerEXT mDebugMessenger;
	private bool mValidationEnabled;
	private List<VulkanAdapter> mAdapters = new .() ~ DeleteContainerAndItems!(_);

	private static char8*[?] sValidationLayers = .("VK_LAYER_KHRONOS_validation");

	// Debug callback delegate type
	typealias DebugCallbackDelegate = function VkBool32(
		VkDebugUtilsMessageSeverityFlagsEXT messageSeverity,
		VkDebugUtilsMessageTypeFlagsEXT messageType,
		VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
		void* pUserData);

	private static DebugCallbackDelegate sDebugCallbackDelegate = => DebugCallback;

	private static char8*[?] sInstanceExtensions = .(
		"VK_KHR_surface",
#if BF_PLATFORM_WINDOWS
		"VK_KHR_win32_surface",
#endif
#if BF_PLATFORM_LINUX
		"VK_KHR_xlib_surface",
#endif
		"VK_EXT_debug_utils"
	);

	/// Creates a new Vulkan backend.
	public this(bool enableValidation = true)
	{
		mValidationEnabled = enableValidation;
		CreateInstance();
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		// Clean up adapters
		for (let adapter in mAdapters)
			delete adapter;
		mAdapters.Clear();

		// Destroy debug messenger
		if (mDebugMessenger != default && mValidationEnabled)
		{
			VulkanNative.vkDestroyDebugUtilsMessengerEXT(mInstance, mDebugMessenger, null);
			mDebugMessenger = default;
		}

		// Destroy instance
		if (mInstance != default)
		{
			VulkanNative.vkDestroyInstance(mInstance, null);
			mInstance = default;
		}
	}

	/// Returns true if the backend initialized successfully.
	public bool IsInitialized => mInstance != default;

	public void EnumerateAdapters(List<IAdapter> adapters)
	{
		// Enumerate physical devices if not already done
		if (mAdapters.Count == 0)
		{
			EnumeratePhysicalDevices();
		}

		for (let adapter in mAdapters)
		{
			adapters.Add(adapter);
		}
	}

	public Result<ISurface> CreateSurface(void* windowHandle, void* displayHandle = null)
	{
		if (mInstance == default)
			return .Err;

#if BF_PLATFORM_WINDOWS
		VkWin32SurfaceCreateInfoKHR createInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
				hwnd = windowHandle,
				hinstance = (void*)(int)System.Windows.GetModuleHandleA(null)
			};

		VkSurfaceKHR surface = default;
		if (VulkanNative.vkCreateWin32SurfaceKHR(mInstance, &createInfo, null, &surface) != .VK_SUCCESS)
			return .Err;

		return .Ok(new VulkanSurface(mInstance, surface));
#elif BF_PLATFORM_LINUX
		VkXlibSurfaceCreateInfoKHR createInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
				dpy = displayHandle,
				window = (uint)(int)windowHandle
			};

		VkSurfaceKHR surface = default;
		if (VulkanNative.vkCreateXlibSurfaceKHR(mInstance, &createInfo, null, &surface) != .VK_SUCCESS)
			return .Err;

		return .Ok(new VulkanSurface(mInstance, surface));
#else
		return .Err;
#endif
	}

	/// Gets the Vulkan instance handle.
	public VkInstance Instance => mInstance;

	private void CreateInstance()
	{
		// Initialize Vulkan loader
		VulkanNative.Initialize();
		VulkanNative.LoadPreInstanceFunctions();

		// Application info
		VkApplicationInfo appInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_APPLICATION_INFO,
				pApplicationName = "Sedulous Application",
				applicationVersion = VK_MAKE_VERSION!(1, 0, 0),
				pEngineName = "Sedulous Engine",
				engineVersion = VK_MAKE_VERSION!(1, 0, 0),
				apiVersion = VK_MAKE_VERSION!(1, 2, 0)
			};

		// Create instance
		VkInstanceCreateInfo createInfo = .();
		createInfo.sType = .VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
		createInfo.pApplicationInfo = &appInfo;
		createInfo.enabledExtensionCount = (uint32)sInstanceExtensions.Count;
		createInfo.ppEnabledExtensionNames = &sInstanceExtensions;

		// Enable validation layers in debug
		if (mValidationEnabled && CheckValidationLayerSupport())
		{
			createInfo.enabledLayerCount = (uint32)sValidationLayers.Count;
			createInfo.ppEnabledLayerNames = &sValidationLayers;
		}
		else
		{
			createInfo.enabledLayerCount = 0;
			mValidationEnabled = false;
		}

		if (VulkanNative.vkCreateInstance(&createInfo, null, &mInstance) != .VK_SUCCESS)
		{
			mInstance = default;
			return;
		}

		// Load instance functions
		InstanceFunctionFlags flags = .Agnostic;
#if BF_PLATFORM_WINDOWS
		flags |= .Win32;
#endif
#if BF_PLATFORM_LINUX
		flags |= .Xlib;
#endif

		VulkanNative.LoadInstanceFunctions(mInstance, flags, null, scope (func) =>
			{
				// Failed to load function
			}).IgnoreError();

		VulkanNative.LoadPostInstanceFunctions();

		// Setup debug messenger
		if (mValidationEnabled)
		{
			SetupDebugMessenger();
		}
	}

	private bool CheckValidationLayerSupport()
	{
		uint32 layerCount = 0;
		VulkanNative.vkEnumerateInstanceLayerProperties(&layerCount, null);

		if (layerCount == 0)
			return false;

		VkLayerProperties* availableLayers = scope VkLayerProperties[(int)layerCount]*;
		VulkanNative.vkEnumerateInstanceLayerProperties(&layerCount, availableLayers);

		for (let layerName in sValidationLayers)
		{
			bool found = false;
			for (uint32 i = 0; i < layerCount; i++)
			{
				if (String.Equals(layerName, &availableLayers[i].layerName))
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

	private void SetupDebugMessenger()
	{
		VkDebugUtilsMessengerCreateInfoEXT createInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
				messageSeverity = .VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | .VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
				messageType = .VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | .VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | .VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
				pfnUserCallback = sDebugCallbackDelegate,
				pUserData = null
			};

		VulkanNative.vkCreateDebugUtilsMessengerEXT(mInstance, &createInfo, null, &mDebugMessenger);
	}

	[CallingConvention(.Stdcall)]
	private static VkBool32 DebugCallback(
		VkDebugUtilsMessageSeverityFlagsEXT messageSeverity,
		VkDebugUtilsMessageTypeFlagsEXT messageType,
		VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
		void* pUserData)
	{
		if (pCallbackData != null && pCallbackData.pMessage != null)
		{
			Console.Error.WriteLine(scope $"[Vulkan] {StringView(pCallbackData.pMessage)}");
		}
		return VkBool32.False;
	}

	private void EnumeratePhysicalDevices()
	{
		if (mInstance == default)
			return;

		uint32 deviceCount = 0;
		VulkanNative.vkEnumeratePhysicalDevices(mInstance, &deviceCount, null);

		if (deviceCount == 0)
			return;

		VkPhysicalDevice* devices = scope VkPhysicalDevice[(int)deviceCount]*;
		VulkanNative.vkEnumeratePhysicalDevices(mInstance, &deviceCount, devices);

		for (int i = 0; i < (int)deviceCount; i++)
		{
			mAdapters.Add(new VulkanAdapter(this, devices[i]));
		}
	}

	private static mixin VK_MAKE_VERSION(uint32 major, uint32 minor, uint32 patch)
	{
		((major << 22) | (minor << 12) | patch)
	}
}
