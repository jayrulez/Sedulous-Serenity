namespace Sedulous.RHI;

using System;

/// A synchronization primitive for CPU/GPU coordination.
interface IFence : IDisposable
{
	/// Returns true if the fence has been signaled.
	bool IsSignaled { get; }

	/// Waits for the fence to be signaled.
	/// Returns true if the fence was signaled, false if timeout occurred.
	bool Wait(uint64 timeoutNanoseconds = uint64.MaxValue);

	/// Resets the fence to unsignaled state.
	void Reset();
}
