using System;
namespace Sedulous.RHI;

/// Encodes commands within a render pass.
interface IRenderPassEncoder
{
	/// Sets the render pipeline.
	void SetPipeline(IRenderPipeline pipeline);

	/// Sets a bind group at the specified index.
	void SetBindGroup(uint32 index, IBindGroup bindGroup, Span<uint32> dynamicOffsets = default);

	/// Sets a vertex buffer at the specified slot.
	void SetVertexBuffer(uint32 slot, IBuffer buffer, uint64 offset = 0);

	/// Sets the index buffer.
	void SetIndexBuffer(IBuffer buffer, IndexFormat format, uint64 offset = 0);

	/// Sets the viewport.
	void SetViewport(float x, float y, float width, float height, float minDepth, float maxDepth);

	/// Sets the scissor rectangle.
	void SetScissorRect(int32 x, int32 y, uint32 width, uint32 height);

	/// Sets the blend constant color.
	void SetBlendConstant(float r, float g, float b, float a);

	/// Sets the stencil reference value.
	void SetStencilReference(uint32 reference);

	/// Draws primitives.
	void Draw(uint32 vertexCount, uint32 instanceCount = 1, uint32 firstVertex = 0, uint32 firstInstance = 0);

	/// Draws indexed primitives.
	void DrawIndexed(uint32 indexCount, uint32 instanceCount = 1, uint32 firstIndex = 0, int32 baseVertex = 0, uint32 firstInstance = 0);

	/// Draws primitives using indirect parameters from a buffer.
	void DrawIndirect(IBuffer indirectBuffer, uint64 indirectOffset);

	/// Draws indexed primitives using indirect parameters from a buffer.
	void DrawIndexedIndirect(IBuffer indirectBuffer, uint64 indirectOffset);

	/// Ends the render pass.
	void End();
}
