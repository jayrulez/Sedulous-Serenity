namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Render proxy for a skinned mesh instance in the scene.
/// Contains skeletal animation data in addition to base mesh data.
[Reflect]
struct SkinnedMeshProxy
{
	/// Unique ID for this proxy.
	public uint32 Id;

	/// World transform matrix.
	public Matrix Transform;

	/// Previous frame's transform (for motion vectors).
	public Matrix PreviousTransform;

	/// World-space bounding box (transformed).
	public BoundingBox WorldBounds;

	/// Local-space bounding box (from mesh).
	public BoundingBox LocalBounds;

	/// Handle to the GPU skinned mesh.
	public GPUSkinnedMeshHandle MeshHandle;

	/// Material instance handle.
	public MaterialInstanceHandle MaterialInstance;

	/// Bone matrix buffer (owned by component, referenced here).
	public IBuffer BoneMatrixBuffer;

	/// Object uniform buffer (owned by component, referenced here).
	public IBuffer ObjectUniformBuffer;

	/// Flags for rendering behavior.
	public SkinnedMeshProxyFlags Flags;

	/// Layer mask for culling (bitfield).
	public uint32 LayerMask;

	/// Distance from camera (calculated during visibility).
	public float DistanceToCamera;

	/// Sort key for draw call ordering.
	public uint64 SortKey;

	/// Creates an invalid proxy.
	public static Self Invalid
	{
		get
		{
			Self p = default;
			p.Id = uint32.MaxValue;
			p.Transform = .Identity;
			p.PreviousTransform = .Identity;
			p.WorldBounds = .(.Zero, .Zero);
			p.LocalBounds = .(.Zero, .Zero);
			p.MeshHandle = .Invalid;
			p.MaterialInstance = .Invalid;
			p.BoneMatrixBuffer = null;
			p.ObjectUniformBuffer = null;
			p.Flags = .None;
			p.LayerMask = 0xFFFFFFFF;
			p.DistanceToCamera = 0;
			p.SortKey = 0;
			return p;
		}
	}

	/// Creates a skinned mesh proxy with the given parameters.
	public this(uint32 id, GPUSkinnedMeshHandle mesh, Matrix transform, BoundingBox localBounds)
	{
		Id = id;
		MeshHandle = mesh;
		Transform = transform;
		PreviousTransform = transform;
		LocalBounds = localBounds;
		WorldBounds = TransformBounds(localBounds, transform);
		MaterialInstance = .Invalid;
		BoneMatrixBuffer = null;
		ObjectUniformBuffer = null;
		Flags = .CastShadows | .ReceiveShadows | .Visible;
		LayerMask = 0xFFFFFFFF;
		DistanceToCamera = 0;
		SortKey = 0;
	}

	/// Updates the world bounds from transform and local bounds.
	public void UpdateWorldBounds() mut
	{
		WorldBounds = TransformBounds(LocalBounds, Transform);
	}

	/// Transforms a bounding box by a matrix, creating a new AABB that encloses the result.
	private static BoundingBox TransformBounds(BoundingBox bounds, Matrix transform)
	{
		// Transform all 8 corners and find new min/max
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
			let transformed = Vector3.Transform(corner, transform);
			newMin.X = Math.Min(newMin.X, transformed.X);
			newMin.Y = Math.Min(newMin.Y, transformed.Y);
			newMin.Z = Math.Min(newMin.Z, transformed.Z);
			newMax.X = Math.Max(newMax.X, transformed.X);
			newMax.Y = Math.Max(newMax.Y, transformed.Y);
			newMax.Z = Math.Max(newMax.Z, transformed.Z);
		}

		return .(newMin, newMax);
	}

	/// Saves current transform as previous (call at end of frame).
	public void SavePreviousTransform() mut
	{
		PreviousTransform = Transform;
	}

	/// Checks if this proxy is valid.
	public bool IsValid => Id != uint32.MaxValue && MeshHandle.IsValid;

	/// Checks if visible.
	public bool IsVisible => Flags.HasFlag(.Visible);

	/// Checks if casts shadows.
	public bool CastsShadows => Flags.HasFlag(.CastShadows);

	/// Checks if receives shadows.
	public bool ReceivesShadows => Flags.HasFlag(.ReceiveShadows);

	/// Checks if has valid GPU buffers for rendering.
	public bool HasValidBuffers => BoneMatrixBuffer != null && ObjectUniformBuffer != null;
}

/// Flags controlling skinned mesh proxy behavior.
enum SkinnedMeshProxyFlags : uint16
{
	None = 0,
	/// Proxy is visible for rendering.
	Visible = 1 << 0,
	/// Casts shadows.
	CastShadows = 1 << 1,
	/// Receives shadows.
	ReceiveShadows = 1 << 2,
	/// Uses alpha blending (requires back-to-front sort).
	Transparent = 1 << 3,
	/// Object is dirty and needs GPU data update.
	Dirty = 1 << 4,
	/// Object was culled this frame.
	Culled = 1 << 5
}
