namespace Sedulous.RHI;

/// Type of GPU adapter.
enum AdapterType
{
	/// Discrete GPU (dedicated graphics card).
	Discrete,
	/// Integrated GPU (part of CPU).
	Integrated,
	/// Software/CPU implementation.
	Software,
	/// Unknown adapter type.
	Unknown,
}
