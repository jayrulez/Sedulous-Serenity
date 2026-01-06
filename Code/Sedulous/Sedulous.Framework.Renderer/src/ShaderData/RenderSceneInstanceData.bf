namespace Sedulous.Framework.Renderer;

using Sedulous.Mathematics;
using System;

/// Per-instance GPU data (80 bytes) - transform matrix rows + color.
/// Used for legacy rendering path without material system.
[CRepr]
struct RenderSceneInstanceData
{
	public Vector4 Row0;
	public Vector4 Row1;
	public Vector4 Row2;
	public Vector4 Row3;
	public Vector4 Color;

	public this(Matrix transform, Vector4 color)
	{
		Row0 = .(transform.M11, transform.M12, transform.M13, transform.M14);
		Row1 = .(transform.M21, transform.M22, transform.M23, transform.M24);
		Row2 = .(transform.M31, transform.M32, transform.M33, transform.M34);
		Row3 = .(transform.M41, transform.M42, transform.M43, transform.M44);
		Color = color;
	}
}

/// Per-instance GPU data for material rendering (80 bytes).
/// Transform matrix rows + tint color + flags.
[CRepr]
struct MaterialInstanceData
{
	public Vector4 Row0;
	public Vector4 Row1;
	public Vector4 Row2;
	public Vector4 Row3;
	public Vector4 TintAndFlags;  // xyz=tint, w=flags

	public this(Matrix transform, Vector3 tint, uint32 flags)
	{
		var flags;
		Row0 = .(transform.M11, transform.M12, transform.M13, transform.M14);
		Row1 = .(transform.M21, transform.M22, transform.M23, transform.M24);
		Row2 = .(transform.M31, transform.M32, transform.M33, transform.M34);
		Row3 = .(transform.M41, transform.M42, transform.M43, transform.M44);
		TintAndFlags = .(tint.X, tint.Y, tint.Z, *(float*)&flags);
	}

	public this(Matrix transform, Vector3 tint)
	{
		Row0 = .(transform.M11, transform.M12, transform.M13, transform.M14);
		Row1 = .(transform.M21, transform.M22, transform.M23, transform.M24);
		Row2 = .(transform.M31, transform.M32, transform.M33, transform.M34);
		Row3 = .(transform.M41, transform.M42, transform.M43, transform.M44);
		TintAndFlags = .(tint.X, tint.Y, tint.Z, 0);
	}
}

/// A batch of draw calls sharing the same mesh and material.
struct DrawBatch
{
	/// Handle to the GPU mesh.
	public GPUMeshHandle Mesh;

	/// Handle to the material instance.
	public MaterialInstanceHandle Material;

	/// Offset into the instance data buffer.
	public int32 InstanceOffset;

	/// Number of instances in this batch.
	public int32 InstanceCount;

	public this(GPUMeshHandle mesh, MaterialInstanceHandle material, int32 offset, int32 count)
	{
		Mesh = mesh;
		Material = material;
		InstanceOffset = offset;
		InstanceCount = count;
	}
}
