namespace Sedulous.RHI.DX12;

using System;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Dxgi.Common;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

using Win32;

/// DX12 implementation of ITexture.
class DX12Texture : ITexture
{
	private DX12Device mDevice;
	private ID3D12Resource* mResource;
	private bool mOwnsResource;
	private TextureDimension mDimension;
	private TextureFormat mFormat;
	private uint32 mWidth;
	private uint32 mHeight;
	private uint32 mDepth;
	private uint32 mMipLevelCount;
	private uint32 mArrayLayerCount;
	private uint32 mSampleCount;
	private TextureUsage mUsage;
	private D3D12_RESOURCE_STATES mCurrentState;
	private String mDebugName ~ delete _;

	/// Creates a new texture with the given descriptor.
	public this(DX12Device device, TextureDescriptor* descriptor)
	{
		mDevice = device;
		mOwnsResource = true;
		mDimension = descriptor.Dimension;
		mFormat = descriptor.Format;
		mWidth = descriptor.Width;
		mHeight = descriptor.Height;
		mDepth = descriptor.Depth;
		mMipLevelCount = descriptor.MipLevelCount;
		mArrayLayerCount = descriptor.ArrayLayerCount;
		mSampleCount = descriptor.SampleCount;
		mUsage = descriptor.Usage;
		if (descriptor.Label.Ptr != null && descriptor.Label.Length > 0)
			mDebugName = new String(descriptor.Label);

		CreateTexture(descriptor);
	}

