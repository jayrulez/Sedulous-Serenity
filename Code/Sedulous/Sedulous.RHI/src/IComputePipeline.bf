namespace Sedulous.RHI;

using System;

/// A compiled compute pipeline.
interface IComputePipeline : IDisposable
{
	/// The pipeline layout.
	IPipelineLayout Layout { get; }
}
