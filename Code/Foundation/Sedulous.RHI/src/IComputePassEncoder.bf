using System;
namespace Sedulous.RHI;

/// Encodes commands within a compute pass.
interface IComputePassEncoder
{
	/// Sets the compute pipeline.
	void SetPipeline(IComputePipeline pipeline);

	/// Sets a bind group at the specified index.
	void SetBindGroup(uint32 index, IBindGroup bindGroup, Span<uint32> dynamicOffsets = default);

	/// Dispatches compute work.
	void Dispatch(uint32 workgroupCountX, uint32 workgroupCountY = 1, uint32 workgroupCountZ = 1);

	/// Dispatches compute work using indirect parameters from a buffer.
	void DispatchIndirect(IBuffer indirectBuffer, uint64 indirectOffset);

	/// Ends the compute pass.
	void End();
}