	/// Wraps an existing D3D12 resource (e.g., swap chain back buffer). Non-owning.
	public this(DX12Device device, ID3D12Resource* resource, TextureFormat format, uint32 width, uint32 height, D3D12_RESOURCE_STATES initialState)
	{
		mDevice = device;
		mResource = resource;
		mOwnsResource = false;
		mDimension = .Texture2D;
		mFormat = format;
		mWidth = width;
		mHeight = height;
		mDepth = 1;
		mMipLevelCount = 1;
		mArrayLayerCount = 1;
		mSampleCount = 1;
		mUsage = .RenderTarget | .CopySrc;
		mCurrentState = initialState;
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mOwnsResource && mResource != null)
		{
			mResource.Release();
		}
		mResource = null;
	}

	public bool IsValid => mResource != null;
	public StringView DebugName => mDebugName != null ? mDebugName : "";
	public TextureDimension Dimension => mDimension;
	public TextureFormat Format => mFormat;
	public uint32 Width => mWidth;
	public uint32 Height => mHeight;
	public uint32 Depth => mDepth;
	public uint32 MipLevelCount => mMipLevelCount;
	public uint32 ArrayLayerCount => mArrayLayerCount;
	public uint32 SampleCount => mSampleCount;
	public TextureUsage Usage => mUsage;

	public ID3D12Resource* Resource => mResource;
	public D3D12_RESOURCE_STATES CurrentState { get => mCurrentState; set => mCurrentState = value; }

	/// True for swap chain back buffer wrappers (non-owning).
	public bool IsSwapChainTexture => !mOwnsResource;

	/// Transitions the texture to a new resource state. Returns true if a barrier was needed.
	public bool TransitionTo(D3D12_RESOURCE_STATES newState, out D3D12_RESOURCE_BARRIER barrier)
	{
		barrier = default;
		if (mCurrentState == newState)
			return false;

		barrier.Type = .D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
		barrier.Flags = .D3D12_RESOURCE_BARRIER_FLAG_NONE;
		barrier.Transition.pResource = mResource;
		barrier.Transition.Subresource = 0xFFFFFFFF; // D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES
		barrier.Transition.StateBefore = mCurrentState;
		barrier.Transition.StateAfter = newState;

		mCurrentState = newState;
		return true;
	}

	private void CreateTexture(TextureDescriptor* descriptor)
	{
		bool isDepth = DX12Conversions.IsDepthFormat(descriptor.Format);
		bool needsSrv = (descriptor.Usage & .Sampled) != 0;

		// Use typeless format for depth+sampled textures
		DXGI_FORMAT resourceFormat;
		if (isDepth && needsSrv)
			resourceFormat = DX12Conversions.GetTypelessDepthFormat(descriptor.Format);
		else
			resourceFormat = DX12Conversions.ToDxgiFormat(descriptor.Format);

		D3D12_RESOURCE_DESC resourceDesc = .();
		resourceDesc.Alignment = 0;
		resourceDesc.Format = resourceFormat;
		resourceDesc.MipLevels = (uint16)descriptor.MipLevelCount;
		resourceDesc.SampleDesc.Count = descriptor.SampleCount;
		resourceDesc.SampleDesc.Quality = 0;
		resourceDesc.Layout = .D3D12_TEXTURE_LAYOUT_UNKNOWN;
		resourceDesc.Flags = .D3D12_RESOURCE_FLAG_NONE;

		switch (descriptor.Dimension)
		{
		case .Texture1D:
			resourceDesc.Dimension = .D3D12_RESOURCE_DIMENSION_TEXTURE1D;
			resourceDesc.Width = descriptor.Width;
			resourceDesc.Height = 1;
			resourceDesc.DepthOrArraySize = (uint16)descriptor.ArrayLayerCount;
		case .Texture2D:
			resourceDesc.Dimension = .D3D12_RESOURCE_DIMENSION_TEXTURE2D;
			resourceDesc.Width = descriptor.Width;
			resourceDesc.Height = descriptor.Height;
			resourceDesc.DepthOrArraySize = (uint16)descriptor.ArrayLayerCount;
		case .Texture3D:
			resourceDesc.Dimension = .D3D12_RESOURCE_DIMENSION_TEXTURE3D;
			resourceDesc.Width = descriptor.Width;
			resourceDesc.Height = descriptor.Height;
			resourceDesc.DepthOrArraySize = (uint16)descriptor.Depth;
		}

		// Resource flags from usage
		if ((descriptor.Usage & .RenderTarget) != 0)
			resourceDesc.Flags |= .D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
		if ((descriptor.Usage & .DepthStencil) != 0)
			resourceDesc.Flags |= .D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL;
		if ((descriptor.Usage & .Storage) != 0)
			resourceDesc.Flags |= .D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
		// CopyDst textures may be blit destinations — DX12 blit uses a render pass
		if ((descriptor.Usage & .CopyDst) != 0 && !isDepth)
			resourceDesc.Flags |= .D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;

		// Determine initial state
		if (isDepth)
			mCurrentState = .D3D12_RESOURCE_STATE_DEPTH_WRITE;
		else if ((descriptor.Usage & .RenderTarget) != 0)
			mCurrentState = .D3D12_RESOURCE_STATE_RENDER_TARGET;
		else
			mCurrentState = .D3D12_RESOURCE_STATE_COMMON;

		D3D12_HEAP_PROPERTIES heapProps = .();
		heapProps.Type = .D3D12_HEAP_TYPE_DEFAULT;
		heapProps.CPUPageProperty = .D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
		heapProps.MemoryPoolPreference = .D3D12_MEMORY_POOL_UNKNOWN;
		heapProps.CreationNodeMask = 1;
		heapProps.VisibleNodeMask = 1;

		// Optimized clear value for render targets / depth
		D3D12_CLEAR_VALUE clearValue = .();
		D3D12_CLEAR_VALUE* pClearValue = null;
		if ((resourceDesc.Flags & .D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET) != 0 && !isDepth)
		{
			clearValue.Format = DX12Conversions.ToDxgiFormat(descriptor.Format);
			clearValue.Color = .(0, 0, 0, 1);
			pClearValue = &clearValue;
		}
		else if (isDepth)
		{
			clearValue.Format = DX12Conversions.GetDepthDsvFormat(descriptor.Format);
			clearValue.DepthStencil.Depth = 1.0f;
			clearValue.DepthStencil.Stencil = 0;
			pClearValue = &clearValue;
		}

		HRESULT hr = mDevice.NativeDevice.CreateCommittedResource(
			&heapProps,
			.D3D12_HEAP_FLAG_NONE,
			&resourceDesc,
			mCurrentState,
			pClearValue,
			ID3D12Resource.IID,
			(void**)&mResource);

		if (!SUCCEEDED(hr))
		{
			mResource = null;
		}
	}
}
