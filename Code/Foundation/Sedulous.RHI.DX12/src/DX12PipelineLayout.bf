namespace Sedulous.RHI.DX12;

using System;
using System.Collections;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Direct3D;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of IPipelineLayout. Creates an ID3D12RootSignature.
class DX12PipelineLayout : IPipelineLayout
{
	public const int MaxBindGroups = 8;
	public const int MaxDynamicPerGroup = 4;

	private DX12Device mDevice;
	private ID3D12RootSignature* mRootSignature;
	private List<DX12BindGroupLayout> mBindGroupLayouts = new .() ~ delete _;

	// Maps bind group index -> root parameter index (-1 if bind group has none of that type)
	private int32[MaxBindGroups] mCbvSrvUavRootParam;
	private int32[MaxBindGroups] mSamplerRootParam;

	// Dynamic offset entries get individual root CBV/SRV/UAV parameters
	private int32[MaxBindGroups * MaxDynamicPerGroup] mDynamicRootParams;
	private uint32[MaxBindGroups] mDynamicParamCounts;

	private uint32 mRootParameterCount;

	public this(DX12Device device, PipelineLayoutDescriptor* descriptor)
	{
		mDevice = device;
		for (int i = 0; i < MaxBindGroups; i++)
		{
			mCbvSrvUavRootParam[i] = -1;
			mSamplerRootParam[i] = -1;
			mDynamicParamCounts[i] = 0;
		}
		for (int i = 0; i < MaxBindGroups * MaxDynamicPerGroup; i++)
			mDynamicRootParams[i] = -1;
		CreateRootSignature(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mRootSignature != null)
		{
			mRootSignature.Release();
			mRootSignature = null;
		}
		mBindGroupLayouts.Clear();
	}

	public bool IsValid => mRootSignature != null;
	public ID3D12RootSignature* RootSignature => mRootSignature;
	public Span<DX12BindGroupLayout> BindGroupLayouts => mBindGroupLayouts;
	public uint32 RootParameterCount => mRootParameterCount;

	/// Gets the root parameter index for a bind group's CBV/SRV/UAV descriptor table (-1 if none).
	public int32 GetCbvSrvUavRootParam(int bindGroupIndex) => mCbvSrvUavRootParam[bindGroupIndex];

	/// Gets the root parameter index for a bind group's Sampler descriptor table (-1 if none).
	public int32 GetSamplerRootParam(int bindGroupIndex) => mSamplerRootParam[bindGroupIndex];

	/// Gets the root parameter index for a dynamic offset entry (-1 if none).
	public int32 GetDynamicRootParam(int bindGroupIndex, int dynamicIndex) => mDynamicRootParams[bindGroupIndex * MaxDynamicPerGroup + dynamicIndex];

	/// Gets the number of dynamic root parameters for a bind group.
	public uint32 GetDynamicParamCount(int bindGroupIndex) => mDynamicParamCounts[bindGroupIndex];

