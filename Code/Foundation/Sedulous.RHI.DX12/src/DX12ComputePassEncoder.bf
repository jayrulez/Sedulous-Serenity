namespace Sedulous.RHI.DX12;

using System;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of IComputePassEncoder.
class DX12ComputePassEncoder : IComputePassEncoder
{
	private DX12Device mDevice;
	private ID3D12GraphicsCommandList* mCommandList;
	private DX12ComputePipeline mCurrentPipeline;

	public this(DX12Device device, ID3D12GraphicsCommandList* commandList)
	{
		mDevice = device;
		mCommandList = commandList;
	}

	public void SetPipeline(IComputePipeline pipeline)
	{
		if (let dx12Pipeline = pipeline as DX12ComputePipeline)
		{
			mCurrentPipeline = dx12Pipeline;
			mCommandList.SetPipelineState(dx12Pipeline.PipelineState);
			mCommandList.SetComputeRootSignature(dx12Pipeline.RootSignature);
		}
	}

	public void SetBindGroup(uint32 index, IBindGroup bindGroup, Span<uint32> dynamicOffsets = default)
	{
		if (let dx12BindGroup = bindGroup as DX12BindGroup)
		{
			if (mCurrentPipeline == null)
				return;

			let layout = mCurrentPipeline.PipelineLayout;
			if (layout == null)
				return;

			// Bind descriptor table for non-dynamic CBV/SRV/UAV entries
			if (dx12BindGroup.HasCbvSrvUav)
			{
				let rootParam = layout.GetCbvSrvUavRootParam((int)index);
				if (rootParam >= 0)
					mCommandList.SetComputeRootDescriptorTable((uint32)rootParam, dx12BindGroup.CbvSrvUavGpuHandle);
			}

			// Bind descriptor table for samplers
			if (dx12BindGroup.HasSampler)
			{
				let rootParam = layout.GetSamplerRootParam((int)index);
				if (rootParam >= 0)
					mCommandList.SetComputeRootDescriptorTable((uint32)rootParam, dx12BindGroup.SamplerGpuHandle);
			}

			// Bind dynamic offset entries via root CBV/SRV/UAV
			uint32 dynamicCount = Math.Min(dx12BindGroup.DynamicCount, layout.GetDynamicParamCount((int)index));
			for (uint32 i = 0; i < dynamicCount; i++)
			{
				let rootParam = layout.GetDynamicRootParam((int)index, (int)i);
				if (rootParam >= 0)
				{
					uint64 gpuVA = dx12BindGroup.GetDynamicBufferGpuVA((int)i);
					uint64 offset = (i < dynamicOffsets.Length) ? dynamicOffsets[(int)i] : 0;
					mCommandList.SetComputeRootConstantBufferView((uint32)rootParam, gpuVA + offset);
				}
			}
		}
	}

	public void Dispatch(uint32 workgroupCountX, uint32 workgroupCountY = 1, uint32 workgroupCountZ = 1)
	{
		mCommandList.Dispatch(workgroupCountX, workgroupCountY, workgroupCountZ);
	}

	public void DispatchIndirect(IBuffer indirectBuffer, uint64 indirectOffset)
	{
		if (let dx12Buffer = indirectBuffer as DX12Buffer)
		{
			mCommandList.ExecuteIndirect(
				mDevice.DispatchSignature,
				1,
				dx12Buffer.Resource,
				indirectOffset,
				null, 0);
		}
	}

	public void ComputeBarrier()
	{
		// UAV barrier — ensures all prior UAV writes are visible to subsequent dispatches
		D3D12_RESOURCE_BARRIER barrier = .();
		barrier.Type = .D3D12_RESOURCE_BARRIER_TYPE_UAV;
		barrier.Flags = .D3D12_RESOURCE_BARRIER_FLAG_NONE;
		barrier.UAV.pResource = null; // null = barrier on all UAV resources
		mCommandList.ResourceBarrier(1, &barrier);
	}

	public void End()
	{
		// Nothing to do — compute passes don't need render target transitions
	}
}
