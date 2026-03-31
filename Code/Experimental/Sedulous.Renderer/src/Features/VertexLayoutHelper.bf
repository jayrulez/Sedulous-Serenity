namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Geometry;

typealias RHIVertexAttribute = Sedulous.RHI.VertexAttribute;

/// Provides reusable vertex buffer layout descriptors for standard mesh formats.
static class VertexLayoutHelper
{
	/// Static mesh vertex attributes (persist for the lifetime of the program).
	private static RHIVertexAttribute[5] sStaticMeshAttrs = .(
		.() { Format = .Float32x3, Offset = 0,  ShaderLocation = 0 }, // Position
		.() { Format = .Float32x3, Offset = 12, ShaderLocation = 1 }, // Normal
		.() { Format = .Float32x2, Offset = 24, ShaderLocation = 2 }, // TexCoord
		.() { Format = .Unorm8x4,  Offset = 32, ShaderLocation = 3 }, // Color
		.() { Format = .Float32x3, Offset = 36, ShaderLocation = 4 }  // Tangent
		);

	/// Previous-frame position attribute for skinned motion vectors (vertex slot 1).
	private static RHIVertexAttribute[1] sPrevPositionAttrs = .(
		.() { Format = .Float32x3, Offset = 0,  ShaderLocation = 5 }  // PrevPosition
		);

	/// GPU-driven object index attribute (vertex slot 1, per-instance step).
	/// The instance buffer contains uint32 objectIndex values.
	/// Hardware instance fetch uses firstInstance from indirect commands.
	private static RHIVertexAttribute[1] sObjectIndexAttrs = .(
		.() { Format = .Uint32, Offset = 0, ShaderLocation = 5 }  // ObjectIndex
		);

	/// Instance layout attributes (persist for the lifetime of the program).
	private static RHIVertexAttribute[4] sInstanceAttrs = .(
		.() { Format = .Float32x4, Offset = 0,  ShaderLocation = 5 }, // WorldMatrix row 0
		.() { Format = .Float32x4, Offset = 16, ShaderLocation = 6 }, // WorldMatrix row 1
		.() { Format = .Float32x4, Offset = 32, ShaderLocation = 7 }, // WorldMatrix row 2
		.() { Format = .Float32x4, Offset = 48, ShaderLocation = 8 }  // WorldMatrix row 3
		);

	/// Returns the VertexBufferLayout for StaticMeshVertex (48 bytes).
	/// Attributes: Position(0), Normal(1), TexCoord(2), Color(3), Tangent(4).
	/// All semantics use TEXCOORD for DX12 compatibility.
	public static VertexBufferLayout GetStaticMeshLayout()
	{
		static int logged = 0;

		if (logged++ < 1)
		{
			for (int i = 0; i < sStaticMeshAttrs.Count; i++)
			{
				Console.WriteLine(scope $"Format: {sStaticMeshAttrs[i].Format} Offset: {sStaticMeshAttrs[i].Offset} ShaderLocation: {sStaticMeshAttrs[i].ShaderLocation}");
			}
		}

		return VertexBufferLayout()
			{
				Stride = (uint32)sizeof(StaticMeshVertex),
				StepMode = .Vertex,
				Attributes = Span<RHIVertexAttribute>(&sStaticMeshAttrs[0], 5)
			};
	}

	/// Returns the VertexBufferLayout for previous-frame skinned positions (12 bytes).
	/// Used as vertex slot 1 for skinned motion vector rendering.
	/// Attribute: PrevPosition(5) — float3 at offset 0.
	public static VertexBufferLayout GetPrevPositionLayout()
	{
		return VertexBufferLayout()
			{
				Stride = 12,
				StepMode = .Vertex,
				Attributes = Span<RHIVertexAttribute>(&sPrevPositionAttrs[0], 1)
			};
	}

	/// Returns the VertexBufferLayout for the GPU-driven object index (4 bytes, per-instance).
	/// Used as vertex slot 1 for GPU-driven rendering.
	/// The instance buffer contains uint32 objectIndex values that index into GPUSceneBuffer.
	public static VertexBufferLayout GetObjectIndexLayout()
	{
		return VertexBufferLayout()
			{
				Stride = 4,
				StepMode = .Instance,
				Attributes = Span<RHIVertexAttribute>(&sObjectIndexAttrs[0], 1)
			};
	}

	/// Returns the VertexBufferLayout for InstanceData (64 bytes).
	/// Matrix rows at ShaderLocations 5-8, per-instance step mode.
	public static VertexBufferLayout GetInstanceLayout()
	{
		static int logged = 0;

		if (logged++ < 1)
		{
			for (int i = 0; i < sInstanceAttrs.Count; i++)
			{
				Console.WriteLine(scope $"Format: {sInstanceAttrs[i].Format} Offset: {sInstanceAttrs[i].Offset} ShaderLocation: {sInstanceAttrs[i].ShaderLocation}");
			}
		}

		return VertexBufferLayout()
			{
				Stride = 64,
				StepMode = .Instance,
				Attributes = Span<RHIVertexAttribute>(&sInstanceAttrs[0], 4)
			};
	}
}