	private void CreateRootSignature(PipelineLayoutDescriptor* descriptor)
	{
		int layoutCount = descriptor.BindGroupLayouts.Length;

		// Collect bind group layouts
		for (int i = 0; i < layoutCount; i++)
		{
			if (let dx12Layout = descriptor.BindGroupLayouts[i] as DX12BindGroupLayout)
				mBindGroupLayouts.Add(dx12Layout);
			else
				return;
		}

		// First pass: count total descriptor ranges and dynamic entries
		int totalCbvSrvUavRanges = 0;
		int totalSamplerRanges = 0;
		int totalDynamicEntries = 0;
		for (let layout in mBindGroupLayouts)
		{
			for (let entry in layout.Entries)
			{
				if (entry.HasDynamicOffset)
				{
					totalDynamicEntries++;
					continue;
				}
				if (DX12Conversions.IsSamplerBinding(entry.Type))
					totalSamplerRanges++;
				else
					totalCbvSrvUavRanges++;
			}
		}

		// Allocate all ranges on the scope stack (stable pointers)
		D3D12_DESCRIPTOR_RANGE* cbvSrvUavRanges = scope D3D12_DESCRIPTOR_RANGE[Math.Max(1, totalCbvSrvUavRanges)]*;
		D3D12_DESCRIPTOR_RANGE* samplerRanges = scope D3D12_DESCRIPTOR_RANGE[Math.Max(1, totalSamplerRanges)]*;
		int cbvSrvUavIdx = 0;
		int samplerIdx = 0;

		// Each bind group gets up to 2 table params + N dynamic params
		int maxRootParams = layoutCount * 2 + totalDynamicEntries;
		D3D12_ROOT_PARAMETER* rootParams = scope D3D12_ROOT_PARAMETER[Math.Max(1, maxRootParams)]*;
		uint32 rootParamIdx = 0;

		for (int bgIdx = 0; bgIdx < mBindGroupLayouts.Count; bgIdx++)
		{
			let layout = mBindGroupLayouts[bgIdx];

			// Non-dynamic CBV/SRV/UAV entries → descriptor table
			uint32 tableCount = layout.CbvSrvUavTableCount;
			if (tableCount > 0)
			{
				int rangeStart = cbvSrvUavIdx;

				for (let entry in layout.Entries)
				{
					if (DX12Conversions.IsSamplerBinding(entry.Type) || entry.HasDynamicOffset)
						continue;

					D3D12_DESCRIPTOR_RANGE range = .();
					range.RangeType = DX12Conversions.ToDx12RangeType(entry.Type);
					range.NumDescriptors = 1;
					range.BaseShaderRegister = entry.Binding;
					range.RegisterSpace = (uint32)bgIdx;
					range.OffsetInDescriptorsFromTableStart = 0xFFFFFFFF; // D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND

					cbvSrvUavRanges[cbvSrvUavIdx++] = range;
				}

				D3D12_ROOT_PARAMETER param = .();
				param.ParameterType = .D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
				param.ShaderVisibility = .D3D12_SHADER_VISIBILITY_ALL;
				param.DescriptorTable.NumDescriptorRanges = (uint32)(cbvSrvUavIdx - rangeStart);
				param.DescriptorTable.pDescriptorRanges = &cbvSrvUavRanges[rangeStart];

				mCbvSrvUavRootParam[bgIdx] = (int32)rootParamIdx;
				rootParams[rootParamIdx++] = param;
			}

			// Dynamic offset entries → individual root descriptors
			int dynamicIdx = 0;
			for (let entry in layout.Entries)
			{
				if (!entry.HasDynamicOffset || DX12Conversions.IsSamplerBinding(entry.Type))
					continue;

				D3D12_ROOT_PARAMETER param = .();
				switch (entry.Type)
				{
				case .UniformBuffer:
					param.ParameterType = .D3D12_ROOT_PARAMETER_TYPE_CBV;
				case .StorageBuffer:
					param.ParameterType = .D3D12_ROOT_PARAMETER_TYPE_SRV;
				case .StorageBufferReadWrite:
					param.ParameterType = .D3D12_ROOT_PARAMETER_TYPE_UAV;
				default:
					continue;
				}
				param.ShaderVisibility = .D3D12_SHADER_VISIBILITY_ALL;
				param.Descriptor.ShaderRegister = entry.Binding;
				param.Descriptor.RegisterSpace = (uint32)bgIdx;

				mDynamicRootParams[bgIdx * MaxDynamicPerGroup + dynamicIdx] = (int32)rootParamIdx;
				rootParams[rootParamIdx++] = param;
				dynamicIdx++;
			}
			mDynamicParamCounts[bgIdx] = (uint32)dynamicIdx;

			// Sampler descriptor table
			if (layout.SamplerCount > 0)
			{
				int rangeStart = samplerIdx;

				for (let entry in layout.Entries)
				{
					if (!DX12Conversions.IsSamplerBinding(entry.Type))
						continue;

					D3D12_DESCRIPTOR_RANGE range = .();
					range.RangeType = .D3D12_DESCRIPTOR_RANGE_TYPE_SAMPLER;
					range.NumDescriptors = 1;
					range.BaseShaderRegister = entry.Binding;
					range.RegisterSpace = (uint32)bgIdx;
					range.OffsetInDescriptorsFromTableStart = 0xFFFFFFFF;

					samplerRanges[samplerIdx++] = range;
				}

				D3D12_ROOT_PARAMETER param = .();
				param.ParameterType = .D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
				param.ShaderVisibility = .D3D12_SHADER_VISIBILITY_ALL;
				param.DescriptorTable.NumDescriptorRanges = (uint32)(samplerIdx - rangeStart);
				param.DescriptorTable.pDescriptorRanges = &samplerRanges[rangeStart];

				mSamplerRootParam[bgIdx] = (int32)rootParamIdx;
				rootParams[rootParamIdx++] = param;
			}
		}

		mRootParameterCount = rootParamIdx;

		D3D12_ROOT_SIGNATURE_DESC desc = .();
		desc.NumParameters = rootParamIdx;
		desc.pParameters = rootParams;
		desc.NumStaticSamplers = 0;
		desc.pStaticSamplers = null;
		desc.Flags = .D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;

		ID3DBlob* signatureBlob = null;
		ID3DBlob* errorBlob = null;

		HRESULT hr = D3D12SerializeRootSignature(&desc, .D3D_ROOT_SIGNATURE_VERSION_1, &signatureBlob, &errorBlob);

		if (!SUCCEEDED(hr))
		{
			if (errorBlob != null)
				errorBlob.Release();
			if (signatureBlob != null)
				signatureBlob.Release();
			return;
		}

		hr = mDevice.NativeDevice.CreateRootSignature(
			0,
			signatureBlob.GetBufferPointer(),
			signatureBlob.GetBufferSize(),
			ID3D12RootSignature.IID,
			(void**)&mRootSignature);

		if (signatureBlob != null)
			signatureBlob.Release();
		if (errorBlob != null)
			errorBlob.Release();

		if (!SUCCEEDED(hr))
			mRootSignature = null;
	}
}
