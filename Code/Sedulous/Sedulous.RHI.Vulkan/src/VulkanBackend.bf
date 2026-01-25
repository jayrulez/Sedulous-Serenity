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
	private bool mDebugUtilsEnabled;
	private List<VulkanAdapter> mAdapters = new .() ~ DeleteContainerAndItems!(_);

	private static char8*[?] sValidationLayers = .("VK_LAYER_KHRONOS_validation");

	// Debug callback delegate type
	typealias DebugCallbackDelegate = function VkBool32(
		VkDebugUtilsMessageSeverityFlagsEXT messageSeverity,
		VkDebugUtilsMessageTypeFlagsEXT messageType,
		VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
		void* pUserData);

	private static DebugCallbackDelegate sDebugCallbackDelegate = => DebugCallback;

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
		if (mDebugMessenger != default && mDebugUtilsEnabled)
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

		// Build required extensions list
		List<char8*> extensions = scope .();
		extensions.Add("VK_KHR_surface");
#if BF_PLATFORM_WINDOWS
		extensions.Add("VK_KHR_win32_surface");
#endif
#if BF_PLATFORM_LINUX
		extensions.Add("VK_KHR_xlib_surface");
#endif

		// Check if validation layers are available
		bool validationAvailable = mValidationEnabled && CheckValidationLayerSupport();

		// Add debug extension only if validation is enabled and the extension is available
		bool debugUtilsAvailable = false;
		bool validationFeaturesAvailable = false;
		if (validationAvailable)
		{
			debugUtilsAvailable = CheckExtensionSupport("VK_EXT_debug_utils");
			if (debugUtilsAvailable)
			{
				extensions.Add("VK_EXT_debug_utils");
			}

			// Check for validation features extension (needed for GPU-assisted validation)
			validationFeaturesAvailable = CheckExtensionSupport("VK_EXT_validation_features");
			if (validationFeaturesAvailable)
			{
				extensions.Add("VK_EXT_validation_features");
				Console.WriteLine("[Vulkan] VK_EXT_validation_features extension available");
			}
			else
			{
				Console.WriteLine("[Vulkan] WARNING: VK_EXT_validation_features extension NOT available");
			}
		}

		// Create instance
		VkInstanceCreateInfo createInfo = .();
		createInfo.sType = .VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
		createInfo.pApplicationInfo = &appInfo;
		createInfo.enabledExtensionCount = (uint32)extensions.Count;
		createInfo.ppEnabledExtensionNames = extensions.Ptr;

		// Enable validation layers
		if (validationAvailable)
		{
			createInfo.enabledLayerCount = (uint32)sValidationLayers.Count;
			createInfo.ppEnabledLayerNames = &sValidationLayers;
		}
		else
		{
			createInfo.enabledLayerCount = 0;
			mValidationEnabled = false;
		}

		// Enable GPU-assisted validation if the extension is available
		// This provides more detailed error messages for buffer overflows, descriptor issues, etc.
		VkValidationFeaturesEXT validationFeatures = .();
		VkValidationFeatureEnableEXT[3] enabledFeatures = .(
			.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_EXT,
			.VK_VALIDATION_FEATURE_ENABLE_GPU_ASSISTED_RESERVE_BINDING_SLOT_EXT,
			.VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT
		);

		if (validationFeaturesAvailable)
		{
			validationFeatures.sType = .VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT;
			validationFeatures.pNext = null;
			validationFeatures.enabledValidationFeatureCount = (uint32)enabledFeatures.Count;
			validationFeatures.pEnabledValidationFeatures = &enabledFeatures;
			validationFeatures.disabledValidationFeatureCount = 0;
			validationFeatures.pDisabledValidationFeatures = null;

			createInfo.pNext = &validationFeatures;
			Console.WriteLine("[Vulkan] GPU-assisted validation ENABLED");
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

		// Add debug utils functions if the extension is enabled
		List<String> additionalFunctions = null;
		if (debugUtilsAvailable)
		{
			additionalFunctions = scope:: List<String>();
			additionalFunctions.Add("vkCreateDebugUtilsMessengerEXT");
			additionalFunctions.Add("vkDestroyDebugUtilsMessengerEXT");
			additionalFunctions.Add("vkSubmitDebugUtilsMessageEXT");
			additionalFunctions.Add("vkSetDebugUtilsObjectNameEXT");
		}

		VulkanNative.LoadInstanceFunctions(mInstance, flags, additionalFunctions, scope (func) =>
			{
				// Failed to load function
			}).IgnoreError();

		VulkanNative.LoadPostInstanceFunctions();

		// Setup debug messenger only if debug utils extension was loaded
		mDebugUtilsEnabled = debugUtilsAvailable;
		if (mValidationEnabled && mDebugUtilsEnabled)
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

	private bool CheckExtensionSupport(StringView extensionName)
	{
		uint32 extensionCount = 0;
		VulkanNative.vkEnumerateInstanceExtensionProperties(null, &extensionCount, null);

		if (extensionCount == 0)
			return false;

		VkExtensionProperties* availableExtensions = scope VkExtensionProperties[(int)extensionCount]*;
		VulkanNative.vkEnumerateInstanceExtensionProperties(null, &extensionCount, availableExtensions);

		for (uint32 i = 0; i < extensionCount; i++)
		{
			if (extensionName == StringView(&availableExtensions[i].extensionName))
				return true;
		}

		return false;
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
			StringView message = .(pCallbackData.pMessage);
			Console.Error.WriteLine(scope $"[Vulkan] {message}");

			if(message.Contains("vkFreeDescriptorSets()") || message.Contains("can't be called on VkImageView"))
			{
				int x = 1;
			}
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
