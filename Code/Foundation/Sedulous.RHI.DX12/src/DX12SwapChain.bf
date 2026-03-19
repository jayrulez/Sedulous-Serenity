namespace Sedulous.RHI.DX12;

using System;
using System.Collections;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Dxgi;
using Win32.Graphics.Dxgi.Common;
using Win32.Foundation;
using Win32.System.Com;
using Win32.System.Threading;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of ISwapChain using IDXGISwapChain3.
class DX12SwapChain : ISwapChain
{
	private const uint32 BufferCount = 2;

	private DX12Device mDevice;
	private DX12Surface mSurface;
	private IDXGISwapChain3* mSwapChain;

	private TextureFormat mFormat;
	private uint32 mWidth;
	private uint32 mHeight;
	private PresentMode mPresentMode;

	// Back buffer textures and views (owned wrappers around swap chain buffers)
	private DX12Texture[BufferCount] mBackBufferTextures;
	private DX12TextureView[BufferCount] mBackBufferViews;

	// Per-frame fences for CPU/GPU sync
	private ID3D12Fence* mFrameFence;
	private HANDLE mFrameEvent;
	private uint64 mFenceValue;                    // Global monotonic counter
	private uint64[BufferCount] mFrameFenceValues;  // Per-back-buffer: fence value when last used

	private uint32 mCurrentBackBufferIndex;

