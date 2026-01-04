namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of IDevice.
class VulkanDevice : IDevice
{
	private VulkanAdapter mAdapter;
	private VkDevice mDevice;
	private VulkanQueue mQueue;
	private QueueFamilyIndices mQueueFamilyIndices;
	private VulkanDescriptorPool mDescriptorPool;
	private VulkanCommandPool mCommandPool;

	private static char8*[?] sDeviceExtensions = .("VK_KHR_swapchain");

	public this(VulkanAdapter adapter)
	{
		mAdapter = adapter;
		CreateDevice();

		if (mDevice != default)
		{
			mDescriptorPool = new VulkanDescriptorPool(this);
			if (mQueueFamilyIndices.GraphicsFamily.HasValue)
			{
				mCommandPool = new VulkanCommandPool(this, mQueueFamilyIndices.GraphicsFamily.Value);
			}
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mCommandPool != null)
		{
			delete mCommandPool;
			mCommandPool = null;
		}

		if (mDescriptorPool != null)
		{
			delete mDescriptorPool;
			mDescriptorPool = null;
		}

		if (mQueue != null)
		{
			delete mQueue;
			mQueue = null;
		}

		if (mDevice != default)
		{
			VulkanNative.vkDestroyDevice(mDevice, null);
			mDevice = default;
		}
	}

	/// Returns true if the device was created successfully.
	public bool IsInitialized => mDevice != default;

	public IAdapter Adapter => mAdapter;
	public IQueue Queue => mQueue;
	public bool FlipProjectionRequired => true;

	/// Gets the Vulkan logical device handle.
	public VkDevice Device => mDevice;

	/// Gets the queue family indices.
	public QueueFamilyIndices QueueFamilyIndices => mQueueFamilyIndices;

	// ===== Resource Creation =====

	public Result<IBuffer> CreateBuffer(BufferDescriptor* descriptor)
	{
		let buffer = new VulkanBuffer(this, descriptor);
		if (!buffer.IsValid)
		{
			delete buffer;
			return .Err;
		}
		return .Ok(buffer);
	}

	public Result<ITexture> CreateTexture(TextureDescriptor* descriptor)
	{
		let texture = new VulkanTexture(this, descriptor);
		if (!texture.IsValid)
		{
			delete texture;
			return .Err;
		}
		return .Ok(texture);
	}

	public Result<ITextureView> CreateTextureView(ITexture texture, TextureViewDescriptor* descriptor)
	{
		if (let vkTexture = texture as VulkanTexture)
		{
			let view = new VulkanTextureView(this, vkTexture, descriptor);
			if (!view.IsValid)
			{
				delete view;
				return .Err;
			}
			return .Ok(view);
		}
		return .Err;
	}

	public Result<ISampler> CreateSampler(SamplerDescriptor* descriptor)
	{
		let sampler = new VulkanSampler(this, descriptor);
		if (!sampler.IsValid)
		{
			delete sampler;
			return .Err;
		}
		return .Ok(sampler);
	}

	public Result<IShaderModule> CreateShaderModule(ShaderModuleDescriptor* descriptor)
	{
		let shaderModule = new VulkanShaderModule(this, descriptor);
		if (!shaderModule.IsValid)
		{
			delete shaderModule;
			return .Err;
		}
		return .Ok(shaderModule);
	}

	// ===== Binding =====

	public Result<IBindGroupLayout> CreateBindGroupLayout(BindGroupLayoutDescriptor* descriptor)
	{
		let layout = new VulkanBindGroupLayout(this, descriptor);
		if (!layout.IsValid)
		{
			delete layout;
			return .Err;
		}
		return .Ok(layout);
	}

	public Result<IBindGroup> CreateBindGroup(BindGroupDescriptor* descriptor)
	{
		if (mDescriptorPool == null)
			return .Err;

		let bindGroup = new VulkanBindGroup(this, mDescriptorPool, descriptor);
		if (!bindGroup.IsValid)
		{
			delete bindGroup;
			return .Err;
		}
		return .Ok(bindGroup);
	}

	public Result<IPipelineLayout> CreatePipelineLayout(PipelineLayoutDescriptor* descriptor)
	{
		let layout = new VulkanPipelineLayout(this, descriptor);
		if (!layout.IsValid)
		{
			delete layout;
			return .Err;
		}
		return .Ok(layout);
	}

	// ===== Pipelines =====

