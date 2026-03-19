namespace Sedulous.RHI.DX12;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of IBindGroupLayout.
class DX12BindGroupLayout : IBindGroupLayout
{
	private List<BindGroupLayoutEntry> mEntries = new .() ~ delete _;
	private uint32 mCbvSrvUavCount;
	private uint32 mSamplerCount;
	private uint32 mDynamicOffsetCount;
	private uint32 mDynamicCbvSrvUavCount;

	public this(BindGroupLayoutDesc descriptor)
	{
		for (let entry in descriptor.Entries)
		{
			mEntries.Add(entry);
			if (DX12Conversions.IsSamplerBinding(entry.Type))
				mSamplerCount++;
			else
				mCbvSrvUavCount++;
			if (entry.HasDynamicOffset)
			{
				mDynamicOffsetCount++;
				if (!DX12Conversions.IsSamplerBinding(entry.Type))
					mDynamicCbvSrvUavCount++;
			}
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
	}

	public List<BindGroupLayoutEntry> Entries => mEntries;
	public uint32 CbvSrvUavCount => mCbvSrvUavCount;
	public uint32 SamplerCount => mSamplerCount;
	public uint32 DynamicOffsetCount => mDynamicOffsetCount;

	/// CBV/SRV/UAV entries that go into descriptor tables (excludes dynamic offset entries).
	public uint32 CbvSrvUavTableCount => mCbvSrvUavCount - mDynamicCbvSrvUavCount;
}
