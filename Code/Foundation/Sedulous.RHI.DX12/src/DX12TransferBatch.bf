namespace Sedulous.RHI.DX12;

using System;
using System.Collections;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Dxgi.Common;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of ITransferBatch.
/// Batches GPU transfer operations into a single command list submission.
class DX12TransferBatch : ITransferBatch
{
	private DX12Device mDevice;
	private DX12Queue mQueue;
	private ID3D12CommandAllocator* mAllocator;
	private ID3D12GraphicsCommandList* mCommandList;
	private List<IBuffer> mStagingBuffers = new .() ~ delete _;
	private int mTransferCount;

	public this(DX12Device device, DX12Queue queue)
	{
		mDevice = device;
		mQueue = queue;
	}

	public ~this()
	{
		Cleanup();
		delete mStagingBuffers;
	}

	public void WriteTexture(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout,
		Extent3D* writeSize, uint32 mipLevel = 0, uint32 arrayLayer = 0)
	{
		let dx12Texture = texture as DX12Texture;
		if (dx12Texture == null || data.Length == 0 || dataLayout == null || writeSize == null)
			return;

		// Create staging buffer
		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				MemoryAccess = .CpuToGpu
			};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
		{
			if (let dx12Staging = stagingBuffer as DX12Buffer)
			{
				let ptr = dx12Staging.Map();
				if (ptr != null)
				{
					Internal.MemCpy(ptr, data.Ptr, data.Length);
					dx12Staging.Unmap();
				}

				EnsureCmdList();
				if (mCommandList != null)
				{
					// Transition texture to copy dest
					D3D12_RESOURCE_BARRIER barrier;
					if (dx12Texture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_DEST, out barrier))
						mCommandList.ResourceBarrier(1, &barrier);

					D3D12_TEXTURE_COPY_LOCATION dst = .();
					dst.pResource = dx12Texture.Resource;
					dst.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
					dst.SubresourceIndex = mipLevel + arrayLayer * dx12Texture.MipLevelCount;

					D3D12_TEXTURE_COPY_LOCATION src = .();
					src.pResource = dx12Staging.Resource;
					src.Type = .D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
					src.PlacedFootprint.Offset = dataLayout.Offset;
					src.PlacedFootprint.Footprint.Format = DX12Conversions.ToDxgiFormat(dx12Texture.Format);
					src.PlacedFootprint.Footprint.Width = writeSize.Width;
					src.PlacedFootprint.Footprint.Height = writeSize.Height;
					src.PlacedFootprint.Footprint.Depth = writeSize.Depth;
					src.PlacedFootprint.Footprint.RowPitch = dataLayout.BytesPerRow;

					mCommandList.CopyTextureRegion(&dst, 0, 0, 0, &src, null);

					// Transition to shader read
					if (dx12Texture.TransitionTo((D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE), out barrier))
						mCommandList.ResourceBarrier(1, &barrier);

					mTransferCount++;
				}
			}

			mStagingBuffers.Add(stagingBuffer);
		}
	}

	public void WriteBuffer(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let dx12Buffer = buffer as DX12Buffer;
		if (dx12Buffer == null || data.Length == 0)
			return;

		// Create staging buffer
		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				MemoryAccess = .CpuToGpu
			};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
		{
			if (let dx12Staging = stagingBuffer as DX12Buffer)
			{
				let ptr = dx12Staging.Map();
				if (ptr != null)
				{
					Internal.MemCpy(ptr, data.Ptr, data.Length);
					dx12Staging.Unmap();
				}

				EnsureCmdList();
				if (mCommandList != null)
				{
					D3D12_RESOURCE_BARRIER barrier;
					if (dx12Buffer.TransitionTo(.D3D12_RESOURCE_STATE_COPY_DEST, out barrier))
						mCommandList.ResourceBarrier(1, &barrier);

					mCommandList.CopyBufferRegion(dx12Buffer.Resource, offset, dx12Staging.Resource, 0, (uint64)data.Length);

					mTransferCount++;
				}
			}

			mStagingBuffers.Add(stagingBuffer);
		}
	}

	public void Submit()
	{
		if (mCommandList == null || mTransferCount == 0)
			return;

		Console.WriteLine(scope $"[DX12] TransferBatch: submitting {mTransferCount} transfers");

		// Close and execute
		mCommandList.Close();

		ID3D12CommandList*[1] cmdLists = .((ID3D12CommandList*)mCommandList);
		mQueue.NativeQueue.ExecuteCommandLists(1, &cmdLists);

		// Wait for completion
		mQueue.WaitIdle();

		// Clean up
		Cleanup();
	}

	// ===== Internal =====

	private void EnsureCmdList()
	{
		if (mCommandList != null)
			return;

		HRESULT hr = mDevice.NativeDevice.CreateCommandAllocator(
			.D3D12_COMMAND_LIST_TYPE_DIRECT,
			ID3D12CommandAllocator.IID,
			(void**)&mAllocator);

		if (!SUCCEEDED(hr))
			return;

		hr = mDevice.NativeDevice.CreateCommandList(
			0,
			.D3D12_COMMAND_LIST_TYPE_DIRECT,
			mAllocator,
			null,
			ID3D12GraphicsCommandList.IID,
			(void**)&mCommandList);

		if (!SUCCEEDED(hr))
		{
			mAllocator.Release();
			mAllocator = null;
		}
	}

	private void Cleanup()
	{
		if (mCommandList != null) { mCommandList.Release(); mCommandList = null; }
		if (mAllocator != null) { mAllocator.Release(); mAllocator = null; }

		for (let stagingBuffer in mStagingBuffers)
			delete stagingBuffer;
		mStagingBuffers.Clear();

		mTransferCount = 0;
	}
}
