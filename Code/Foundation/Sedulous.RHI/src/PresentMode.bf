namespace Sedulous.RHI;

/// Swap chain presentation mode.
enum PresentMode
{
	/// No vertical sync, may tear. Lowest latency.
	Immediate,
	/// Vertical sync with FIFO queue. No tearing, may have latency.
	Fifo,
	/// Vertical sync with single frame queue. No tearing, lower latency than Fifo.
	Mailbox,
}
