namespace Sedulous.RHI.DX12;

using System;
using System.Collections;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Direct3D;
using Win32.Graphics.Dxgi.Common;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of IRenderPassEncoder.
class DX12RenderPassEncoder : IRenderPassEncoder
{
	private DX12Device mDevice;
	private ID3D12GraphicsCommandList* mCommandList;
	private DX12RenderPipeline mCurrentPipeline;
	private List<DX12Texture> mColorTextures;

	public this(DX12Device device, ID3D12GraphicsCommandList* commandList, List<DX12Texture> colorTextures)
	{
		mDevice = device;
		mCommandList = commandList;
		// Copy the texture list since the scope-allocated original will be freed
		mColorTextures = new List<DX12Texture>();
		for (let tex in colorTextures)
			mColorTextures.Add(tex);
	}

	public ~this()
	{
		delete mColorTextures;
	}

	public void SetPipeline(IRenderPipeline pipeline)
	{
		if (let dx12Pipeline = pipeline as DX12RenderPipeline)
		{
			mCurrentPipeline = dx12Pipeline;
			mCommandList.SetPipelineState(dx12Pipeline.PipelineState);
			mCommandList.SetGraphicsRootSignature(dx12Pipeline.RootSignature);
			mCommandList.IASetPrimitiveTopology(dx12Pipeline.Topology);
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
					mCommandList.SetGraphicsRootDescriptorTable((uint32)rootParam, dx12BindGroup.CbvSrvUavGpuHandle);
			}

			// Bind descriptor table for samplers
			if (dx12BindGroup.HasSampler)
			{
				let rootParam = layout.GetSamplerRootParam((int)index);
				if (rootParam >= 0)
					mCommandList.SetGraphicsRootDescriptorTable((uint32)rootParam, dx12BindGroup.SamplerGpuHandle);
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
					mCommandList.SetGraphicsRootConstantBufferView((uint32)rootParam, gpuVA + offset);
				}
			}
		}
	}

	public void SetVertexBuffer(uint32 slot, IBuffer buffer, uint64 offset = 0)
	{
		if (let dx12Buffer = buffer as DX12Buffer)
		{
			D3D12_VERTEX_BUFFER_VIEW vbView = .();
			vbView.BufferLocation = dx12Buffer.GpuVirtualAddress + offset;
			vbView.SizeInBytes = (uint32)(dx12Buffer.Size - offset);
			// Stride comes from the pipeline's vertex buffer layout
			if (mCurrentPipeline != null)
				vbView.StrideInBytes = mCurrentPipeline.GetVertexStride(slot);
			mCommandList.IASetVertexBuffers(slot, 1, &vbView);
		}
	}

	public void SetIndexBuffer(IBuffer buffer, IndexFormat format, uint64 offset = 0)
	{
		if (let dx12Buffer = buffer as DX12Buffer)
		{
			D3D12_INDEX_BUFFER_VIEW ibView = .();
			ibView.BufferLocation = dx12Buffer.GpuVirtualAddress + offset;
			ibView.SizeInBytes = (uint32)(dx12Buffer.Size - offset);
			ibView.Format = DX12Conversions.ToDxgiFormat(format);
			mCommandList.IASetIndexBuffer(&ibView);
		}
	}

	public void SetViewport(float x, float y, float width, float height, float minDepth, float maxDepth)
	{
		D3D12_VIEWPORT viewport = .();
		viewport.TopLeftX = x;
		viewport.TopLeftY = y;
		viewport.Width = width;
		viewport.Height = height;
		viewport.MinDepth = minDepth;
		viewport.MaxDepth = maxDepth;
		mCommandList.RSSetViewports(1, &viewport);
	}

	public void SetScissorRect(int32 x, int32 y, uint32 width, uint32 height)
	{
		D3D12_RECT rect = .();
		rect.left = x;
		rect.top = y;
		rect.right = x + (int32)width;
		rect.bottom = y + (int32)height;
		mCommandList.RSSetScissorRects(1, &rect);
	}

	public void SetBlendConstant(float r, float g, float b, float a)
	{
		float[4] blendFactor;
		blendFactor[0] = r;
		blendFactor[1] = g;
		blendFactor[2] = b;
		blendFactor[3] = a;
		mCommandList.OMSetBlendFactor(&blendFactor);
	}

	public void SetStencilReference(uint32 reference)
	{
		mCommandList.OMSetStencilRef(reference);
	}

	public void Draw(uint32 vertexCount, uint32 instanceCount = 1, uint32 firstVertex = 0, uint32 firstInstance = 0)
	{
		mCommandList.DrawInstanced(vertexCount, instanceCount, firstVertex, firstInstance);
	}

	public void DrawIndexed(uint32 indexCount, uint32 instanceCount = 1, uint32 firstIndex = 0, int32 baseVertex = 0, uint32 firstInstance = 0)
	{
		mCommandList.DrawIndexedInstanced(indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
	}

	public void DrawIndirect(IBuffer indirectBuffer, uint64 indirectOffset)
	{
		if (let dx12Buffer = indirectBuffer as DX12Buffer)
		{
			mCommandList.ExecuteIndirect(
				mDevice.DrawSignature,
				1,
				dx12Buffer.Resource,
				indirectOffset,
				null, 0);
		}
	}

	public void DrawIndexedIndirect(IBuffer indirectBuffer, uint64 indirectOffset)
	{
		if (let dx12Buffer = indirectBuffer as DX12Buffer)
		{
			mCommandList.ExecuteIndirect(
				mDevice.DrawIndexedSignature,
				1,
				dx12Buffer.Resource,
				indirectOffset,
				null, 0);
		}
	}

	public void End()
	{
		for (let tex in mColorTextures)
		{
			// Swap chain back buffers must go to PRESENT state; other targets to shader read
			let targetState = tex.IsSwapChainTexture
				? D3D12_RESOURCE_STATES.D3D12_RESOURCE_STATE_PRESENT
				: (D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

			D3D12_RESOURCE_BARRIER barrier;
			if (tex.TransitionTo(targetState, out barrier))
				mCommandList.ResourceBarrier(1, &barrier);
		}
	}
}
