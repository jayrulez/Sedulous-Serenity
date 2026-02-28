namespace Sedulous.RHI;

using System;

/// A compiled graphics/render pipeline.
interface IRenderPipeline : IDisposable
{
	/// The pipeline layout.
	IPipelineLayout Layout { get; }
}
