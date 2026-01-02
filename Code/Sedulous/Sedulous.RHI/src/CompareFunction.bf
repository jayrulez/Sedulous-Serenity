namespace Sedulous.RHI;

/// Comparison functions for depth/stencil tests.
enum CompareFunction
{
	/// Comparison never passes.
	Never,
	/// Passes if new value < existing value.
	Less,
	/// Passes if new value == existing value.
	Equal,
	/// Passes if new value <= existing value.
	LessEqual,
	/// Passes if new value > existing value.
	Greater,
	/// Passes if new value != existing value.
	NotEqual,
	/// Passes if new value >= existing value.
	GreaterEqual,
	/// Comparison always passes.
	Always,
}
