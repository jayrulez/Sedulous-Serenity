namespace Sedulous.RHI.DX12.Internal;

using System;
using Win32.Graphics.Direct3D12;
using Win32.Foundation;

using Win32;

/// Linear descriptor allocator for GPU-visible heaps and CPU staging heaps.
/// Descriptors are allocated sequentially and never freed individually.
class DX12DescriptorAllocator
{
	private ID3D12DescriptorHeap* mHeap;
	private D3D12_DESCRIPTOR_HEAP_TYPE mType;
	private uint32 mDescriptorSize;
	private uint32 mCapacity;
	private uint32 mCount;
	private D3D12_CPU_DESCRIPTOR_HANDLE mCpuStart;
	private D3D12_GPU_DESCRIPTOR_HANDLE mGpuStart;
	private bool mShaderVisible;

	public this(ID3D12Device* device, D3D12_DESCRIPTOR_HEAP_TYPE type, uint32 capacity, bool shaderVisible)
	{
		mType = type;
		mCapacity = capacity;
		mCount = 0;
		mShaderVisible = shaderVisible;

		mDescriptorSize = device.GetDescriptorHandleIncrementSize(type);

		D3D12_DESCRIPTOR_HEAP_DESC desc = .();
		desc.Type = type;
		desc.NumDescriptors = capacity;
		desc.Flags = shaderVisible ? .D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE : .D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
		desc.NodeMask = 0;

		HRESULT hr = device.CreateDescriptorHeap(&desc, ID3D12DescriptorHeap.IID, (void**)&mHeap);
		if (SUCCEEDED(hr))
		{
			mCpuStart = mHeap.GetCPUDescriptorHandleForHeapStart();
			if (shaderVisible)
				mGpuStart = mHeap.GetGPUDescriptorHandleForHeapStart();
		}
	}

	public ~this()
	{
		if (mHeap != null)
		{
			mHeap.Release();
			mHeap = null;
		}
	}

	public bool IsValid => mHeap != null;
	public ID3D12DescriptorHeap* Heap => mHeap;
	public uint32 DescriptorSize => mDescriptorSize;

	/// Allocates a contiguous range of descriptors. Returns the CPU handle of the first descriptor.
	/// outGpuHandle is set if the heap is shader-visible.
	public bool Allocate(uint32 count, out D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle, out D3D12_GPU_DESCRIPTOR_HANDLE gpuHandle)
	{
		cpuHandle = default;
		gpuHandle = default;

		if (mCount + count > mCapacity)
			return false;

		cpuHandle.ptr = mCpuStart.ptr + (uint)(mCount * mDescriptorSize);
		if (mShaderVisible)
			gpuHandle.ptr = mGpuStart.ptr + (uint64)(mCount * mDescriptorSize);

		mCount += count;
		return true;
	}

	/// Allocates a single descriptor.
	public bool Allocate(out D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle, out D3D12_GPU_DESCRIPTOR_HANDLE gpuHandle)
	{
		return Allocate(1, out cpuHandle, out gpuHandle);
	}

	/// Resets the allocator (all previous allocations become invalid).
	public void Reset()
	{
		mCount = 0;
	}
}

/// Free-list descriptor allocator for CPU-only heaps (RTV, DSV).
/// Supports individual allocation and deallocation.
class DX12CpuDescriptorAllocator
{
	private ID3D12DescriptorHeap* mHeap;
	private D3D12_DESCRIPTOR_HEAP_TYPE mType;
	private uint32 mDescriptorSize;
	private uint32 mCapacity;
	private D3D12_CPU_DESCRIPTOR_HANDLE mCpuStart;
	private uint32* mFreeList;
	private uint32 mFreeCount;

	public this(ID3D12Device* device, D3D12_DESCRIPTOR_HEAP_TYPE type, uint32 capacity)
	{
		mType = type;
		mCapacity = capacity;

		mDescriptorSize = device.GetDescriptorHandleIncrementSize(type);

		D3D12_DESCRIPTOR_HEAP_DESC desc = .();
		desc.Type = type;
		desc.NumDescriptors = capacity;
		desc.Flags = .D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
		desc.NodeMask = 0;

		HRESULT hr = device.CreateDescriptorHeap(&desc, ID3D12DescriptorHeap.IID, (void**)&mHeap);
		if (SUCCEEDED(hr))
		{
			mCpuStart = mHeap.GetCPUDescriptorHandleForHeapStart();

			// Initialize free list with all indices
			mFreeList = new uint32[capacity]*;
			mFreeCount = capacity;
			for (uint32 i = 0; i < capacity; i++)
				mFreeList[i] = capacity - 1 - i; // Stack order: pop from end
		}
	}

	public ~this()
	{
		if (mFreeList != null)
		{
			delete mFreeList;
			mFreeList = null;
		}
		if (mHeap != null)
		{
			mHeap.Release();
			mHeap = null;
		}
	}

	public bool IsValid => mHeap != null;
	public uint32 DescriptorSize => mDescriptorSize;

	/// Allocates a single descriptor from the free list.
	public bool Allocate(out D3D12_CPU_DESCRIPTOR_HANDLE handle)
	{
		handle = default;

		if (mFreeCount == 0)
			return false;

		mFreeCount--;
		uint32 index = mFreeList[mFreeCount];
		handle.ptr = mCpuStart.ptr + (uint)(index * mDescriptorSize);
		return true;
	}

	/// Frees a previously allocated descriptor back to the free list.
	public void Free(D3D12_CPU_DESCRIPTOR_HANDLE handle)
	{
		if (handle.ptr == 0)
			return;

		uint32 index = (uint32)((handle.ptr - mCpuStart.ptr) / (uint)mDescriptorSize);
		if (index < mCapacity && mFreeCount < mCapacity)
		{
			mFreeList[mFreeCount] = index;
			mFreeCount++;
		}
	}
}
