namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Materials;

/// Visibility and rendering flags for mesh proxies.
[AllowDuplicates]
public enum MeshFlags : uint32
{
	None = 0,
	Visible = 1 << 0,
	CastShadows = 1 << 1,
	ReceiveShadows = 1 << 2,
	MotionVectors = 1 << 3,
	Static = 1 << 4,
	DefaultOpaque = Visible | CastShadows | ReceiveShadows | MotionVectors,
	DefaultTransparent = Visible | ReceiveShadows | MotionVectors
}

/// Proxy for a static mesh in the render world.
public struct StaticMeshProxy
{
	public GPUMeshHandle MeshHandle;
	public MaterialInstance[RenderConfig.MaxMaterialsPerMesh] Materials;
	public int32 MaterialCount;
	public Matrix WorldMatrix;
	public Matrix PrevWorldMatrix;
	public BoundingBox WorldBounds;
	public BoundingBox LocalBounds;
	public MeshFlags Flags;
	public uint8 LODLevel;
	public uint32 LayerMask;
	public uint32 SortKey;
	public uint32 Generation;
	public bool IsActive;
	public IBindGroup ObjectBindGroup;

	public bool IsVisible => (Flags & .Visible) != 0 && IsActive;
	public bool CastsShadows => (Flags & .CastShadows) != 0;
	public bool ReceivesShadows => (Flags & .ReceiveShadows) != 0;
	public bool HasMotionVectors => (Flags & .MotionVectors) != 0;
	public bool IsStatic => (Flags & .Static) != 0;

	public void SetTransform(Matrix worldMatrix) mut
	{
		PrevWorldMatrix = WorldMatrix;
		WorldMatrix = worldMatrix;
		WorldBounds = BoundsHelper.TransformBounds(LocalBounds, worldMatrix);
	}

	public void SetTransformImmediate(Matrix worldMatrix) mut
	{
		WorldMatrix = worldMatrix;
		PrevWorldMatrix = worldMatrix;
		WorldBounds = BoundsHelper.TransformBounds(LocalBounds, worldMatrix);
	}

	public void SetLocalBounds(BoundingBox bounds) mut
	{
		LocalBounds = bounds;
		WorldBounds = BoundsHelper.TransformBounds(bounds, WorldMatrix);
	}

	public void Reset() mut
	{
		MeshHandle = .Invalid;
		Materials = .();
		MaterialCount = 0;
		WorldMatrix = .Identity;
		PrevWorldMatrix = .Identity;
		WorldBounds = .(Vector3.Zero, Vector3.Zero);
		LocalBounds = .(Vector3.Zero, Vector3.Zero);
		Flags = .None;
		LODLevel = 0;
		LayerMask = 0xFFFFFFFF;
		SortKey = 0;
		IsActive = false;
		ObjectBindGroup = null;
	}
}

/// Utility for bounding box transforms shared across proxy types.
public static class BoundsHelper
{
	public static BoundingBox TransformBounds(BoundingBox bounds, Matrix matrix)
	{
		Vector3[8] corners = .(
			.(bounds.Min.X, bounds.Min.Y, bounds.Min.Z),
			.(bounds.Max.X, bounds.Min.Y, bounds.Min.Z),
			.(bounds.Min.X, bounds.Max.Y, bounds.Min.Z),
			.(bounds.Max.X, bounds.Max.Y, bounds.Min.Z),
			.(bounds.Min.X, bounds.Min.Y, bounds.Max.Z),
			.(bounds.Max.X, bounds.Min.Y, bounds.Max.Z),
			.(bounds.Min.X, bounds.Max.Y, bounds.Max.Z),
			.(bounds.Max.X, bounds.Max.Y, bounds.Max.Z)
		);

		Vector3 newMin = .(float.MaxValue, float.MaxValue, float.MaxValue);
		Vector3 newMax = .(float.MinValue, float.MinValue, float.MinValue);

		for (let corner in corners)
		{
			let transformed = Vector3.Transform(corner, matrix);
			newMin = Vector3.Min(newMin, transformed);
			newMax = Vector3.Max(newMax, transformed);
		}

		return .(newMin, newMax);
	}

	public static BoundingBox ExpandBounds(BoundingBox bounds, float scale)
	{
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let halfExtent = (bounds.Max - bounds.Min) * 0.5f * scale;
		return .(center - halfExtent, center + halfExtent);
	}
}
