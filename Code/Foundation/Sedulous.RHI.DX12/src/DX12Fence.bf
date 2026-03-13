namespace Sedulous.RHI.DX12;

using System;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Foundation;
using Win32.System.Threading;
using Sedulous.RHI;

/// DX12 implementation of IFence using ID3D12Fence + Win32 event.
class DX12Fence : IFence
{
	private DX12Device mDevice;
	private ID3D12Fence* mFence;
	private HANDLE mEvent;
	private uint64 mFenceValue;

	public this(DX12Device device, bool signaled = false)
	{
		mDevice = device;
		mFenceValue = signaled ? 1 : 0;
		CreateFence(signaled);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mEvent != 0)
		{
			CloseHandle(mEvent);
			mEvent = default;
		}

		if (mFence != null)
		{
			mFence.Release();
			mFence = null;
		}
	}

	public bool IsValid => mFence != null;
	public ID3D12Fence* NativeFence => mFence;
	public uint64 FenceValue => mFenceValue;
	public ref uint64 FenceValueRef => ref mFenceValue;

	public bool IsSignaled
	{
		get
		{
			if (mFence == null)
				return false;
			return mFence.GetCompletedValue() >= mFenceValue;
		}
	}

	public bool Wait(uint64 timeoutNanoseconds = uint64.MaxValue)
	{
		if (mFence == null)
			return false;

		if (mFence.GetCompletedValue() >= mFenceValue)
			return true;

		mFence.SetEventOnCompletion(mFenceValue, mEvent);

		// Convert nanoseconds to milliseconds
		uint32 timeoutMs;
		if (timeoutNanoseconds == uint64.MaxValue)
			timeoutMs = uint32.MaxValue;
		else
			timeoutMs = (uint32)(timeoutNanoseconds / 1000000);

		return WaitForSingleObjectEx(mEvent, timeoutMs, FALSE) == 0; // WAIT_OBJECT_0
	}

	public void Reset()
	{
		// D3D12 fences are monotonic — we "reset" by moving to a new value
		// The fence will become unsignaled relative to the new target
	}

	/// Signals the fence on the CPU side.
	public void Signal(uint64 value)
	{
		mFenceValue = value;
		mFence.Signal(value);
	}

	/// Increments the fence value and returns the new value (for queue signal).
	public uint64 IncrementAndGetValue()
	{
		return ++mFenceValue;
	}

	private void CreateFence(bool signaled)
	{
		uint64 initialValue = signaled ? 1 : 0;

		HRESULT hr = mDevice.NativeDevice.CreateFence(
			initialValue,
			.D3D12_FENCE_FLAG_NONE,
			ID3D12Fence.IID,
			(void**)&mFence);

		if (!SUCCEEDED(hr))
		{
			mFence = null;
			return;
		}

		mEvent = CreateEventW(null, FALSE, FALSE, null);
	}
}
