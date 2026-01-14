namespace Sedulous.RendererNext;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// A single draw command for rendering.
struct DrawCommand
{
	/// World transform matrix.
	public Matrix Transform;

	/// World position (for sorting/culling).
	public Vector3 WorldPosition;

	/// Blend mode for this draw.
	public BlendMode BlendMode;

	/// Vertex buffer to draw from.
	public IBuffer VertexBuffer;

	/// Index buffer (optional, null for non-indexed draws).
	public IBuffer IndexBuffer;

	/// Number of vertices to draw.
	public uint32 VertexCount;

	/// Number of indices to draw (0 for non-indexed).
	public uint32 IndexCount;

	/// Offset into the vertex buffer.
	public uint32 VertexOffset;

	/// Offset into the index buffer.
	public uint32 IndexOffset;

	/// Instance count (1 for non-instanced).
	public uint32 InstanceCount;

	/// First instance index.
	public uint32 FirstInstance;

	/// Material index for this draw.
	public uint32 MaterialIndex;

	/// Mesh/object ID for identification.
	public uint32 ObjectId;

	/// Layer mask for filtering.
	public uint32 LayerMask;

	/// Sorting key (for depth sorting).
	public float SortKey;

	/// Creates a simple non-indexed draw command.
	public static Self Simple(Matrix transform, IBuffer vertexBuffer, uint32 vertexCount, BlendMode blendMode = .Opaque)
	{
		return .()
		{
			Transform = transform,
			WorldPosition = transform.Translation,
			BlendMode = blendMode,
			VertexBuffer = vertexBuffer,
			IndexBuffer = null,
			VertexCount = vertexCount,
			IndexCount = 0,
			VertexOffset = 0,
			IndexOffset = 0,
			InstanceCount = 1,
			FirstInstance = 0,
			MaterialIndex = 0,
			ObjectId = 0,
			LayerMask = 0xFFFFFFFF,
			SortKey = 0
		};
	}

	/// Creates an indexed draw command.
	public static Self Indexed(Matrix transform, IBuffer vertexBuffer, IBuffer indexBuffer, uint32 indexCount, BlendMode blendMode = .Opaque)
	{
		return .()
		{
			Transform = transform,
			WorldPosition = transform.Translation,
			BlendMode = blendMode,
			VertexBuffer = vertexBuffer,
			IndexBuffer = indexBuffer,
			VertexCount = 0,
			IndexCount = indexCount,
			VertexOffset = 0,
			IndexOffset = 0,
			InstanceCount = 1,
			FirstInstance = 0,
			MaterialIndex = 0,
			ObjectId = 0,
			LayerMask = 0xFFFFFFFF,
			SortKey = 0
		};
	}
}

/// Batch of draw commands with shared state.
struct DrawBatch
{
	/// Pipeline to use for this batch.
	public IRenderPipeline Pipeline;

	/// Bind group for per-batch resources (material, textures).
	public IBindGroup BindGroup;

	/// Start index in the draw command list.
	public int32 StartIndex;

	/// Number of draw commands in this batch.
	public int32 Count;
}
