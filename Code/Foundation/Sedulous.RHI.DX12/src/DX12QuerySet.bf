namespace Sedulous.RHI.DX12;

using System;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Foundation;
using Sedulous.RHI;

/// DX12 implementation of IQuerySet using ID3D12QueryHeap + readback buffer.
class DX12QuerySet : IQuerySet
{
	private DX12Device mDevice;
	private ID3D12QueryHeap* mQueryHeap;
	private ID3D12Resource* mReadbackBuffer;
	private QueryType mType;
	private uint32 mCount;
	private uint32 mResultStride;

	public this(DX12Device device, QuerySetDescriptor* descriptor)
	{
		mDevice = device;
		mType = descriptor.Type;
		mCount = descriptor.Count;
		mResultStride = GetResultStride(descriptor.Type);
		CreateQueryHeap(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mReadbackBuffer != null) { mReadbackBuffer.Release(); mReadbackBuffer = null; }
		if (mQueryHeap != null) { mQueryHeap.Release(); mQueryHeap = null; }
	}

	public bool IsValid => mQueryHeap != null;
	public QueryType Type => mType;
	public uint32 Count => mCount;
	public ID3D12QueryHeap* QueryHeap => mQueryHeap;
	public ID3D12Resource* ReadbackBuffer => mReadbackBuffer;
	public uint32 ResultStride => mResultStride;

	public bool GetResults(uint32 firstQuery, uint32 queryCount, Span<uint8> destination, bool wait = true)
	{
		if (mReadbackBuffer == null || queryCount == 0)
			return false;

		// Map the readback buffer and copy results
		void* mappedData = null;
		D3D12_RANGE readRange = .();
		readRange.Begin = (uint)(firstQuery * mResultStride);
		readRange.End = (uint)((firstQuery + queryCount) * mResultStride);

		HRESULT hr = mReadbackBuffer.Map(0, &readRange, &mappedData);
		if (!SUCCEEDED(hr))
			return false;

		uint64 copySize = Math.Min((uint64)(queryCount * mResultStride), (uint64)destination.Length);
		Internal.MemCpy(destination.Ptr, (uint8*)mappedData + firstQuery * mResultStride, (int)copySize);

		D3D12_RANGE writtenRange = .();
		writtenRange.Begin = 0;
		writtenRange.End = 0;
		mReadbackBuffer.Unmap(0, &writtenRange);

		return true;
	}

	private void CreateQueryHeap(QuerySetDescriptor* descriptor)
	{
		D3D12_QUERY_HEAP_DESC heapDesc = .();
		heapDesc.Count = descriptor.Count;
		heapDesc.NodeMask = 0;

		switch (descriptor.Type)
		{
		case .Timestamp:
			heapDesc.Type = .D3D12_QUERY_HEAP_TYPE_TIMESTAMP;
		case .Occlusion:
			heapDesc.Type = .D3D12_QUERY_HEAP_TYPE_OCCLUSION;
		case .PipelineStatistics:
			heapDesc.Type = .D3D12_QUERY_HEAP_TYPE_PIPELINE_STATISTICS;
		}

		HRESULT hr = mDevice.NativeDevice.CreateQueryHeap(
			&heapDesc,
			ID3D12QueryHeap.IID,
			(void**)&mQueryHeap);

		if (!SUCCEEDED(hr))
		{
			mQueryHeap = null;
			return;
		}

		// Create readback buffer for ResolveQueryData results
		uint64 bufferSize = (uint64)(descriptor.Count * mResultStride);

		D3D12_HEAP_PROPERTIES heapProps = .();
		heapProps.Type = .D3D12_HEAP_TYPE_READBACK;
		heapProps.CPUPageProperty = .D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
		heapProps.MemoryPoolPreference = .D3D12_MEMORY_POOL_UNKNOWN;
		heapProps.CreationNodeMask = 1;
		heapProps.VisibleNodeMask = 1;

		D3D12_RESOURCE_DESC resourceDesc = .();
		resourceDesc.Dimension = .D3D12_RESOURCE_DIMENSION_BUFFER;
		resourceDesc.Alignment = 0;
		resourceDesc.Width = bufferSize;
		resourceDesc.Height = 1;
		resourceDesc.DepthOrArraySize = 1;
		resourceDesc.MipLevels = 1;
		resourceDesc.Format = .DXGI_FORMAT_UNKNOWN;
		resourceDesc.SampleDesc.Count = 1;
		resourceDesc.SampleDesc.Quality = 0;
		resourceDesc.Layout = .D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
		resourceDesc.Flags = .D3D12_RESOURCE_FLAG_NONE;

		hr = mDevice.NativeDevice.CreateCommittedResource(
			&heapProps,
			.D3D12_HEAP_FLAG_NONE,
			&resourceDesc,
			.D3D12_RESOURCE_STATE_COPY_DEST,
			null,
			ID3D12Resource.IID,
			(void**)&mReadbackBuffer);

		if (!SUCCEEDED(hr))
			mReadbackBuffer = null;
	}

	private static uint32 GetResultStride(QueryType type)
	{
		switch (type)
		{
		case .Timestamp, .Occlusion:
			return 8; // sizeof(uint64)
		case .PipelineStatistics:
			return (uint32)sizeof(PipelineStatistics);
		}
	}
}
