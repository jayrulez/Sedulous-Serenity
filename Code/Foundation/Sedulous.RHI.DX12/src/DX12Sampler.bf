namespace Sedulous.RHI.DX12;

using System;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of ISampler.
class DX12Sampler : ISampler
{
	private DX12Device mDevice;
	private D3D12_CPU_DESCRIPTOR_HANDLE mCpuHandle;
	private bool mValid;
	private String mDebugName ~ delete _;

	public this(DX12Device device, SamplerDescriptor* descriptor)
	{
		mDevice = device;
		if (descriptor.Label.Ptr != null && descriptor.Label.Length > 0)
			mDebugName = new String(descriptor.Label);

		CreateSampler(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		// Sampler descriptors in CPU staging heap — no individual free needed
		mValid = false;
	}

	public bool IsValid => mValid;
	public StringView DebugName => mDebugName != null ? mDebugName : "";
	public D3D12_CPU_DESCRIPTOR_HANDLE CpuHandle => mCpuHandle;

	private void CreateSampler(SamplerDescriptor* descriptor)
	{
		D3D12_GPU_DESCRIPTOR_HANDLE gpuHandle;
		if (!mDevice.SamplerCpuHeap.Allocate(out mCpuHandle, out gpuHandle))
			return;

		bool isComparison = descriptor.Compare != .Never;

		D3D12_SAMPLER_DESC samplerDesc = .();
		samplerDesc.Filter = DX12Conversions.ToDx12Filter(
			descriptor.MinFilter, descriptor.MagFilter, descriptor.MipmapFilter, isComparison);

		// Override to anisotropic if max anisotropy > 1
		if (descriptor.MaxAnisotropy > 1)
		{
			if (isComparison)
				samplerDesc.Filter = .D3D12_FILTER_COMPARISON_ANISOTROPIC;
			else
				samplerDesc.Filter = .D3D12_FILTER_ANISOTROPIC;
		}

		samplerDesc.AddressU = DX12Conversions.ToDx12AddressMode(descriptor.AddressModeU);
		samplerDesc.AddressV = DX12Conversions.ToDx12AddressMode(descriptor.AddressModeV);
		samplerDesc.AddressW = DX12Conversions.ToDx12AddressMode(descriptor.AddressModeW);
		samplerDesc.MipLODBias = 0.0f;
		samplerDesc.MaxAnisotropy = Math.Max(1, descriptor.MaxAnisotropy);
		samplerDesc.ComparisonFunc = DX12Conversions.ToDx12CompareFunc(descriptor.Compare);
		samplerDesc.MinLOD = descriptor.LodMinClamp;
		samplerDesc.MaxLOD = descriptor.LodMaxClamp;

		// Border color
		switch (descriptor.BorderColor)
		{
		case .TransparentBlack:
			samplerDesc.BorderColor = .(0, 0, 0, 0);
		case .OpaqueBlack:
			samplerDesc.BorderColor = .(0, 0, 0, 1);
		case .OpaqueWhite:
			samplerDesc.BorderColor = .(1, 1, 1, 1);
		}

		mDevice.NativeDevice.CreateSampler(&samplerDesc, mCpuHandle);
		mValid = true;
	}
}
