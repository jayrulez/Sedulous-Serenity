namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;
using Sedulous.Materials;

/// Visibility and rendering flags for mesh proxies.
[AllowDuplicates]
public enum MeshFlags : uint32
{
	None = 0,

	/// Mesh is visible and should be rendered.
	Visible = 1 << 0,

	/// Mesh casts shadows.
	CastShadows = 1 << 1,

	/// Mesh receives shadows.
	ReceiveShadows = 1 << 2,

	/// Mesh contributes to motion vectors.
	MotionVectors = 1 << 3,

	/// Mesh is static (never moves, can be baked into acceleration structures).
	Static = 1 << 4,

	/// Default flags for opaque meshes.
	DefaultOpaque = Visible | CastShadows | ReceiveShadows | MotionVectors,

	/// Default flags for transparent meshes.
	DefaultTransparent = Visible | ReceiveShadows | MotionVectors
}

/// Proxy for a static mesh in the render world.
/// Contains all data needed to render a mesh instance.
public struct MeshProxy
{
	/// Handle to the GPU mesh data.
	public GPUMeshHandle MeshHandle;

	/// Material instance for rendering.
	public MaterialInstance Material;

	/// World transform matrix.
	public Matrix WorldMatrix;

	/// Previous frame world matrix (for motion vectors).
	public Matrix PrevWorldMatrix;

	/// Normal matrix (inverse transpose of world matrix, for lighting).
	public Matrix NormalMatrix;

	/// World-space bounding box.
	public BoundingBox WorldBounds;

	/// Local-space bounding box (cached from mesh).
	public BoundingBox LocalBounds;

	/// Rendering flags.
	public MeshFlags Flags;

	/// LOD level (0 = highest detail).
	public uint8 LODLevel;

	/// Render layer mask (for layer-based rendering).
	public uint32 LayerMask;

	/// Custom sort key for render order control.
	public uint32 SortKey;

	/// Generation counter (for handle validation).
	public uint32 Generation;

	/// Whether this proxy slot is in use.
	public bool IsActive;

	/// Whether the proxy is visible.
	public bool IsVisible => (Flags & .Visible) != 0 && IsActive;

	/// Whether the mesh casts shadows.
	public bool CastsShadows => (Flags & .CastShadows) != 0;

	/// Whether the mesh receives shadows.
	public bool ReceivesShadows => (Flags & .ReceiveShadows) != 0;

	/// Whether motion vectors should be generated.
	public bool HasMotionVectors => (Flags & .MotionVectors) != 0;

	/// Whether the mesh is static.
	public bool IsStatic => (Flags & .Static) != 0;

	/// Updates the world transform and derived values.
	public void SetTransform(Matrix worldMatrix) mut
	{
		PrevWorldMatrix = WorldMatrix;
		WorldMatrix = worldMatrix;

		// Compute normal matrix (inverse transpose)
		Matrix invWorld;
		if (Matrix.TryInvert(worldMatrix, out invWorld))
			NormalMatrix = Matrix.Transpose(invWorld);
		else
			NormalMatrix = .Identity;

		// Transform local bounds to world space
		WorldBounds = TransformBounds(LocalBounds, worldMatrix);
	}

	/// Updates transform without saving previous (for initialization).
	public void SetTransformImmediate(Matrix worldMatrix) mut
	{
		WorldMatrix = worldMatrix;
		PrevWorldMatrix = worldMatrix;

		Matrix invWorld;
		if (Matrix.TryInvert(worldMatrix, out invWorld))
			NormalMatrix = Matrix.Transpose(invWorld);
		else
			NormalMatrix = .Identity;

		WorldBounds = TransformBounds(LocalBounds, worldMatrix);
	}

	/// Sets the local bounds (typically from the mesh data).
	public void SetLocalBounds(BoundingBox bounds) mut
	{
		LocalBounds = bounds;
		WorldBounds = TransformBounds(bounds, WorldMatrix);
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		MeshHandle = .Invalid;
		Material = null;
		WorldMatrix = .Identity;
		PrevWorldMatrix = .Identity;
		NormalMatrix = .Identity;
		WorldBounds = .(Vector3.Zero, Vector3.Zero);
		LocalBounds = .(Vector3.Zero, Vector3.Zero);
		Flags = .None;
		LODLevel = 0;
		LayerMask = 0xFFFFFFFF;
		SortKey = 0;
		IsActive = false;
	}

	/// Transforms a bounding box by a matrix.
	private static BoundingBox TransformBounds(BoundingBox bounds, Matrix matrix)
	{
		// Transform all 8 corners and find new AABB
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
}
