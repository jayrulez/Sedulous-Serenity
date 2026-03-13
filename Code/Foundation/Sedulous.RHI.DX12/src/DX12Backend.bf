namespace Sedulous.RHI.DX12;

using System;
using System.Collections;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Dxgi;
using Win32.Foundation;
using Win32.System.Com;
using Sedulous.RHI;

using Win32;

/// DX12 implementation of IBackend.
class DX12Backend : IBackend
{
	private IDXGIFactory6* mFactory;
	private bool mValidationEnabled;
	private bool mDebugEnabled;
	private List<DX12Adapter> mAdapters = new .() ~ DeleteContainerAndItems!(_);

	/// Creates a new DX12 backend.
	public this(bool enableValidation = true)
	{
		mValidationEnabled = enableValidation;
		Initialize();
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		for (let adapter in mAdapters)
			delete adapter;
		mAdapters.Clear();

		if (mFactory != null)
		{
			mFactory.Release();
			mFactory = null;
		}
	}

	public bool IsInitialized => mFactory != null;
	public bool DebugEnabled => mDebugEnabled;

	public void EnumerateAdapters(List<IAdapter> adapters)
	{
		if (mAdapters.Count == 0)
			EnumerateGpuAdapters();

		for (let adapter in mAdapters)
			adapters.Add(adapter);
	}

	public Result<ISurface> CreateSurface(void* windowHandle, void* displayHandle = null)
	{
		if (mFactory == null)
			return .Err;

		return .Ok(new DX12Surface(windowHandle));
	}

	public IDXGIFactory6* Factory => mFactory;

	private void Initialize()
	{
		// Enable debug layer if requested
		if (mValidationEnabled)
		{
			ID3D12Debug* debugController = null;
			if (SUCCEEDED(D3D12GetDebugInterface(ID3D12Debug.IID, (void**)&debugController)))
			{
				debugController.EnableDebugLayer();
				debugController.Release();
				mDebugEnabled = true;
				Console.WriteLine("[DX12] Debug layer enabled");
			}
			else
			{
				Console.WriteLine("[DX12] WARNING: Debug layer not available");
			}
		}

		// Create DXGI factory
		uint32 factoryFlags = mDebugEnabled ? 1 : 0; // DXGI_CREATE_FACTORY_DEBUG = 1

		IDXGIFactory6* factory6 = null;
		HRESULT hr = CreateDXGIFactory2(factoryFlags, IDXGIFactory6.IID, (void**)&factory6);
		if (SUCCEEDED(hr))
		{
			mFactory = factory6;
		}
		else
		{
			// Fallback to factory4
			IDXGIFactory4* factory4 = null;
			hr = CreateDXGIFactory2(factoryFlags, IDXGIFactory4.IID, (void**)&factory4);
			if (SUCCEEDED(hr))
			{
				// QI for factory6
				hr = factory4.QueryInterface(IDXGIFactory6.IID, (void**)&mFactory);
				factory4.Release();
				if (!SUCCEEDED(hr))
					mFactory = null;
			}
		}

		if (mFactory != null)
			Console.WriteLine("[DX12] DXGI Factory created");
		else
			Console.Error.WriteLine("[DX12] ERROR: Failed to create DXGI Factory");
	}

	private void EnumerateGpuAdapters()
	{
		if (mFactory == null)
			return;

		uint32 adapterIndex = 0;
		IDXGIAdapter1* adapter = null;

		while (true)
		{
			HRESULT hr = mFactory.EnumAdapterByGpuPreference(
				adapterIndex,
				.DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,
				IDXGIAdapter1.IID,
				(void**)&adapter);

			if (!SUCCEEDED(hr))
				break;

			// Check if the adapter supports D3D12
			hr = D3D12CreateDevice((IUnknown*)adapter, .D3D_FEATURE_LEVEL_12_0, ID3D12Device.IID, null);
			if (SUCCEEDED(hr))
			{
				mAdapters.Add(new DX12Adapter(this, adapter));
			}

			adapter.Release();
			adapterIndex++;
		}
	}
}
