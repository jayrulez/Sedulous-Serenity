namespace Sedulous.RHI.DX12;

using System;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Foundation;
using Win32.System.Threading;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of IQueue.
class DX12Queue : IQueue
{
	private DX12Device mDevice;
	private ID3D12CommandQueue* mQueue;

	// Inline fence for synchronous operations
	private ID3D12Fence* mInlineFence;
	private HANDLE mInlineEvent;
	private uint64 mInlineFenceValue;

	public this(DX12Device device, ID3D12CommandQueue* queue)
	{
		mDevice = device;
		mQueue = queue;
		CreateInlineFence();
	}

	public ~this()
	{
		if (mInlineEvent != 0)
		{
			CloseHandle(mInlineEvent);
			mInlineEvent = default;
		}
		if (mInlineFence != null) { mInlineFence.Release(); mInlineFence = null; }
		if (mQueue != null) { mQueue.Release(); mQueue = null; }
	}

	public ID3D12CommandQueue* NativeQueue => mQueue;

	public void Submit(Span<ICommandBuffer> commandBuffers)
	{
		if (commandBuffers.Length == 0 || mQueue == null)
			return;

		ID3D12CommandList** cmdLists = scope ID3D12CommandList*[commandBuffers.Length]*;
		int count = 0;

		for (let cmdBuffer in commandBuffers)
		{
			if (let dx12Cmd = cmdBuffer as DX12CommandBuffer)
			{
				if (dx12Cmd.IsValid)
					cmdLists[count++] = (ID3D12CommandList*)dx12Cmd.CommandList;
			}
		}

		if (count > 0)
			mQueue.ExecuteCommandLists((uint32)count, cmdLists);
	}

	public void Submit(ICommandBuffer commandBuffer)
	{
		if (commandBuffer != null)
		{
			ICommandBuffer[1] buffers = .(commandBuffer);
			Submit(buffers);
		}
	}

	public void Submit(Span<ICommandBuffer> commandBuffers, ISwapChain swapChain)
	{
		// DX12 doesn't use semaphores for swap chain sync — just submit normally
		// Swap chain sync is handled by fence in DX12SwapChain
		Submit(commandBuffers);
	}

	public void Submit(ICommandBuffer commandBuffer, ISwapChain swapChain)
	{
		ICommandBuffer[1] buffers = default;
		if (commandBuffer != null)
			buffers = .(commandBuffer);
		Submit(Span<ICommandBuffer>(&buffers, commandBuffer != null ? 1 : 0), swapChain);
	}

	public void WriteMappedBuffer(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let dx12Buffer = buffer as DX12Buffer;
		if (dx12Buffer == null || !dx12Buffer.IsValid || data.Length == 0)
			return;

		let ptr = dx12Buffer.Map();
		if (ptr != null)
		{
			Internal.MemCpy((uint8*)ptr + offset, data.Ptr, data.Length);
			dx12Buffer.Unmap();
		}
		else
		{
			Runtime.FatalError("WriteMappedBuffer called on non-mappable buffer. Use WriteStagedBufferSync for device-local buffers.");
		}
	}

