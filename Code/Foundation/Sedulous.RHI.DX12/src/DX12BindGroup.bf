namespace Sedulous.RHI.DX12;

using System;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Dxgi.Common;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of IBindGroup. Allocates GPU descriptor heap ranges
/// and copies/creates descriptors from CPU staging.
class DX12BindGroup : IBindGroup
{
	private DX12Device mDevice;
	private DX12BindGroupLayout mLayout;
	private D3D12_GPU_DESCRIPTOR_HANDLE mCbvSrvUavGpuHandle;
	private D3D12_GPU_DESCRIPTOR_HANDLE mSamplerGpuHandle;
	private bool mHasCbvSrvUav;
	private bool mHasSampler;
	private bool mValid;

	// Dynamic offset entries store buffer GPU virtual addresses (bound via root CBV at draw time)
	private uint64[DX12PipelineLayout.MaxDynamicPerGroup] mDynamicBufferGpuVAs;
	private uint32 mDynamicCount;

	public this(DX12Device device, BindGroupDesc descriptor)
	{
		mDevice = device;
		if (let layout = descriptor.Layout as DX12BindGroupLayout)
		{
			mLayout = layout;
			CreateBindGroup(descriptor);
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		// GPU heap descriptors are linearly allocated — no individual free needed
		mValid = false;
	}

	public bool IsValid => mValid;
	public IBindGroupLayout Layout => mLayout;
	public D3D12_GPU_DESCRIPTOR_HANDLE CbvSrvUavGpuHandle => mCbvSrvUavGpuHandle;
	public D3D12_GPU_DESCRIPTOR_HANDLE SamplerGpuHandle => mSamplerGpuHandle;
	public bool HasCbvSrvUav => mHasCbvSrvUav;
	public bool HasSampler => mHasSampler;
	public uint32 DynamicCount => mDynamicCount;

	/// Gets the GPU virtual address for a dynamic offset entry.
	public uint64 GetDynamicBufferGpuVA(int index) => mDynamicBufferGpuVAs[index];

	private void CreateBindGroup(BindGroupDesc descriptor)
	{
		if (mLayout == null)
			return;

		let nativeDevice = mDevice.NativeDevice;
		uint32 cbvSrvUavDescSize = mDevice.CbvSrvUavGpuHeap.DescriptorSize;
		uint32 samplerDescSize = mDevice.SamplerGpuHeap.DescriptorSize;

		// Allocate contiguous range in GPU CBV/SRV/UAV heap (only for non-dynamic entries)
		D3D12_CPU_DESCRIPTOR_HANDLE cbvSrvUavCpuStart = default;
		uint32 tableCount = mLayout.CbvSrvUavTableCount;
		if (tableCount > 0)
		{
			if (!mDevice.CbvSrvUavGpuHeap.Allocate(tableCount, out cbvSrvUavCpuStart, out mCbvSrvUavGpuHandle))
				return;
			mHasCbvSrvUav = true;
		}

		// Allocate contiguous range in GPU Sampler heap
		D3D12_CPU_DESCRIPTOR_HANDLE samplerCpuStart = default;
		if (mLayout.SamplerCount > 0)
		{
			if (!mDevice.SamplerGpuHeap.Allocate(mLayout.SamplerCount, out samplerCpuStart, out mSamplerGpuHandle))
				return;
			mHasSampler = true;
		}

		// Fill descriptors — iterate layout entries in order (must match root signature ranges).
		// Use positional matching: layout entry [i] corresponds to bind group entry [i].
		// Binding-number matching doesn't work for DX12 because different register types
		// (b0, t0, u0, s0) can all have the same binding number.
		uint32 cbvSrvUavSlot = 0;
		uint32 samplerSlot = 0;
		uint32 dynamicIdx = 0;

		for (int entryIdx = 0; entryIdx < mLayout.Entries.Count; entryIdx++)
		{
			let layoutEntry = mLayout.Entries[entryIdx];

			BindGroupEntry* matchedEntry = null;
			if (entryIdx < descriptor.Entries.Length)
			{
				var e = ref descriptor.Entries[entryIdx];
				matchedEntry = &e;
			}

			// Dynamic offset entries → store GPU VA, don't create descriptor
			if (layoutEntry.HasDynamicOffset && !DX12Conversions.IsSamplerBinding(layoutEntry.Type))
			{
				if (matchedEntry != null && matchedEntry.Buffer != null)
				{
					if (let dx12Buffer = matchedEntry.Buffer as DX12Buffer)
					{
						if (dynamicIdx < DX12PipelineLayout.MaxDynamicPerGroup)
							mDynamicBufferGpuVAs[dynamicIdx] = dx12Buffer.GpuVirtualAddress + matchedEntry.BufferOffset;
					}
				}
				dynamicIdx++;
				continue;
			}

			if (matchedEntry == null)
			{
				// No binding provided — advance slot counter with empty descriptor
				if (DX12Conversions.IsSamplerBinding(layoutEntry.Type))
					samplerSlot++;
				else
					cbvSrvUavSlot++;
				continue;
			}

			if (DX12Conversions.IsSamplerBinding(layoutEntry.Type))
			{
				// Copy sampler descriptor from CPU staging to GPU heap
				if (matchedEntry.Sampler != null)
				{
					if (let dx12Sampler = matchedEntry.Sampler as DX12Sampler)
					{
						D3D12_CPU_DESCRIPTOR_HANDLE destCpu;
						destCpu.ptr = samplerCpuStart.ptr + (uint)(samplerSlot * samplerDescSize);
						nativeDevice.CopyDescriptorsSimple(1, destCpu, dx12Sampler.CpuHandle, .D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER);
					}
				}
				samplerSlot++;
			}
			else
			{
				D3D12_CPU_DESCRIPTOR_HANDLE destCpu;
				destCpu.ptr = cbvSrvUavCpuStart.ptr + (uint)(cbvSrvUavSlot * cbvSrvUavDescSize);

				switch (layoutEntry.Type)
				{
				case .UniformBuffer:
					CreateCbv(matchedEntry, destCpu);

				case .SampledTexture:
					CopySrv(matchedEntry, destCpu);

				case .StorageTexture, .StorageTextureReadWrite:
					CopyUav(matchedEntry, destCpu);

				case .StorageBuffer:
					CreateBufferSrv(matchedEntry, destCpu);

				case .StorageBufferReadWrite:
					CreateBufferUav(matchedEntry, destCpu);

				default:
					break;
				}
				cbvSrvUavSlot++;
			}
		}

		mDynamicCount = dynamicIdx;
		mValid = true;
	}

	/// Creates a constant buffer view (CBV) directly in the GPU heap slot.
	private void CreateCbv(BindGroupEntry* entry, D3D12_CPU_DESCRIPTOR_HANDLE destCpu)
	{
		if (entry.Buffer == null)
			return;
		if (let dx12Buffer = entry.Buffer as DX12Buffer)
		{
			D3D12_CONSTANT_BUFFER_VIEW_DESC cbvDesc = .();
			cbvDesc.BufferLocation = dx12Buffer.GpuVirtualAddress + entry.BufferOffset;
			uint64 size = entry.BufferSize > 0 ? entry.BufferSize : dx12Buffer.Size - entry.BufferOffset;
			cbvDesc.SizeInBytes = (uint32)((size + 255) & ~(uint64)255); // 256-byte aligned
			mDevice.NativeDevice.CreateConstantBufferView(&cbvDesc, destCpu);
		}
	}

	/// Copies a texture's SRV from CPU staging heap to GPU heap.
	private void CopySrv(BindGroupEntry* entry, D3D12_CPU_DESCRIPTOR_HANDLE destCpu)
	{
		if (entry.TextureView == null)
			return;
		if (let dx12View = entry.TextureView as DX12TextureView)
		{
			if (dx12View.HasSrv)
				mDevice.NativeDevice.CopyDescriptorsSimple(1, destCpu, dx12View.SrvHandle, .D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
		}
	}

	/// Copies a texture's UAV from CPU staging heap to GPU heap.
	private void CopyUav(BindGroupEntry* entry, D3D12_CPU_DESCRIPTOR_HANDLE destCpu)
	{
		if (entry.TextureView == null)
			return;
		if (let dx12View = entry.TextureView as DX12TextureView)
		{
			if (dx12View.HasUav)
				mDevice.NativeDevice.CopyDescriptorsSimple(1, destCpu, dx12View.UavHandle, .D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
		}
	}

	/// Creates an SRV for a read-only storage buffer.
	/// Uses structured format when StructureByteStride > 0, raw byte-address otherwise.
	private void CreateBufferSrv(BindGroupEntry* entry, D3D12_CPU_DESCRIPTOR_HANDLE destCpu)
	{
		if (entry.Buffer == null)
			return;
		if (let dx12Buffer = entry.Buffer as DX12Buffer)
		{
			uint64 offset = entry.BufferOffset;
			uint64 size = entry.BufferSize > 0 ? entry.BufferSize : dx12Buffer.Size - offset;
			uint32 stride = dx12Buffer.StructureByteStride;

			D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = .();
			srvDesc.ViewDimension = .D3D12_SRV_DIMENSION_BUFFER;
			srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;

			if (stride > 0)
			{
				// Structured buffer (StructuredBuffer<T>)
				srvDesc.Format = .DXGI_FORMAT_UNKNOWN;
				srvDesc.Buffer.FirstElement = offset / stride;
				srvDesc.Buffer.NumElements = (uint32)(size / stride);
				srvDesc.Buffer.StructureByteStride = stride;
				srvDesc.Buffer.Flags = .D3D12_BUFFER_SRV_FLAG_NONE;
			}
			else
			{
				// Raw byte-address buffer (ByteAddressBuffer)
				srvDesc.Format = .DXGI_FORMAT_R32_TYPELESS;
				srvDesc.Buffer.FirstElement = offset / 4;
				srvDesc.Buffer.NumElements = (uint32)(size / 4);
				srvDesc.Buffer.StructureByteStride = 0;
				srvDesc.Buffer.Flags = .D3D12_BUFFER_SRV_FLAG_RAW;
			}

			mDevice.NativeDevice.CreateShaderResourceView(dx12Buffer.Resource, &srvDesc, destCpu);
		}
	}

	/// Creates a UAV for a read-write storage buffer.
	/// Uses structured format when StructureByteStride > 0, raw byte-address otherwise.
	private void CreateBufferUav(BindGroupEntry* entry, D3D12_CPU_DESCRIPTOR_HANDLE destCpu)
	{
		if (entry.Buffer == null)
			return;
		if (let dx12Buffer = entry.Buffer as DX12Buffer)
		{
			uint64 offset = entry.BufferOffset;
			uint64 size = entry.BufferSize > 0 ? entry.BufferSize : dx12Buffer.Size - offset;
			uint32 stride = dx12Buffer.StructureByteStride;

			D3D12_UNORDERED_ACCESS_VIEW_DESC uavDesc = .();
			uavDesc.ViewDimension = .D3D12_UAV_DIMENSION_BUFFER;

			if (stride > 0)
			{
				// Structured buffer (RWStructuredBuffer<T>)
				uavDesc.Format = .DXGI_FORMAT_UNKNOWN;
				uavDesc.Buffer.FirstElement = offset / stride;
				uavDesc.Buffer.NumElements = (uint32)(size / stride);
				uavDesc.Buffer.StructureByteStride = stride;
				uavDesc.Buffer.Flags = .D3D12_BUFFER_UAV_FLAG_NONE;
			}
			else
			{
				// Raw byte-address buffer (RWByteAddressBuffer)
				uavDesc.Format = .DXGI_FORMAT_R32_TYPELESS;
				uavDesc.Buffer.FirstElement = offset / 4;
				uavDesc.Buffer.NumElements = (uint32)(size / 4);
				uavDesc.Buffer.StructureByteStride = 0;
				uavDesc.Buffer.Flags = .D3D12_BUFFER_UAV_FLAG_RAW;
			}

			mDevice.NativeDevice.CreateUnorderedAccessView(dx12Buffer.Resource, null, &uavDesc, destCpu);
		}
	}
}
