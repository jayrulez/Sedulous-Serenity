namespace Sedulous.RHI.DX12;

using System;
using Win32.Graphics.Dxgi;
using Win32.Foundation;
using Sedulous.RHI;

using Win32;

/// DX12 implementation of IAdapter.
class DX12Adapter : IAdapter
{
	private DX12Backend mBackend;
	private IDXGIAdapter1* mAdapter;
	private AdapterInfo mInfo;

	public this(DX12Backend backend, IDXGIAdapter1* adapter)
	{
		mBackend = backend;
		mAdapter = adapter;
		mAdapter.AddRef();

		DXGI_ADAPTER_DESC1 desc = .();
		if (SUCCEEDED(mAdapter.GetDesc1(&desc)))
		{
			mInfo = .();

			// Convert wide char description to String
			for (int i = 0; i < 128; i++)
			{
				let c = desc.Description[i];
				if (c == 0) break;
				mInfo.Name.Append((char8)c);
			}

			mInfo.VendorId = desc.VendorId;
			mInfo.DeviceId = desc.DeviceId;

			// Determine adapter type from flags
			if ((desc.Flags & 2) != 0) // DXGI_ADAPTER_FLAG_SOFTWARE
				mInfo.Type = .Software;
			else if (desc.DedicatedVideoMemory > 0)
				mInfo.Type = .Discrete;
			else
				mInfo.Type = .Integrated;
		}
	}

	public ~this()
	{
		mInfo.Dispose();
		if (mAdapter != null)
		{
			mAdapter.Release();
			mAdapter = null;
		}
	}

	public AdapterInfo Info => mInfo;
	public DX12Backend Backend => mBackend;
	public IDXGIAdapter1* Adapter => mAdapter;

	public Result<IDevice> CreateDevice()
	{
		let device = new DX12Device(this);
		if (!device.IsInitialized)
		{
			delete device;
			return .Err;
		}
		return .Ok(device);
	}
}
