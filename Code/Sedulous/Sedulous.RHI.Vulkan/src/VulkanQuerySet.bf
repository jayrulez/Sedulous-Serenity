namespace Sedulous.RHI.Vulkan;

using System;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of IQuerySet.
class VulkanQuerySet : IQuerySet
{
	private VulkanDevice mDevice;
	private VkQueryPool mQueryPool;
	private QueryType mType;
	private uint32 mCount;

	public this(VulkanDevice device, QuerySetDescriptor* descriptor)
	{
		mDevice = device;
		mType = descriptor.Type;
		mCount = descriptor.Count;
		CreateQueryPool(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mQueryPool != default)
		{
			VulkanNative.vkDestroyQueryPool(mDevice.Device, mQueryPool, null);
			mQueryPool = default;
		}
	}

	public QueryType Type => mType;
	public uint32 Count => mCount;

	/// Returns true if the query pool was created successfully.
	public bool IsValid => mQueryPool != default;

	/// Gets the Vulkan query pool handle.
	public VkQueryPool QueryPool => mQueryPool;

	public bool GetResults(uint32 firstQuery, uint32 queryCount, Span<uint8> destination, bool wait)
	{
		if (mQueryPool == default)
			return false;

		VkQueryResultFlags flags = .VK_QUERY_RESULT_64_BIT;
		if (wait)
			flags |= .VK_QUERY_RESULT_WAIT_BIT;

		uint64 stride = GetResultStride();

		let result = VulkanNative.vkGetQueryPoolResults(
			mDevice.Device,
			mQueryPool,
			firstQuery,
			queryCount,
			(uint)destination.Length,
			destination.Ptr,
			stride,
			flags
		);

		return result == .VK_SUCCESS;
	}

	private uint64 GetResultStride()
	{
		switch (mType)
		{
		case .Timestamp, .Occlusion:
			return sizeof(uint64);
		case .PipelineStatistics:
			return (uint64)sizeof(PipelineStatistics);
		}
	}

	private void CreateQueryPool(QuerySetDescriptor* descriptor)
	{
		VkQueryType vkQueryType;
		VkQueryPipelineStatisticFlags statisticFlags = default;

		switch (descriptor.Type)
		{
		case .Occlusion:
			vkQueryType = .VK_QUERY_TYPE_OCCLUSION;
		case .Timestamp:
			vkQueryType = .VK_QUERY_TYPE_TIMESTAMP;
		case .PipelineStatistics:
			vkQueryType = .VK_QUERY_TYPE_PIPELINE_STATISTICS;
			statisticFlags = .VK_QUERY_PIPELINE_STATISTIC_INPUT_ASSEMBLY_VERTICES_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_INPUT_ASSEMBLY_PRIMITIVES_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_VERTEX_SHADER_INVOCATIONS_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_GEOMETRY_SHADER_INVOCATIONS_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_GEOMETRY_SHADER_PRIMITIVES_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_CLIPPING_INVOCATIONS_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_CLIPPING_PRIMITIVES_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_FRAGMENT_SHADER_INVOCATIONS_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_TESSELLATION_CONTROL_SHADER_PATCHES_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_TESSELLATION_EVALUATION_SHADER_INVOCATIONS_BIT |
				.VK_QUERY_PIPELINE_STATISTIC_COMPUTE_SHADER_INVOCATIONS_BIT;
		}

		VkQueryPoolCreateInfo createInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
				queryType = vkQueryType,
				queryCount = descriptor.Count,
				pipelineStatistics = statisticFlags
			};

		VulkanNative.vkCreateQueryPool(mDevice.Device, &createInfo, null, &mQueryPool);
	}
}
