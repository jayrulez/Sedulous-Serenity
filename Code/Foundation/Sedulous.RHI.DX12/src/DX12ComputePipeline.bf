namespace Sedulous.RHI.DX12;

using System;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Foundation;
using Sedulous.RHI;

/// DX12 implementation of IComputePipeline.
class DX12ComputePipeline : IComputePipeline
{
	private DX12Device mDevice;
	private ID3D12PipelineState* mPipelineState;
	private DX12PipelineLayout mLayout;

	public this(DX12Device device, ComputePipelineDescriptor* descriptor)
	{
		mDevice = device;
		if (let layout = descriptor.Layout as DX12PipelineLayout)
		{
			mLayout = layout;
			CreatePipeline(descriptor);
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mPipelineState != null)
		{
			mPipelineState.Release();
			mPipelineState = null;
		}
	}

	public bool IsValid => mPipelineState != null;
	public IPipelineLayout Layout => mLayout;
	public ID3D12PipelineState* PipelineState => mPipelineState;
	public ID3D12RootSignature* RootSignature => mLayout?.RootSignature;
	public DX12PipelineLayout PipelineLayout => mLayout;

	private void CreatePipeline(ComputePipelineDescriptor* descriptor)
	{
		let shaderModule = descriptor.Compute.Module as DX12ShaderModule;
		if (shaderModule == null || mLayout == null)
			return;

		D3D12_COMPUTE_PIPELINE_STATE_DESC desc = .();
		desc.pRootSignature = mLayout.RootSignature;
		desc.CS = shaderModule.GetBytecode();
		desc.NodeMask = 0;
		desc.Flags = .D3D12_PIPELINE_STATE_FLAG_NONE;

		HRESULT hr = mDevice.NativeDevice.CreateComputePipelineState(
			&desc,
			ID3D12PipelineState.IID,
			(void**)&mPipelineState);

		if (!SUCCEEDED(hr))
			mPipelineState = null;
	}
}