	public void WriteStagedBufferSync(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let dx12Buffer = buffer as DX12Buffer;
		if (dx12Buffer == null || !dx12Buffer.IsValid || data.Length == 0)
			return;

		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				Memory = .CpuToGpu
			};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
		{
			if (let dx12Staging = stagingBuffer as DX12Buffer)
			{
				let stagingPtr = dx12Staging.Map();
				if (stagingPtr != null)
				{
					Internal.MemCpy(stagingPtr, data.Ptr, data.Length);
					dx12Staging.Unmap();
				}

				ExecuteOneShotCopy(new (cmdList) =>
					{
						D3D12_RESOURCE_BARRIER barrier;
						if (dx12Buffer.TransitionTo(.D3D12_RESOURCE_STATE_COPY_DEST, out barrier))
							cmdList.ResourceBarrier(1, &barrier);

						cmdList.CopyBufferRegion(dx12Buffer.Resource, offset, dx12Staging.Resource, 0, (uint64)data.Length);
					});
			}

			delete stagingBuffer;
		}
	}

	public void WriteTextureSync(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout, Extent3D* writeSize, uint32 mipLevel = 0, uint32 arrayLayer = 0)
	{
		let dx12Texture = texture as DX12Texture;
		if (dx12Texture == null || data.Length == 0 || dataLayout == null || writeSize == null)
			return;

		// Create staging buffer
		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopySrc,
				Memory = .CpuToGpu
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

				let capturedMipLevel = mipLevel;
				let capturedArrayLayer = arrayLayer;

				ExecuteOneShotCopy(new (cmdList) =>
					{
						D3D12_RESOURCE_BARRIER barrier;
						if (dx12Texture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_DEST, out barrier))
							cmdList.ResourceBarrier(1, &barrier);

						D3D12_TEXTURE_COPY_LOCATION dst = .();
						dst.pResource = dx12Texture.Resource;
						dst.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
						dst.SubresourceIndex = capturedMipLevel + capturedArrayLayer * dx12Texture.MipLevelCount;

						D3D12_TEXTURE_COPY_LOCATION src = .();
						src.pResource = dx12Staging.Resource;
						src.Type = .D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
						src.PlacedFootprint.Offset = dataLayout.Offset;
						src.PlacedFootprint.Footprint.Format = DX12Conversions.ToDxgiFormat(dx12Texture.Format);
						src.PlacedFootprint.Footprint.Width = writeSize.Width;
						src.PlacedFootprint.Footprint.Height = writeSize.Height;
						src.PlacedFootprint.Footprint.Depth = writeSize.Depth;
						src.PlacedFootprint.Footprint.RowPitch = dataLayout.BytesPerRow;

						cmdList.CopyTextureRegion(&dst, 0, 0, 0, &src, null);

						// Transition to shader read
						if (dx12Texture.TransitionTo((D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE), out barrier))
							cmdList.ResourceBarrier(1, &barrier);
					});
			}

			delete stagingBuffer;
		}
	}

	public void ReadMappedBuffer(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let dx12Buffer = buffer as DX12Buffer;
		if (dx12Buffer == null || data.Length == 0)
			return;

		let ptr = dx12Buffer.Map();
		if (ptr != null)
		{
			Internal.MemCpy(data.Ptr, (uint8*)ptr + offset, data.Length);
			dx12Buffer.Unmap();
		}
		else
		{
			Runtime.FatalError("ReadMappedBuffer called on non-mappable buffer. Use ReadStagedBufferSync for device-local buffers.");
		}
	}

	public void ReadStagedBufferSync(IBuffer buffer, uint64 offset, Span<uint8> data)
	{
		let dx12Buffer = buffer as DX12Buffer;
		if (dx12Buffer == null || data.Length == 0)
			return;

		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopyDst,
				Memory = .GpuToCpu
			};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
		{
			if (let dx12Staging = stagingBuffer as DX12Buffer)
			{
				ExecuteOneShotCopy(new (cmdList) =>
					{
						D3D12_RESOURCE_BARRIER barrier;
						if (dx12Buffer.TransitionTo(.D3D12_RESOURCE_STATE_COPY_SOURCE, out barrier))
							cmdList.ResourceBarrier(1, &barrier);

						cmdList.CopyBufferRegion(dx12Staging.Resource, 0, dx12Buffer.Resource, offset, (uint64)data.Length);
					});

				let ptr = dx12Staging.Map();
				if (ptr != null)
				{
					Internal.MemCpy(data.Ptr, ptr, data.Length);
					dx12Staging.Unmap();
				}
			}

			delete stagingBuffer;
		}
	}

	public void ReadTextureSync(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout, Extent3D* readSize, uint32 mipLevel = 0, uint32 arrayLayer = 0)
	{
		let dx12Texture = texture as DX12Texture;
		if (dx12Texture == null || data.Length == 0 || dataLayout == null || readSize == null)
			return;

		BufferDesc stagingDesc = .()
			{
				Size = (uint64)data.Length,
				Usage = .CopyDst,
				Memory = .GpuToCpu
			};

		if (mDevice.CreateBuffer(stagingDesc) case .Ok(let stagingBuffer))
		{
			if (let dx12Staging = stagingBuffer as DX12Buffer)
			{
				let capturedMipLevel = mipLevel;
				let capturedArrayLayer = arrayLayer;

				ExecuteOneShotCopy(new (cmdList) =>
					{
						D3D12_RESOURCE_BARRIER barrier;
						if (dx12Texture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_SOURCE, out barrier))
							cmdList.ResourceBarrier(1, &barrier);

						D3D12_TEXTURE_COPY_LOCATION src = .();
						src.pResource = dx12Texture.Resource;
						src.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
						src.SubresourceIndex = capturedMipLevel + capturedArrayLayer * dx12Texture.MipLevelCount;

						D3D12_TEXTURE_COPY_LOCATION dst = .();
						dst.pResource = dx12Staging.Resource;
						dst.Type = .D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
						dst.PlacedFootprint.Offset = dataLayout.Offset;
						dst.PlacedFootprint.Footprint.Format = DX12Conversions.ToDxgiFormat(dx12Texture.Format);
						dst.PlacedFootprint.Footprint.Width = readSize.Width;
						dst.PlacedFootprint.Footprint.Height = readSize.Height;
						dst.PlacedFootprint.Footprint.Depth = readSize.Depth;
						dst.PlacedFootprint.Footprint.RowPitch = dataLayout.BytesPerRow;

						cmdList.CopyTextureRegion(&dst, 0, 0, 0, &src, null);

						// Transition back to shader read
						if (dx12Texture.TransitionTo((D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE), out barrier))
							cmdList.ResourceBarrier(1, &barrier);
					});

				let ptr = dx12Staging.Map();
				if (ptr != null)
				{
					Internal.MemCpy(data.Ptr, ptr, data.Length);
					dx12Staging.Unmap();
				}
			}

			delete stagingBuffer;
		}
	}

	public void WaitIdle()
	{
		if (mQueue == null || mInlineFence == null)
			return;

		Console.WriteLine("[GPU Sync] WaitIdle - D3D12 fence");
		mInlineFenceValue++;
		mQueue.Signal(mInlineFence, mInlineFenceValue);
		if (mInlineFence.GetCompletedValue() < mInlineFenceValue)
		{
			mInlineFence.SetEventOnCompletion(mInlineFenceValue, mInlineEvent);
			WaitForSingleObjectEx(mInlineEvent, uint32.MaxValue, FALSE);
		}
	}

	public Result<ITransferBatch> CreateTransferBatch()
	{
		return .Ok(new DX12TransferBatch(mDevice, this));
	}

	public float GetTimestampPeriod()
	{
		if (mQueue == null)
			return 1.0f;

		uint64 frequency = 0;
		if (SUCCEEDED(mQueue.GetTimestampFrequency(&frequency)) && frequency > 0)
			return 1000000000.0f / (float)frequency; // Convert frequency to nanoseconds per tick
		return 1.0f;
	}

	// ===== Internal =====

	/// Signals the queue's fence and returns the fence value used.
	public void SignalFence(DX12Fence fence)
	{
		let value = fence.IncrementAndGetValue();
		mQueue.Signal(fence.NativeFence, value);
	}

	private void CreateInlineFence()
	{
		mDevice.NativeDevice.CreateFence(0, .D3D12_FENCE_FLAG_NONE, ID3D12Fence.IID, (void**)&mInlineFence);
		mInlineEvent = CreateEventW(null, FALSE, FALSE, null);
	}

	/// Executes a one-shot command list with a delegate for recording, then waits for completion.
	private void ExecuteOneShotCopy(delegate void(ID3D12GraphicsCommandList*) recordFunc)
	{
		ID3D12CommandAllocator* allocator = null;
		ID3D12GraphicsCommandList* cmdList = null;

		mDevice.NativeDevice.CreateCommandAllocator(
			.D3D12_COMMAND_LIST_TYPE_DIRECT,
			ID3D12CommandAllocator.IID,
			(void**)&allocator);

		if (allocator == null)
		{
			delete recordFunc;
			return;
		}

		mDevice.NativeDevice.CreateCommandList(
			0, .D3D12_COMMAND_LIST_TYPE_DIRECT, allocator, null,
			ID3D12GraphicsCommandList.IID, (void**)&cmdList);

		if (cmdList == null)
		{
			allocator.Release();
			delete recordFunc;
			return;
		}

		recordFunc(cmdList);
		delete recordFunc;

		cmdList.Close();

		ID3D12CommandList*[1] cmdLists = .((ID3D12CommandList*)cmdList);
		mQueue.ExecuteCommandLists(1, &cmdLists);

		// Wait for completion
		mInlineFenceValue++;
		mQueue.Signal(mInlineFence, mInlineFenceValue);
		if (mInlineFence.GetCompletedValue() < mInlineFenceValue)
		{
			mInlineFence.SetEventOnCompletion(mInlineFenceValue, mInlineEvent);
			WaitForSingleObjectEx(mInlineEvent, uint32.MaxValue, FALSE);
		}

		cmdList.Release();
		allocator.Release();
	}
}
