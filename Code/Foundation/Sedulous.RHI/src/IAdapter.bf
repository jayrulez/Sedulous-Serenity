namespace Sedulous.RHI;

using System;

/// Information about a GPU adapter.
struct AdapterInfo
{
	/// Adapter name/description.
	public String Name;
	/// Vendor ID.
	public uint32 VendorId;
	/// Device ID.
	public uint32 DeviceId;
	/// Adapter type.
	public AdapterType Type;

	public this()
	{
		Name = new .();
		VendorId = 0;
		DeviceId = 0;
		Type = .Unknown;
	}

	public void Dispose() mut
	{
		delete Name;
		Name = null;
	}
}

/// A GPU adapter (physical device).
interface IAdapter
{
	/// Gets information about this adapter.
	AdapterInfo Info { get; }

	/// Creates a logical device from this adapter.
	Result<IDevice> CreateDevice();
}
