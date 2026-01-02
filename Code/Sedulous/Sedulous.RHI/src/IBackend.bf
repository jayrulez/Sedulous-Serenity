namespace Sedulous.RHI;

using System;
using System.Collections;

/// A graphics backend (Vulkan, DX12, etc.).
interface IBackend : IDisposable
{
	/// Gets whether the backend was successfully initialized.
	bool IsInitialized { get; }

	/// Enumerates available GPU adapters.
	void EnumerateAdapters(List<IAdapter> adapters);

	/// Creates a surface from native window handles.
	/// For Vulkan: windowHandle is HWND (Windows) or X11 Window, displayHandle is null (Windows) or X11 Display*.
	/// For DX12: windowHandle is HWND, displayHandle is unused.
	Result<ISurface> CreateSurface(void* windowHandle, void* displayHandle = null);
}
