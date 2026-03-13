namespace Sedulous.RHI.DX12;

using System;
using Win32;
using Win32.Graphics.Direct3D12;
using Sedulous.RHI;

/// DX12 implementation of ICommandBuffer.
/// Owns a closed command list and its command allocator.
class DX12CommandBuffer : ICommandBuffer
{
	private ID3D12GraphicsCommandList* mCommandList;
	private ID3D12CommandAllocator* mAllocator;

	public this(ID3D12GraphicsCommandList* commandList, ID3D12CommandAllocator* allocator)
	{
		mCommandList = commandList;
		mAllocator = allocator;
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mCommandList != null)
		{
			mCommandList.Release();
			mCommandList = null;
		}
		if (mAllocator != null)
		{
			mAllocator.Release();
			mAllocator = null;
		}
	}

	public bool IsValid => mCommandList != null;
	public ID3D12GraphicsCommandList* CommandList => mCommandList;
	public ID3D12CommandAllocator* Allocator => mAllocator;
}
