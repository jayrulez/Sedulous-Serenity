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

/// DX12 implementation of ICommandEncoder.
/// Records commands into an ID3D12GraphicsCommandList.
class DX12CommandEncoder : ICommandEncoder
{
	private DX12Device mDevice;
	private ID3D12CommandAllocator* mAllocator;
	private ID3D12GraphicsCommandList* mCommandList;
	private bool mIsRecording;
	private bool mFinished;

	public this(DX12Device device)
	{
		mDevice = device;
		CreateCommandList();
	}

	public ~this()
	{
		// If not finished, release resources (finished transfers ownership to DX12CommandBuffer)
		if (!mFinished)
		{
			if (mCommandList != null) { mCommandList.Release(); mCommandList = null; }
			if (mAllocator != null) { mAllocator.Release(); mAllocator = null; }
		}
	}

	public bool IsValid => mCommandList != null && mIsRecording;

	public IRenderPassEncoder BeginRenderPass(RenderPassDesc* descriptor)
	{
		if (!mIsRecording || mFinished)
			return null;

		// Set descriptor heaps before any rendering
		ID3D12DescriptorHeap*[2] heaps;
		heaps[0] = mDevice.CbvSrvUavGpuHeap.Heap;
		heaps[1] = mDevice.SamplerGpuHeap.Heap;
		mCommandList.SetDescriptorHeaps(2, &heaps);

		// Collect render target views and determine dimensions
		List<D3D12_CPU_DESCRIPTOR_HANDLE> rtvHandles = scope .();
		D3D12_CPU_DESCRIPTOR_HANDLE dsvHandle = default;
		bool hasDsv = false;
		uint32 width = 0;
		uint32 height = 0;

		// Track textures that need barriers
		List<DX12Texture> colorTextures = scope .();

		for (let colorAttachment in descriptor.ColorAttachments)
		{
			if (colorAttachment.View == null)
				continue;

			if (let dx12View = colorAttachment.View as DX12TextureView)
			{
				if (dx12View.HasRtv)
				{
					// Transition to render target
					if (let dx12Tex = dx12View.Texture as DX12Texture)
					{
						D3D12_RESOURCE_BARRIER barrier;
						if (dx12Tex.TransitionTo(.D3D12_RESOURCE_STATE_RENDER_TARGET, out barrier))
							mCommandList.ResourceBarrier(1, &barrier);
						colorTextures.Add(dx12Tex);

						if (width == 0)
						{
							width = dx12Tex.Width;
							height = dx12Tex.Height;
						}
					}

					rtvHandles.Add(dx12View.RtvHandle);
				}

				// Handle clear
				if (colorAttachment.LoadOp == .Clear)
				{
					float[4] clearColor;
					clearColor[0] = colorAttachment.ClearValue.R / 255.0f;
					clearColor[1] = colorAttachment.ClearValue.G / 255.0f;
					clearColor[2] = colorAttachment.ClearValue.B / 255.0f;
					clearColor[3] = colorAttachment.ClearValue.A / 255.0f;
					mCommandList.ClearRenderTargetView(dx12View.RtvHandle, &clearColor, 0, null);
				}
			}
		}

		// Depth/stencil attachment
		if (descriptor.DepthStencilAttachment.HasValue)
		{
			let ds = descriptor.DepthStencilAttachment.Value;
			if (ds.View != null)
			{
				if (let dx12View = ds.View as DX12TextureView)
				{
					if (dx12View.HasDsv)
					{
						if (let dx12Tex = dx12View.Texture as DX12Texture)
						{
							let dsvState = ds.DepthReadOnly
								? D3D12_RESOURCE_STATES.D3D12_RESOURCE_STATE_DEPTH_READ
								: D3D12_RESOURCE_STATES.D3D12_RESOURCE_STATE_DEPTH_WRITE;
							D3D12_RESOURCE_BARRIER barrier;
							if (dx12Tex.TransitionTo(dsvState, out barrier))
								mCommandList.ResourceBarrier(1, &barrier);

							if (width == 0)
							{
								width = dx12Tex.Width;
								height = dx12Tex.Height;
							}
						}

						dsvHandle = dx12View.DsvHandle;
						hasDsv = true;

						// Clear depth/stencil
						if (ds.DepthLoadOp == .Clear || ds.StencilLoadOp == .Clear)
						{
							D3D12_CLEAR_FLAGS clearFlags = default;
							if (ds.DepthLoadOp == .Clear)
								clearFlags |= .D3D12_CLEAR_FLAG_DEPTH;
							if (ds.StencilLoadOp == .Clear)
								clearFlags |= .D3D12_CLEAR_FLAG_STENCIL;
							mCommandList.ClearDepthStencilView(dsvHandle, clearFlags, ds.DepthClearValue, (uint8)ds.StencilClearValue, 0, null);
						}
					}
				}
			}
		}

		// Set render targets
		if (rtvHandles.Count > 0 || hasDsv)
		{
			mCommandList.OMSetRenderTargets(
				(uint32)rtvHandles.Count,
				rtvHandles.Count > 0 ? rtvHandles.Ptr : null,
				FALSE,
				hasDsv ? &dsvHandle : null);
		}

		// Set viewport and scissor to full render target size
		D3D12_VIEWPORT viewport = .();
		viewport.TopLeftX = 0;
		viewport.TopLeftY = 0;
		viewport.Width = (float)width;
		viewport.Height = (float)height;
		viewport.MinDepth = 0.0f;
		viewport.MaxDepth = 1.0f;
		mCommandList.RSSetViewports(1, &viewport);

		D3D12_RECT scissor = .();
		scissor.left = 0;
		scissor.top = 0;
		scissor.right = (int32)width;
		scissor.bottom = (int32)height;
		mCommandList.RSSetScissorRects(1, &scissor);

		return new DX12RenderPassEncoder(mDevice, mCommandList, colorTextures);
	}

