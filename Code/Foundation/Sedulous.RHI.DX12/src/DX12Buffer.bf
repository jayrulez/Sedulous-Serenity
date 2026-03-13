namespace Sedulous.RHI.DX12;

using System;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Dxgi.Common;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

using Win32;

/// DX12 implementation of IBuffer.
class DX12Buffer : IBuffer
{
	private DX12Device mDevice;
	private ID3D12Resource* mResource;
	private uint64 mSize;
	private BufferUsage mUsage;
	private MemoryAccess mMemoryAccess;
	private uint32 mStructureByteStride;
	private void* mMappedPtr;
	private uint64 mGpuVirtualAddress;
	private String mDebugName ~ delete _;
	private D3D12_RESOURCE_STATES mCurrentState;

	public this(DX12Device device, BufferDescriptor* descriptor)
	{
		mDevice = device;
		mSize = descriptor.Size;
		mUsage = descriptor.Usage;
		mMemoryAccess = descriptor.MemoryAccess;
		mStructureByteStride = descriptor.StructureByteStride;
		if (descriptor.Label.Ptr != null && descriptor.Label.Length > 0)
			mDebugName = new String(descriptor.Label);
		CreateBuffer(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mMappedPtr != null && mResource != null)
		{
			mResource.Unmap(0, null);
			mMappedPtr = null;
		}

		if (mResource != null)
		{
			mResource.Release();
			mResource = null;
		}
	}

	public bool IsValid => mResource != null;
	public StringView DebugName => mDebugName != null ? mDebugName : "";
	public uint64 Size => mSize;
	public BufferUsage Usage => mUsage;
	public uint32 StructureByteStride => mStructureByteStride;
	public ID3D12Resource* Resource => mResource;
	public uint64 GpuVirtualAddress => mGpuVirtualAddress;
	public D3D12_RESOURCE_STATES CurrentState { get => mCurrentState; set => mCurrentState = value; }

	public void* Map()
	{
		if (mMappedPtr != null)
			return mMappedPtr;

		if (mMemoryAccess == .GpuOnly)
			return null;

		void* data = null;
		D3D12_RANGE readRange = .();
		if (mMemoryAccess == .Upload)
		{
			// Upload buffers: no need to read
			readRange.Begin = 0;
			readRange.End = 0;
		}
		else
		{
			// Readback buffers: read the whole range
			readRange.Begin = 0;
			readRange.End = (uint)mSize;
		}

		if (SUCCEEDED(mResource.Map(0, &readRange, &data)))
		{
			mMappedPtr = data;
			return data;
		}

		return null;
	}

	public void Unmap()
	{
		if (mMappedPtr != null && mResource != null)
		{
			D3D12_RANGE writtenRange = .();
			if (mMemoryAccess == .Readback)
			{
				// Readback: nothing was written by CPU
				writtenRange.Begin = 0;
				writtenRange.End = 0;
			}
			else
			{
				// Upload: whole range was potentially written
				writtenRange.Begin = 0;
				writtenRange.End = (uint)mSize;
			}

			mResource.Unmap(0, &writtenRange);
			mMappedPtr = null;
		}
	}

	/// Transitions the buffer to a new resource state. Returns true if a barrier was needed.
	public bool TransitionTo(D3D12_RESOURCE_STATES newState, out D3D12_RESOURCE_BARRIER barrier)
	{
		barrier = default;
		if (mCurrentState == newState)
			return false;

		barrier.Type = .D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
		barrier.Flags = .D3D12_RESOURCE_BARRIER_FLAG_NONE;
		barrier.Transition.pResource = mResource;
		barrier.Transition.Subresource = 0xFFFFFFFF; // D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES
		barrier.Transition.StateBefore = mCurrentState;
		barrier.Transition.StateAfter = newState;

		mCurrentState = newState;
		return true;
	}

	private void CreateBuffer(BufferDescriptor* descriptor)
	{
		// Determine heap type from memory access
		D3D12_HEAP_TYPE heapType;
		switch (descriptor.MemoryAccess)
		{
		case .GpuOnly:   heapType = .D3D12_HEAP_TYPE_DEFAULT;
		case .Upload:    heapType = .D3D12_HEAP_TYPE_UPLOAD;
		case .Readback:  heapType = .D3D12_HEAP_TYPE_READBACK;
		default:         heapType = .D3D12_HEAP_TYPE_DEFAULT;
		}

		// Determine initial state
		switch (descriptor.MemoryAccess)
		{
		case .Upload:    mCurrentState = .D3D12_RESOURCE_STATE_GENERIC_READ;
		case .Readback:  mCurrentState = .D3D12_RESOURCE_STATE_COPY_DEST;
		default:         mCurrentState = .D3D12_RESOURCE_STATE_COMMON;
		}

		// CBV requires 256-byte alignment
		uint64 size = descriptor.Size;
		if ((descriptor.Usage & .Uniform) != 0)
			size = (size + 255) & ~(uint64)255;

		D3D12_HEAP_PROPERTIES heapProps = .();
		heapProps.Type = heapType;
		heapProps.CPUPageProperty = .D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
		heapProps.MemoryPoolPreference = .D3D12_MEMORY_POOL_UNKNOWN;
		heapProps.CreationNodeMask = 1;
		heapProps.VisibleNodeMask = 1;

		D3D12_RESOURCE_DESC resourceDesc = .();
		resourceDesc.Dimension = .D3D12_RESOURCE_DIMENSION_BUFFER;
		resourceDesc.Alignment = 0;
		resourceDesc.Width = size;
		resourceDesc.Height = 1;
		resourceDesc.DepthOrArraySize = 1;
		resourceDesc.MipLevels = 1;
		resourceDesc.Format = .DXGI_FORMAT_UNKNOWN;
		resourceDesc.SampleDesc.Count = 1;
		resourceDesc.SampleDesc.Quality = 0;
		resourceDesc.Layout = .D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
		resourceDesc.Flags = .D3D12_RESOURCE_FLAG_NONE;

		// Storage buffers need UAV flag
		if ((descriptor.Usage & .Storage) != 0)
			resourceDesc.Flags = .D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;

		HRESULT hr = mDevice.NativeDevice.CreateCommittedResource(
			&heapProps,
			.D3D12_HEAP_FLAG_NONE,
			&resourceDesc,
			mCurrentState,
			null,
			ID3D12Resource.IID,
			(void**)&mResource);

		if (SUCCEEDED(hr))
		{
			mGpuVirtualAddress = mResource.GetGPUVirtualAddress();

			// Persistent mapping for Upload/Readback
			if (descriptor.MemoryAccess == .Upload || descriptor.MemoryAccess == .Readback)
			{
				Map();
			}
		}
	}
}
