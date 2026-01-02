namespace Sedulous.RHI;

using System;

/// A group of resource bindings matching a bind group layout.
interface IBindGroup : IDisposable
{
	/// The layout this bind group conforms to.
	IBindGroupLayout Layout { get; }
}