	public this(DX12Device device, DX12Surface surface, SwapChainDesc descriptor)
	{
		mDevice = device;
		mSurface = surface;
		mFormat = descriptor.Format;
		mWidth = descriptor.Width;
		mHeight = descriptor.Height;
		mPresentMode = descriptor.PresentMode;

		mFenceValue = 0;
		for (int i = 0; i < BufferCount; i++)
		{
			mBackBufferTextures[i] = null;
			mBackBufferViews[i] = null;
			mFrameFenceValues[i] = 0;
		}

		CreateSwapChain();
		if (mSwapChain != null)
		{
			CreateFrameFence();
			CreateBackBufferResources();
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		// Wait for all frames to finish before cleanup
		WaitForAllFrames();

		ReleaseBackBufferResources();

		if (mFrameEvent != 0)
		{
			CloseHandle(mFrameEvent);
			mFrameEvent = default;
		}
		if (mFrameFence != null) { mFrameFence.Release(); mFrameFence = null; }
		if (mSwapChain != null) { mSwapChain.Release(); mSwapChain = null; }
	}

	public bool IsValid => mSwapChain != null;
	public TextureFormat Format => mFormat;
	public uint32 Width => mWidth;
	public uint32 Height => mHeight;
	public uint32 CurrentFrameIndex => mCurrentBackBufferIndex;
	public uint32 FrameCount => BufferCount;

	public ITexture CurrentTexture
	{
		get
		{
			if (mCurrentBackBufferIndex < BufferCount && mBackBufferTextures[mCurrentBackBufferIndex] != null)
				return mBackBufferTextures[mCurrentBackBufferIndex];
			return null;
		}
	}

	public ITextureView CurrentTextureView
	{
		get
		{
			if (mCurrentBackBufferIndex < BufferCount && mBackBufferViews[mCurrentBackBufferIndex] != null)
				return mBackBufferViews[mCurrentBackBufferIndex];
			return null;
		}
	}

	public Result<void> AcquireNextImage()
	{
		if (mSwapChain == null || mFrameFence == null)
			return .Err;

		mCurrentBackBufferIndex = mSwapChain.GetCurrentBackBufferIndex();

		// Wait if this frame's fence hasn't been signaled yet
		if (mFrameFence.GetCompletedValue() < mFrameFenceValues[mCurrentBackBufferIndex])
		{
			mFrameFence.SetEventOnCompletion(mFrameFenceValues[mCurrentBackBufferIndex], mFrameEvent);
			WaitForSingleObjectEx(mFrameEvent, uint32.MaxValue, FALSE);
		}

		return .Ok;
	}

	public Result<void> Present()
	{
		if (mSwapChain == null)
			return .Err;

		// Present with vsync based on present mode
		uint32 syncInterval = (mPresentMode == .Immediate) ? 0 : 1;
		uint32 presentFlags = (mPresentMode == .Immediate) ? 0x00000200 : 0; // DXGI_PRESENT_ALLOW_TEARING

		HRESULT hr = mSwapChain.Present(syncInterval, presentFlags);
		if (!SUCCEEDED(hr))
			return .Err;

		// Signal fence for this frame with a globally increasing value
		let queue = mDevice.Queue as DX12Queue;
		if (queue != null)
		{
			mFenceValue++;
			mFrameFenceValues[mCurrentBackBufferIndex] = mFenceValue;
			queue.NativeQueue.Signal(mFrameFence, mFenceValue);
		}

		return .Ok;
	}

	public Result<void> Resize(uint32 width, uint32 height)
	{
		if (mSwapChain == null || width == 0 || height == 0)
			return .Err;

		// Wait for all frames to complete
		WaitForAllFrames();

		// Release old back buffer resources
		ReleaseBackBufferResources();

		// Resize buffers
		HRESULT hr = mSwapChain.ResizeBuffers(
			BufferCount,
			width,
			height,
			GetSwapChainDxgiFormat(),
			0);

		if (!SUCCEEDED(hr))
			return .Err;

		mWidth = width;
		mHeight = height;

		// Reset per-buffer fence values (global counter keeps incrementing)
		for (int i = 0; i < BufferCount; i++)
			mFrameFenceValues[i] = 0;

		// Recreate back buffer wrappers
		CreateBackBufferResources();

		return .Ok;
	}

	// ===== Internal =====

	/// Returns the non-SRGB DXGI format for swap chain creation.
	/// DXGI flip model only supports non-SRGB formats; SRGB is applied via the RTV.
	private DXGI_FORMAT GetSwapChainDxgiFormat()
	{
		switch (mFormat)
		{
		case .BGRA8UnormSrgb: return .DXGI_FORMAT_B8G8R8A8_UNORM;
		case .RGBA8UnormSrgb: return .DXGI_FORMAT_R8G8B8A8_UNORM;
		default: return DX12Conversions.ToDxgiFormat(mFormat);
		}
	}

	private void CreateSwapChain()
	{
		let factory = mDevice.DXGIFactory;
		if (factory == null)
			return;

		DXGI_SWAP_CHAIN_DESC1 desc = .();
		desc.Width = mWidth;
		desc.Height = mHeight;
		desc.Format = GetSwapChainDxgiFormat();
		desc.Stereo = FALSE;
		desc.SampleDesc.Count = 1;
		desc.SampleDesc.Quality = 0;
		desc.BufferUsage = 0x00000020; // DXGI_USAGE_RENDER_TARGET_OUTPUT
		desc.BufferCount = BufferCount;
		desc.Scaling = .DXGI_SCALING_STRETCH;
		desc.SwapEffect = .DXGI_SWAP_EFFECT_FLIP_DISCARD;
		desc.AlphaMode = .DXGI_ALPHA_MODE_UNSPECIFIED;
		desc.Flags = 0;

		// Allow tearing for Immediate mode
		if (mPresentMode == .Immediate)
			desc.Flags |= 2048; // DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING

		let queue = mDevice.Queue as DX12Queue;
		if (queue == null)
			return;

		IDXGISwapChain1* swapChain1 = null;
		HRESULT hr = factory.CreateSwapChainForHwnd(
			(IUnknown*)queue.NativeQueue,
			mSurface.Hwnd,
			&desc,
			null,
			null,
			&swapChain1);

		if (!SUCCEEDED(hr) || swapChain1 == null)
			return;

		// Query for IDXGISwapChain3
		hr = swapChain1.QueryInterface(IDXGISwapChain3.IID, (void**)&mSwapChain);
		swapChain1.Release();

		if (!SUCCEEDED(hr))
			mSwapChain = null;
	}

	private void CreateFrameFence()
	{
		mDevice.NativeDevice.CreateFence(0, .D3D12_FENCE_FLAG_NONE, ID3D12Fence.IID, (void**)&mFrameFence);
		mFrameEvent = CreateEventW(null, FALSE, FALSE, null);
	}

	private void CreateBackBufferResources()
	{
		if (mSwapChain == null)
			return;

		for (uint32 i = 0; i < BufferCount; i++)
		{
			ID3D12Resource* backBuffer = null;
			HRESULT hr = mSwapChain.GetBuffer(i, ID3D12Resource.IID, (void**)&backBuffer);
			if (!SUCCEEDED(hr) || backBuffer == null)
				continue;

			// Create non-owning DX12Texture wrapper
			let texture = new DX12Texture(mDevice, backBuffer, mFormat, mWidth, mHeight, .D3D12_RESOURCE_STATE_PRESENT);
			mBackBufferTextures[i] = texture;

			// Create RTV for the back buffer
			TextureViewDesc viewDesc = .();
			viewDesc.Format = mFormat;
			viewDesc.Dimension = .Texture2D;
			viewDesc.BaseMipLevel = 0;
			viewDesc.MipLevelCount = 1;
			viewDesc.BaseArrayLayer = 0;
			viewDesc.ArrayLayerCount = 1;

			let view = new DX12TextureView(mDevice, texture, viewDesc);
			mBackBufferViews[i] = view;

			// Release our reference — the swap chain still holds one
			backBuffer.Release();
		}
	}

	private void ReleaseBackBufferResources()
	{
		for (int i = 0; i < BufferCount; i++)
		{
			if (mBackBufferViews[i] != null)
			{
				delete mBackBufferViews[i];
				mBackBufferViews[i] = null;
			}
			if (mBackBufferTextures[i] != null)
			{
				delete mBackBufferTextures[i];
				mBackBufferTextures[i] = null;
			}
		}
	}

	private void WaitForAllFrames()
	{
		if (mFrameFence == null)
			return;

		for (int i = 0; i < BufferCount; i++)
		{
			if (mFrameFenceValues[i] > 0 && mFrameFence.GetCompletedValue() < mFrameFenceValues[i])
			{
				mFrameFence.SetEventOnCompletion(mFrameFenceValues[i], mFrameEvent);
				WaitForSingleObjectEx(mFrameEvent, uint32.MaxValue, FALSE);
			}
		}
	}
}
