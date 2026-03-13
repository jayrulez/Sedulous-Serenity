namespace Sedulous.RHI.DX12;

using System;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Dxgi.Common;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of ITextureView.
class DX12TextureView : ITextureView
{
	private DX12Device mDevice;
	private DX12Texture mTexture;
	private TextureViewDimension mDimension;
	private TextureFormat mFormat;
	private uint32 mBaseMipLevel;
	private uint32 mMipLevelCount;
	private uint32 mBaseArrayLayer;
	private uint32 mArrayLayerCount;
	private String mDebugName ~ delete _;

	// CPU descriptor handles
	private D3D12_CPU_DESCRIPTOR_HANDLE mSrvHandle;
	private D3D12_CPU_DESCRIPTOR_HANDLE mRtvHandle;
	private D3D12_CPU_DESCRIPTOR_HANDLE mDsvHandle;
	private D3D12_CPU_DESCRIPTOR_HANDLE mUavHandle;
	private bool mHasSrv;
	private bool mHasRtv;
	private bool mHasDsv;
	private bool mHasUav;

	public this(DX12Device device, DX12Texture texture, TextureViewDescriptor* descriptor)
	{
		mDevice = device;
		mTexture = texture;
		mDimension = descriptor.Dimension;
		mFormat = descriptor.Format;
		mBaseMipLevel = descriptor.BaseMipLevel;
		mMipLevelCount = descriptor.MipLevelCount;
		mBaseArrayLayer = descriptor.BaseArrayLayer;
		mArrayLayerCount = descriptor.ArrayLayerCount;
		if (descriptor.Label.Ptr != null && descriptor.Label.Length > 0)
			mDebugName = new String(descriptor.Label);

		CreateViews();
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mHasRtv)
		{
			mDevice.RtvHeap.Free(mRtvHandle);
			mHasRtv = false;
		}
		if (mHasDsv)
		{
			mDevice.DsvHeap.Free(mDsvHandle);
			mHasDsv = false;
		}
	}

	public bool IsValid => mHasSrv || mHasRtv || mHasDsv || mHasUav;
	public StringView DebugName => mDebugName != null ? mDebugName : "";
	public ITexture Texture => mTexture;
	public TextureViewDimension Dimension => mDimension;
	public TextureFormat Format => mFormat;
	public uint32 BaseMipLevel => mBaseMipLevel;
	public uint32 MipLevelCount => mMipLevelCount;
	public uint32 BaseArrayLayer => mBaseArrayLayer;
	public uint32 ArrayLayerCount => mArrayLayerCount;

	public D3D12_CPU_DESCRIPTOR_HANDLE SrvHandle => mSrvHandle;
	public D3D12_CPU_DESCRIPTOR_HANDLE RtvHandle => mRtvHandle;
	public D3D12_CPU_DESCRIPTOR_HANDLE DsvHandle => mDsvHandle;
	public D3D12_CPU_DESCRIPTOR_HANDLE UavHandle => mUavHandle;
	public bool HasSrv => mHasSrv;
	public bool HasRtv => mHasRtv;
	public bool HasDsv => mHasDsv;
	public bool HasUav => mHasUav;

	private void CreateViews()
	{
		let nativeDevice = mDevice.NativeDevice;
		let texUsage = mTexture.Usage;
		bool isDepth = DX12Conversions.IsDepthFormat(mFormat);

		// SRV — always create if texture is sampled or has a view
		if ((texUsage & .Sampled) != 0 || !isDepth)
		{
			D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle;
			D3D12_GPU_DESCRIPTOR_HANDLE gpuHandle;
			if (mDevice.CbvSrvUavCpuHeap.Allocate(out cpuHandle, out gpuHandle))
			{
				D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = .();
				srvDesc.Format = isDepth ? DX12Conversions.GetDepthSrvFormat(mFormat) : DX12Conversions.ToDxgiFormat(mFormat);
				srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;

				if (mTexture.SampleCount > 1 && (mDimension == .Texture2D || mDimension == .Texture2DArray))
				{
					// MSAA textures require MS-specific SRV dimensions
					if (mDimension == .Texture2DArray)
					{
						srvDesc.ViewDimension = .D3D12_SRV_DIMENSION_TEXTURE2DMSARRAY;
						srvDesc.Texture2DMSArray.FirstArraySlice = mBaseArrayLayer;
						srvDesc.Texture2DMSArray.ArraySize = mArrayLayerCount;
					}
					else
					{
						srvDesc.ViewDimension = .D3D12_SRV_DIMENSION_TEXTURE2DMS;
						// Texture2DMS has no additional fields
					}
				}
				else
				{
					srvDesc.ViewDimension = DX12Conversions.ToDx12SrvDimension(mDimension);

					switch (mDimension)
					{
					case .Texture1D:
						srvDesc.Texture1D.MostDetailedMip = mBaseMipLevel;
						srvDesc.Texture1D.MipLevels = mMipLevelCount;
					case .Texture2D:
						srvDesc.Texture2D.MostDetailedMip = mBaseMipLevel;
						srvDesc.Texture2D.MipLevels = mMipLevelCount;
						srvDesc.Texture2D.PlaneSlice = 0;
					case .Texture2DArray:
						srvDesc.Texture2DArray.MostDetailedMip = mBaseMipLevel;
						srvDesc.Texture2DArray.MipLevels = mMipLevelCount;
						srvDesc.Texture2DArray.FirstArraySlice = mBaseArrayLayer;
						srvDesc.Texture2DArray.ArraySize = mArrayLayerCount;
					case .Texture3D:
						srvDesc.Texture3D.MostDetailedMip = mBaseMipLevel;
						srvDesc.Texture3D.MipLevels = mMipLevelCount;
					case .TextureCube:
						srvDesc.TextureCube.MostDetailedMip = mBaseMipLevel;
						srvDesc.TextureCube.MipLevels = mMipLevelCount;
					case .TextureCubeArray:
						srvDesc.TextureCubeArray.MostDetailedMip = mBaseMipLevel;
						srvDesc.TextureCubeArray.MipLevels = mMipLevelCount;
						srvDesc.TextureCubeArray.First2DArrayFace = mBaseArrayLayer;
						srvDesc.TextureCubeArray.NumCubes = mArrayLayerCount / 6;
					default:
					}
				}

				nativeDevice.CreateShaderResourceView(mTexture.Resource, &srvDesc, cpuHandle);
				mSrvHandle = cpuHandle;
				mHasSrv = true;
			}
		}

		// RTV
		if ((texUsage & .RenderTarget) != 0 && !isDepth)
		{
			if (mDevice.RtvHeap.Allocate(out mRtvHandle))
			{
				D3D12_RENDER_TARGET_VIEW_DESC rtvDesc = .();
				rtvDesc.Format = DX12Conversions.ToDxgiFormat(mFormat);
				rtvDesc.ViewDimension = DX12Conversions.ToDx12RtvDimension(mDimension, mTexture.SampleCount);

				if (mTexture.SampleCount > 1)
				{
					// MSAA — no additional fields needed
				}
				else
				{
					switch (mDimension)
					{
					case .Texture2D:
						rtvDesc.Texture2D.MipSlice = mBaseMipLevel;
						rtvDesc.Texture2D.PlaneSlice = 0;
					case .Texture2DArray:
						rtvDesc.Texture2DArray.MipSlice = mBaseMipLevel;
						rtvDesc.Texture2DArray.FirstArraySlice = mBaseArrayLayer;
						rtvDesc.Texture2DArray.ArraySize = mArrayLayerCount;
					default:
					}
				}

				nativeDevice.CreateRenderTargetView(mTexture.Resource, &rtvDesc, mRtvHandle);
				mHasRtv = true;
			}
		}

		// DSV
		if ((texUsage & .DepthStencil) != 0 && isDepth)
		{
			if (mDevice.DsvHeap.Allocate(out mDsvHandle))
			{
				D3D12_DEPTH_STENCIL_VIEW_DESC dsvDesc = .();
				dsvDesc.Format = DX12Conversions.GetDepthDsvFormat(mFormat);
				dsvDesc.ViewDimension = DX12Conversions.ToDx12DsvDimension(mDimension, mTexture.SampleCount);
				dsvDesc.Flags = .D3D12_DSV_FLAG_NONE;

				if (mTexture.SampleCount <= 1)
				{
					switch (mDimension)
					{
					case .Texture2D:
						dsvDesc.Texture2D.MipSlice = mBaseMipLevel;
					case .Texture2DArray:
						dsvDesc.Texture2DArray.MipSlice = mBaseMipLevel;
						dsvDesc.Texture2DArray.FirstArraySlice = mBaseArrayLayer;
						dsvDesc.Texture2DArray.ArraySize = mArrayLayerCount;
					default:
					}
				}

				nativeDevice.CreateDepthStencilView(mTexture.Resource, &dsvDesc, mDsvHandle);
				mHasDsv = true;
			}
		}

		// UAV
		if ((texUsage & .Storage) != 0)
		{
			D3D12_CPU_DESCRIPTOR_HANDLE cpuHandle;
			D3D12_GPU_DESCRIPTOR_HANDLE gpuHandle;
			if (mDevice.CbvSrvUavCpuHeap.Allocate(out cpuHandle, out gpuHandle))
			{
				D3D12_UNORDERED_ACCESS_VIEW_DESC uavDesc = .();
				uavDesc.Format = DX12Conversions.ToDxgiFormat(mFormat);
				uavDesc.ViewDimension = DX12Conversions.ToDx12UavDimension(mDimension);

				switch (mDimension)
				{
				case .Texture2D:
					uavDesc.Texture2D.MipSlice = mBaseMipLevel;
					uavDesc.Texture2D.PlaneSlice = 0;
				case .Texture2DArray:
					uavDesc.Texture2DArray.MipSlice = mBaseMipLevel;
					uavDesc.Texture2DArray.FirstArraySlice = mBaseArrayLayer;
					uavDesc.Texture2DArray.ArraySize = mArrayLayerCount;
				case .Texture3D:
					uavDesc.Texture3D.MipSlice = mBaseMipLevel;
					uavDesc.Texture3D.FirstWSlice = 0;
					uavDesc.Texture3D.WSize = mTexture.Depth;
				default:
				}

				nativeDevice.CreateUnorderedAccessView(mTexture.Resource, null, &uavDesc, cpuHandle);
				mUavHandle = cpuHandle;
				mHasUav = true;
			}
		}
	}
}
