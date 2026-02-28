namespace Sedulous.RHI;

/// Operations for stencil tests.
enum StencilOperation
{
	/// Keep the current stencil value.
	Keep,
	/// Set stencil value to zero.
	Zero,
	/// Replace stencil value with reference value.
	Replace,
	/// Increment and clamp stencil value.
	IncrementClamp,
	/// Decrement and clamp stencil value.
	DecrementClamp,
	/// Bitwise invert stencil value.
	Invert,
	/// Increment and wrap stencil value.
	IncrementWrap,
	/// Decrement and wrap stencil value.
	DecrementWrap,
}