	public IComputePassEncoder BeginComputePass(StringView label = default)
	{
		if (!mIsRecording || mFinished)
			return null;

		// Set descriptor heaps
		ID3D12DescriptorHeap*[2] heaps;
		heaps[0] = mDevice.CbvSrvUavGpuHeap.Heap;
		heaps[1] = mDevice.SamplerGpuHeap.Heap;
		mCommandList.SetDescriptorHeaps(2, &heaps);

		return new DX12ComputePassEncoder(mDevice, mCommandList);
	}

	public void CopyBufferToBuffer(IBuffer source, uint64 sourceOffset, IBuffer destination, uint64 destinationOffset, uint64 size)
	{
		if (!mIsRecording || mFinished)
			return;

		let srcBuffer = source as DX12Buffer;
		let dstBuffer = destination as DX12Buffer;
		if (srcBuffer == null || dstBuffer == null)
			return;

		// Transition states
		D3D12_RESOURCE_BARRIER[2] barriers;
		int barrierCount = 0;

		if (srcBuffer.TransitionTo(.D3D12_RESOURCE_STATE_COPY_SOURCE, out barriers[barrierCount]))
			barrierCount++;
		if (dstBuffer.TransitionTo(.D3D12_RESOURCE_STATE_COPY_DEST, out barriers[barrierCount]))
			barrierCount++;

		if (barrierCount > 0)
			mCommandList.ResourceBarrier((uint32)barrierCount, &barriers);

		mCommandList.CopyBufferRegion(dstBuffer.Resource, destinationOffset, srcBuffer.Resource, sourceOffset, size);
	}

	public void CopyBufferToTexture(IBuffer source, ITexture destination, BufferTextureCopyInfo* copyInfo)
	{
		if (!mIsRecording || mFinished || copyInfo == null)
			return;

		let srcBuffer = source as DX12Buffer;
		let dstTexture = destination as DX12Texture;
		if (srcBuffer == null || dstTexture == null)
			return;

		D3D12_RESOURCE_BARRIER barrier;
		if (dstTexture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_DEST, out barrier))
			mCommandList.ResourceBarrier(1, &barrier);

		// Use GetCopyableFootprints for proper row pitch alignment
		D3D12_TEXTURE_COPY_LOCATION dst = .();
		dst.pResource = dstTexture.Resource;
		dst.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
		dst.SubresourceIndex = copyInfo.TextureMipLevel + copyInfo.TextureArrayLayer * dstTexture.MipLevelCount;

