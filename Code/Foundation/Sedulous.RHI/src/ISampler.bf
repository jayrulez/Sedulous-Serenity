namespace Sedulous.RHI;

using System;

/// A texture sampler.
interface ISampler : IDisposable
{
	/// Debug name for tracking resource leaks.
	StringView DebugName { get; }
}