	public Result<IRenderPipeline> CreateRenderPipeline(RenderPipelineDescriptor* descriptor)
	{
		let pipeline = new VulkanRenderPipeline(this, descriptor);
		if (!pipeline.IsValid)
		{
			delete pipeline;
			return .Err;
		}
		return .Ok(pipeline);
	}

	public Result<IComputePipeline> CreateComputePipeline(ComputePipelineDescriptor* descriptor)
	{
		let pipeline = new VulkanComputePipeline(this, descriptor);
		if (!pipeline.IsValid)
		{
			delete pipeline;
			return .Err;
		}
		return .Ok(pipeline);
	}

	// ===== Commands =====

	public ICommandEncoder CreateCommandEncoder()
	{
		if (mCommandPool == null)
			return null;

		let encoder = new VulkanCommandEncoder(this, mCommandPool);
		if (!encoder.IsValid)
		{
			delete encoder;
			return null;
		}
		return encoder;
	}

	// ===== Queries =====

	public Result<IQuerySet> CreateQuerySet(QuerySetDescriptor* descriptor)
	{
		let querySet = new VulkanQuerySet(this, descriptor);
		if (!querySet.IsValid)
		{
			delete querySet;
			return .Err;
		}
		return .Ok(querySet);
	}

	// ===== Presentation =====

	public Result<ISwapChain> CreateSwapChain(ISurface surface, SwapChainDescriptor* descriptor)
	{
		if (let vkSurface = surface as VulkanSurface)
		{
			let swapChain = new VulkanSwapChain(this, vkSurface, descriptor);
			if (swapChain.SwapChain == default)
			{
				delete swapChain;
				return .Err;
			}
			return .Ok(swapChain);
		}
		return .Err;
	}

	// ===== Synchronization =====

	public Result<IFence> CreateFence(bool signaled = false)
	{
		let fence = new VulkanFence(this, signaled);
		if (!fence.IsValid)
		{
			delete fence;
			return .Err;
		}
		return .Ok(fence);
	}

	public void WaitIdle()
	{
		if (mDevice != default)
		{
			VulkanNative.vkDeviceWaitIdle(mDevice);
		}
	}

	private void CreateDevice()
	{
		// Find queue families (without surface for now)
		mQueueFamilyIndices = mAdapter.FindQueueFamilies();

		if (!mQueueFamilyIndices.HasGraphics)
			return;

		// Check device extension support
		if (!mAdapter.CheckDeviceExtensionSupport(sDeviceExtensions))
			return;

		// Create queue create infos
		List<VkDeviceQueueCreateInfo> queueCreateInfos = scope .();
		HashSet<uint32> uniqueQueueFamilies = scope .();

		if (mQueueFamilyIndices.GraphicsFamily.HasValue)
			uniqueQueueFamilies.Add(mQueueFamilyIndices.GraphicsFamily.Value);

		float queuePriority = 1.0f;
		for (let queueFamily in uniqueQueueFamilies)
		{
			VkDeviceQueueCreateInfo queueCreateInfo = .()
				{
					sType = .VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
					queueFamilyIndex = queueFamily,
					queueCount = 1,
					pQueuePriorities = &queuePriority
				};
			queueCreateInfos.Add(queueCreateInfo);
		}

		// Device features
		VkPhysicalDeviceFeatures deviceFeatures = .();
		deviceFeatures.fillModeNonSolid = VkBool32.True;  // Enable wireframe rendering

		// Create device
		VkDeviceCreateInfo createInfo = .();
		createInfo.sType = .VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
		createInfo.queueCreateInfoCount = (uint32)queueCreateInfos.Count;
		createInfo.pQueueCreateInfos = queueCreateInfos.Ptr;
		createInfo.pEnabledFeatures = &deviceFeatures;
		createInfo.enabledExtensionCount = (uint32)sDeviceExtensions.Count;
		createInfo.ppEnabledExtensionNames = &sDeviceExtensions;
		createInfo.enabledLayerCount = 0;

		if (VulkanNative.vkCreateDevice(mAdapter.PhysicalDevice, &createInfo, null, &mDevice) != .VK_SUCCESS)
		{
			mDevice = default;
			return;
		}

		// Get queues
		VkQueue graphicsQueue = default;
		VulkanNative.vkGetDeviceQueue(mDevice, mQueueFamilyIndices.GraphicsFamily.Value, 0, &graphicsQueue);
		mQueue = new VulkanQueue(this, graphicsQueue, mQueueFamilyIndices.GraphicsFamily.Value);
	}
}
