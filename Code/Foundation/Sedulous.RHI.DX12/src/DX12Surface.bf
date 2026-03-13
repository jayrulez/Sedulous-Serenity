namespace Sedulous.RHI.DX12;

using System;
using Win32.Foundation;
using Sedulous.RHI;

/// DX12 implementation of ISurface. Wraps an HWND.
class DX12Surface : ISurface
{
	private HWND mHwnd = 0;

	public this(void* windowHandle)
	{
		mHwnd = (HWND)(int)windowHandle;
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		mHwnd = default;
	}

	public bool IsValid => mHwnd != 0;
	public HWND Hwnd => mHwnd;
}
