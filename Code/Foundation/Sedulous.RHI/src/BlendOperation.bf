namespace Sedulous.RHI;

/// Blend operations for combining source and destination colors.
enum BlendOperation
{
	/// Result = source + destination.
	Add,
	/// Result = source - destination.
	Subtract,
	/// Result = destination - source.
	ReverseSubtract,
	/// Result = min(source, destination).
	Min,
	/// Result = max(source, destination).
	Max,
}