		D3D12_TEXTURE_COPY_LOCATION src = .();
		src.pResource = srcBuffer.Resource;
		src.Type = .D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
		src.PlacedFootprint.Offset = copyInfo.BufferLayout.Offset;
		src.PlacedFootprint.Footprint.Format = DX12Conversions.ToDxgiFormat(dstTexture.Format);
		src.PlacedFootprint.Footprint.Width = copyInfo.CopySize.Width;
		src.PlacedFootprint.Footprint.Height = copyInfo.CopySize.Height;
		src.PlacedFootprint.Footprint.Depth = copyInfo.CopySize.Depth;
		src.PlacedFootprint.Footprint.RowPitch = copyInfo.BufferLayout.BytesPerRow;

		D3D12_BOX srcBox = .();
		srcBox.left = 0;
		srcBox.top = 0;
		srcBox.front = 0;
		srcBox.right = copyInfo.CopySize.Width;
		srcBox.bottom = copyInfo.CopySize.Height;
		srcBox.back = copyInfo.CopySize.Depth;

		mCommandList.CopyTextureRegion(&dst,
			copyInfo.TextureOrigin.X, copyInfo.TextureOrigin.Y, copyInfo.TextureOrigin.Z,
			&src, &srcBox);
	}

	public void CopyTextureToBuffer(ITexture source, IBuffer destination, BufferTextureCopyInfo* copyInfo)
	{
		if (!mIsRecording || mFinished || copyInfo == null)
			return;

		let srcTexture = source as DX12Texture;
		let dstBuffer = destination as DX12Buffer;
		if (srcTexture == null || dstBuffer == null)
			return;

		D3D12_RESOURCE_BARRIER barrier;
		if (srcTexture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_SOURCE, out barrier))
			mCommandList.ResourceBarrier(1, &barrier);

		D3D12_TEXTURE_COPY_LOCATION src = .();
		src.pResource = srcTexture.Resource;
		src.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
		src.SubresourceIndex = copyInfo.TextureMipLevel + copyInfo.TextureArrayLayer * srcTexture.MipLevelCount;

		D3D12_TEXTURE_COPY_LOCATION dst = .();
		dst.pResource = dstBuffer.Resource;
		dst.Type = .D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
		dst.PlacedFootprint.Offset = copyInfo.BufferLayout.Offset;
		dst.PlacedFootprint.Footprint.Format = DX12Conversions.ToDxgiFormat(srcTexture.Format);
		dst.PlacedFootprint.Footprint.Width = copyInfo.CopySize.Width;
		dst.PlacedFootprint.Footprint.Height = copyInfo.CopySize.Height;
		dst.PlacedFootprint.Footprint.Depth = copyInfo.CopySize.Depth;
		dst.PlacedFootprint.Footprint.RowPitch = copyInfo.BufferLayout.BytesPerRow;

		D3D12_BOX srcBox = .();
		srcBox.left = copyInfo.TextureOrigin.X;
		srcBox.top = copyInfo.TextureOrigin.Y;
		srcBox.front = copyInfo.TextureOrigin.Z;
		srcBox.right = copyInfo.TextureOrigin.X + copyInfo.CopySize.Width;
		srcBox.bottom = copyInfo.TextureOrigin.Y + copyInfo.CopySize.Height;
		srcBox.back = copyInfo.TextureOrigin.Z + copyInfo.CopySize.Depth;

		mCommandList.CopyTextureRegion(&dst, 0, 0, 0, &src, &srcBox);
	}

	public void CopyTextureToTexture(ITexture source, ITexture destination, TextureCopyInfo* copyInfo)
	{
		if (!mIsRecording || mFinished || copyInfo == null)
			return;

		let srcTexture = source as DX12Texture;
		let dstTexture = destination as DX12Texture;
		if (srcTexture == null || dstTexture == null)
			return;

		D3D12_RESOURCE_BARRIER[2] barriers;
		int barrierCount = 0;
		if (srcTexture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_SOURCE, out barriers[barrierCount]))
			barrierCount++;
		if (dstTexture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_DEST, out barriers[barrierCount]))
			barrierCount++;
		if (barrierCount > 0)
			mCommandList.ResourceBarrier((uint32)barrierCount, &barriers);

		D3D12_TEXTURE_COPY_LOCATION src = .();
		src.pResource = srcTexture.Resource;
		src.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
		src.SubresourceIndex = copyInfo.SrcMipLevel + copyInfo.SrcArrayLayer * srcTexture.MipLevelCount;

		D3D12_TEXTURE_COPY_LOCATION dst = .();
		dst.pResource = dstTexture.Resource;
		dst.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
		dst.SubresourceIndex = copyInfo.DstMipLevel + copyInfo.DstArrayLayer * dstTexture.MipLevelCount;

		D3D12_BOX srcBox = .();
		srcBox.left = copyInfo.SrcOrigin.X;
		srcBox.top = copyInfo.SrcOrigin.Y;
		srcBox.front = copyInfo.SrcOrigin.Z;
		srcBox.right = copyInfo.SrcOrigin.X + copyInfo.CopySize.Width;
		srcBox.bottom = copyInfo.SrcOrigin.Y + copyInfo.CopySize.Height;
		srcBox.back = copyInfo.SrcOrigin.Z + copyInfo.CopySize.Depth;

		mCommandList.CopyTextureRegion(&dst,
			copyInfo.DstOrigin.X, copyInfo.DstOrigin.Y, copyInfo.DstOrigin.Z,
			&src, &srcBox);
	}

	public void TextureBarrier(ITexture texture, TextureLayout oldLayout, TextureLayout newLayout)
	{
		if (!mIsRecording || mFinished)
			return;

		let dx12Texture = texture as DX12Texture;
		if (dx12Texture == null)
			return;

		let newState = DX12Conversions.ToDx12ResourceState(newLayout);
		D3D12_RESOURCE_BARRIER barrier;
		if (dx12Texture.TransitionTo(newState, out barrier))
			mCommandList.ResourceBarrier(1, &barrier);
	}

	public void GenerateMipmaps(ITexture texture)
	{
		if (!mIsRecording || mFinished)
			return;

		let dx12Texture = texture as DX12Texture;
		if (dx12Texture == null)
			return;

		let mipLevels = dx12Texture.MipLevelCount;
		if (mipLevels <= 1)
			return;

		// Transition entire texture to COPY_SOURCE (mip 0 is source for level 1)
		D3D12_RESOURCE_BARRIER barrier;
		if (dx12Texture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_SOURCE, out barrier))
			mCommandList.ResourceBarrier(1, &barrier);

		int32 mipWidth = (int32)dx12Texture.Width;
		int32 mipHeight = (int32)dx12Texture.Height;

		for (uint32 i = 1; i < mipLevels; i++)
		{
			int32 dstWidth = mipWidth > 1 ? mipWidth / 2 : 1;
			int32 dstHeight = mipHeight > 1 ? mipHeight / 2 : 1;

			// Transition destination mip to COPY_DEST
			D3D12_RESOURCE_BARRIER mipBarrier = .();
			mipBarrier.Type = .D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
			mipBarrier.Flags = .D3D12_RESOURCE_BARRIER_FLAG_NONE;
			mipBarrier.Transition.pResource = dx12Texture.Resource;
			mipBarrier.Transition.Subresource = i;
			mipBarrier.Transition.StateBefore = .D3D12_RESOURCE_STATE_COPY_SOURCE;
			mipBarrier.Transition.StateAfter = .D3D12_RESOURCE_STATE_COPY_DEST;
			mCommandList.ResourceBarrier(1, &mipBarrier);

			// Copy from previous mip to current (no scaling — DX12 CopyTextureRegion doesn't scale)
			// For proper mipmap generation with filtering, a compute shader or blit would be needed.
			// This is a basic copy-based approach.
			D3D12_TEXTURE_COPY_LOCATION src = .();
			src.pResource = dx12Texture.Resource;
			src.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
			src.SubresourceIndex = i - 1;

			D3D12_TEXTURE_COPY_LOCATION dst = .();
			dst.pResource = dx12Texture.Resource;
			dst.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
			dst.SubresourceIndex = i;

			D3D12_BOX srcBox = .();
			srcBox.left = 0;
			srcBox.top = 0;
			srcBox.front = 0;
			srcBox.right = (uint32)dstWidth;
			srcBox.bottom = (uint32)dstHeight;
			srcBox.back = 1;

			mCommandList.CopyTextureRegion(&dst, 0, 0, 0, &src, &srcBox);

			// Transition destination mip back to COPY_SOURCE for next iteration
			mipBarrier.Transition.StateBefore = .D3D12_RESOURCE_STATE_COPY_DEST;
			mipBarrier.Transition.StateAfter = .D3D12_RESOURCE_STATE_COPY_SOURCE;
			mCommandList.ResourceBarrier(1, &mipBarrier);

			mipWidth = dstWidth;
			mipHeight = dstHeight;
		}

		// Transition entire texture to shader read
		// We need to track the state as COPY_SOURCE since that's what all subresources are in
		dx12Texture.CurrentState = .D3D12_RESOURCE_STATE_COPY_SOURCE;
		if (dx12Texture.TransitionTo((D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE), out barrier))
			mCommandList.ResourceBarrier(1, &barrier);
	}

	// ===== Queries =====

	public void ResetQuerySet(IQuerySet querySet, uint32 firstQuery, uint32 queryCount)
	{
		// D3D12 queries don't need explicit reset
	}

	public void WriteTimestamp(IQuerySet querySet, uint32 queryIndex)
	{
		if (!mIsRecording || mFinished)
			return;

		let dx12QuerySet = querySet as DX12QuerySet;
		if (dx12QuerySet == null || dx12QuerySet.Type != .Timestamp)
			return;

		mCommandList.EndQuery(dx12QuerySet.QueryHeap, .D3D12_QUERY_TYPE_TIMESTAMP, queryIndex);

		// Auto-resolve into the query set's internal readback buffer
		if (dx12QuerySet.ReadbackBuffer != null)
		{
			mCommandList.ResolveQueryData(
				dx12QuerySet.QueryHeap,
				.D3D12_QUERY_TYPE_TIMESTAMP,
				queryIndex, 1,
				dx12QuerySet.ReadbackBuffer,
				(uint64)(queryIndex * dx12QuerySet.ResultStride));
		}
	}

	public void BeginQuery(IQuerySet querySet, uint32 queryIndex)
	{
		if (!mIsRecording || mFinished)
			return;

		let dx12QuerySet = querySet as DX12QuerySet;
		if (dx12QuerySet == null || dx12QuerySet.Type == .Timestamp)
			return;

		let queryType = dx12QuerySet.Type == .Occlusion
			? D3D12_QUERY_TYPE.D3D12_QUERY_TYPE_OCCLUSION
			: D3D12_QUERY_TYPE.D3D12_QUERY_TYPE_PIPELINE_STATISTICS;

		mCommandList.BeginQuery(dx12QuerySet.QueryHeap, queryType, queryIndex);
	}

	public void EndQuery(IQuerySet querySet, uint32 queryIndex)
	{
		if (!mIsRecording || mFinished)
			return;

		let dx12QuerySet = querySet as DX12QuerySet;
		if (dx12QuerySet == null || dx12QuerySet.Type == .Timestamp)
			return;

		let queryType = dx12QuerySet.Type == .Occlusion
			? D3D12_QUERY_TYPE.D3D12_QUERY_TYPE_OCCLUSION
			: D3D12_QUERY_TYPE.D3D12_QUERY_TYPE_PIPELINE_STATISTICS;

		mCommandList.EndQuery(dx12QuerySet.QueryHeap, queryType, queryIndex);

		// Auto-resolve into the query set's internal readback buffer
		if (dx12QuerySet.ReadbackBuffer != null)
		{
			mCommandList.ResolveQueryData(
				dx12QuerySet.QueryHeap,
				queryType,
				queryIndex, 1,
				dx12QuerySet.ReadbackBuffer,
				(uint64)(queryIndex * dx12QuerySet.ResultStride));
		}
	}

	public void ResolveQuerySet(IQuerySet querySet, uint32 firstQuery, uint32 queryCount, IBuffer destination, uint64 destinationOffset)
	{
		if (!mIsRecording || mFinished)
			return;

		let dx12QuerySet = querySet as DX12QuerySet;
		let dx12Buffer = destination as DX12Buffer;
		if (dx12QuerySet == null || dx12Buffer == null)
			return;

		D3D12_QUERY_TYPE queryType = .();
		switch (dx12QuerySet.Type)
		{
		case .Timestamp:           queryType = .D3D12_QUERY_TYPE_TIMESTAMP;
		case .Occlusion:           queryType = .D3D12_QUERY_TYPE_OCCLUSION;
		case .PipelineStatistics:  queryType = .D3D12_QUERY_TYPE_PIPELINE_STATISTICS;
		}

		D3D12_RESOURCE_BARRIER barrier;
		if (dx12Buffer.TransitionTo(.D3D12_RESOURCE_STATE_COPY_DEST, out barrier))
			mCommandList.ResourceBarrier(1, &barrier);

		mCommandList.ResolveQueryData(dx12QuerySet.QueryHeap, queryType, firstQuery, queryCount, dx12Buffer.Resource, destinationOffset);
	}

	public void ResolveTexture(ITexture source, ITexture destination)
	{
		if (!mIsRecording || mFinished)
			return;

		let srcTexture = source as DX12Texture;
		let dstTexture = destination as DX12Texture;
		if (srcTexture == null || dstTexture == null)
			return;

		D3D12_RESOURCE_BARRIER[2] barriers;
		int barrierCount = 0;
		if (srcTexture.TransitionTo(.D3D12_RESOURCE_STATE_RESOLVE_SOURCE, out barriers[barrierCount]))
			barrierCount++;
		if (dstTexture.TransitionTo(.D3D12_RESOURCE_STATE_RESOLVE_DEST, out barriers[barrierCount]))
			barrierCount++;
		if (barrierCount > 0)
			mCommandList.ResourceBarrier((uint32)barrierCount, &barriers);

		mCommandList.ResolveSubresource(dstTexture.Resource, 0, srcTexture.Resource, 0, DX12Conversions.ToDxgiFormat(dstTexture.Format));

		// Transition destination to shader read
		if (dstTexture.TransitionTo((D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE), out barriers[0]))
			mCommandList.ResourceBarrier(1, &barriers);
	}

	public void Blit(ITexture source, ITexture destination)
	{
		if (!mIsRecording || mFinished)
			return;

		let srcTexture = source as DX12Texture;
		let dstTexture = destination as DX12Texture;
		if (srcTexture == null || dstTexture == null)
			return;

		// Same size: use fast CopyTextureRegion path
		if (srcTexture.Width == dstTexture.Width && srcTexture.Height == dstTexture.Height)
		{
			D3D12_RESOURCE_BARRIER[2] barriers;
			int barrierCount = 0;
			if (srcTexture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_SOURCE, out barriers[barrierCount]))
				barrierCount++;
			if (dstTexture.TransitionTo(.D3D12_RESOURCE_STATE_COPY_DEST, out barriers[barrierCount]))
				barrierCount++;
			if (barrierCount > 0)
				mCommandList.ResourceBarrier((uint32)barrierCount, &barriers);

			D3D12_TEXTURE_COPY_LOCATION src = .();
			src.pResource = srcTexture.Resource;
			src.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
			src.SubresourceIndex = 0;

			D3D12_TEXTURE_COPY_LOCATION dst = .();
			dst.pResource = dstTexture.Resource;
			dst.Type = .D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
			dst.SubresourceIndex = 0;

			mCommandList.CopyTextureRegion(&dst, 0, 0, 0, &src, null);

			if (dstTexture.TransitionTo((D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE), out barriers[0]))
				mCommandList.ResourceBarrier(1, &barriers);
			return;
		}

		// Different sizes: render-based blit with scaling via fullscreen triangle
		BlitWithScaling(srcTexture, dstTexture);
	}

	private void BlitWithScaling(DX12Texture srcTexture, DX12Texture dstTexture)
	{
		let blitRootSig = mDevice.BlitRootSignature;
		if (blitRootSig == null)
			return;

		DXGI_FORMAT dstFormat = DX12Conversions.ToDxgiFormat(dstTexture.Format);
		let blitPso = mDevice.GetOrCreateBlitPSO(dstFormat);
		if (blitPso == null)
			return;

		// Transition source to shader resource, destination to render target
		D3D12_RESOURCE_BARRIER[2] barriers;
		int barrierCount = 0;
		if (srcTexture.TransitionTo((D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE), out barriers[barrierCount]))
			barrierCount++;
		if (dstTexture.TransitionTo(.D3D12_RESOURCE_STATE_RENDER_TARGET, out barriers[barrierCount]))
			barrierCount++;
		if (barrierCount > 0)
			mCommandList.ResourceBarrier((uint32)barrierCount, &barriers);

		// Allocate temporary RTV for destination
		D3D12_CPU_DESCRIPTOR_HANDLE rtvHandle;
		if (!mDevice.RtvHeap.Allocate(out rtvHandle))
			return;

		D3D12_RENDER_TARGET_VIEW_DESC rtvDesc = .();
		rtvDesc.Format = dstFormat;
		rtvDesc.ViewDimension = .D3D12_RTV_DIMENSION_TEXTURE2D;
		rtvDesc.Texture2D.MipSlice = 0;
		rtvDesc.Texture2D.PlaneSlice = 0;
		mDevice.NativeDevice.CreateRenderTargetView(dstTexture.Resource, &rtvDesc, rtvHandle);

		// Allocate SRV for source in GPU heap
		D3D12_CPU_DESCRIPTOR_HANDLE srvCpuHandle;
		D3D12_GPU_DESCRIPTOR_HANDLE srvGpuHandle;
		if (!mDevice.CbvSrvUavGpuHeap.Allocate(out srvCpuHandle, out srvGpuHandle))
		{
			mDevice.RtvHeap.Free(rtvHandle);
			return;
		}

		D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = .();
		srvDesc.Format = DX12Conversions.ToDxgiFormat(srcTexture.Format);
		srvDesc.ViewDimension = .D3D12_SRV_DIMENSION_TEXTURE2D;
		srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
		srvDesc.Texture2D.MostDetailedMip = 0;
		srvDesc.Texture2D.MipLevels = 1;
		srvDesc.Texture2D.PlaneSlice = 0;
		mDevice.NativeDevice.CreateShaderResourceView(srcTexture.Resource, &srvDesc, srvCpuHandle);

		// Set descriptor heaps
		ID3D12DescriptorHeap*[2] heaps;
		heaps[0] = mDevice.CbvSrvUavGpuHeap.Heap;
		heaps[1] = mDevice.SamplerGpuHeap.Heap;
		mCommandList.SetDescriptorHeaps(2, &heaps);

		// Set pipeline state
		mCommandList.SetGraphicsRootSignature(blitRootSig);
		mCommandList.SetPipelineState(blitPso);
		mCommandList.SetGraphicsRootDescriptorTable(0, srvGpuHandle);

		// Set render target
		mCommandList.OMSetRenderTargets(1, &rtvHandle, FALSE, null);

		// Set viewport and scissor to destination size
		D3D12_VIEWPORT viewport = .();
		viewport.TopLeftX = 0;
		viewport.TopLeftY = 0;
		viewport.Width = (float)dstTexture.Width;
		viewport.Height = (float)dstTexture.Height;
		viewport.MinDepth = 0.0f;
		viewport.MaxDepth = 1.0f;
		mCommandList.RSSetViewports(1, &viewport);

		D3D12_RECT scissor = .();
		scissor.left = 0;
		scissor.top = 0;
		scissor.right = (int32)dstTexture.Width;
		scissor.bottom = (int32)dstTexture.Height;
		mCommandList.RSSetScissorRects(1, &scissor);

		// Draw fullscreen triangle
		mCommandList.IASetPrimitiveTopology(.D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
		mCommandList.DrawInstanced(3, 1, 0, 0);

		// Free temporary RTV
		mDevice.RtvHeap.Free(rtvHandle);

		// Transition destination to shader read
		if (dstTexture.TransitionTo((D3D12_RESOURCE_STATES)(.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | .D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE), out barriers[0]))
			mCommandList.ResourceBarrier(1, &barriers);
	}

	public ICommandBuffer Finish()
	{
		if (!mIsRecording || mFinished)
			return null;

		mCommandList.Close();
		mIsRecording = false;
		mFinished = true;

		// Transfer ownership to the command buffer
		let cmdBuffer = new DX12CommandBuffer(mCommandList, mAllocator);
		mCommandList = null;
		mAllocator = null;
		return cmdBuffer;
	}

	// ===== Internal =====

	private void CreateCommandList()
	{
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

		if (SUCCEEDED(hr))
		{
			mIsRecording = true;
		}
		else
		{
			mAllocator.Release();
			mAllocator = null;
		}
	}
}
