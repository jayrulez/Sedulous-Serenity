namespace Sedulous.Framework.Renderer;

using System;
using Sedulous.Mathematics;

/// Render proxy for a mesh instance in the scene.
/// Decoupled from gameplay entities - stores only render-relevant data.
[Reflect]
struct MeshProxy
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

	/// Handle to the GPU mesh.
	public GPUMeshHandle MeshHandle;

	/// Material instance handles for each sub-mesh.
	/// Index corresponds to SubMesh index.
	public MaterialInstanceHandle[8] MaterialInstances;

	/// Legacy material IDs for backward compatibility.
	/// Used when MaterialInstances[i].IsValid == false.
	public uint32[8] MaterialIds;

	/// Number of materials.
	public uint8 MaterialCount;

	/// Current LOD level (0 = highest detail).
	public uint8 LODLevel;

	/// Maximum LOD level available.
	public uint8 MaxLOD;

	/// Flags for rendering behavior.
	public MeshProxyFlags Flags;

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
			p.MaterialInstances = .(.Invalid, .Invalid, .Invalid, .Invalid, .Invalid, .Invalid, .Invalid, .Invalid);
			p.MaterialIds = .();
			p.MaterialCount = 0;
			p.LODLevel = 0;
			p.MaxLOD = 0;
			p.Flags = .None;
			p.LayerMask = 0xFFFFFFFF;
			p.DistanceToCamera = 0;
			p.SortKey = 0;
			return p;
		}
	}

	/// Creates a mesh proxy with the given parameters.
	public this(uint32 id, GPUMeshHandle mesh, Matrix transform, BoundingBox localBounds)
	{
		Id = id;
		MeshHandle = mesh;
		Transform = transform;
		PreviousTransform = transform;
		LocalBounds = localBounds;
		WorldBounds = TransformBounds(localBounds, transform);
		MaterialInstances = .(.Invalid, .Invalid, .Invalid, .Invalid, .Invalid, .Invalid, .Invalid, .Invalid);
		MaterialIds = .();
		MaterialCount = 0;
		LODLevel = 0;
		MaxLOD = 0;
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

	/// Sets a material instance for a sub-mesh.
	public void SetMaterialInstance(int32 subMeshIndex, MaterialInstanceHandle instance) mut
	{
		if (subMeshIndex >= 0 && subMeshIndex < 8)
		{
			MaterialInstances[subMeshIndex] = instance;
			if (subMeshIndex >= MaterialCount)
				MaterialCount = (uint8)(subMeshIndex + 1);
		}
	}

	/// Gets the material instance for a sub-mesh.
	public MaterialInstanceHandle GetMaterialInstance(int32 subMeshIndex)
	{
		if (subMeshIndex >= 0 && subMeshIndex < 8)
			return MaterialInstances[subMeshIndex];
		return .Invalid;
	}

	/// Sets a legacy material ID for a sub-mesh (backward compatibility).
	public void SetMaterial(int32 subMeshIndex, uint32 materialId) mut
	{
		if (subMeshIndex >= 0 && subMeshIndex < 8)
		{
			MaterialIds[subMeshIndex] = materialId;
			if (subMeshIndex >= MaterialCount)
				MaterialCount = (uint8)(subMeshIndex + 1);
		}
	}

	/// Gets the legacy material ID for a sub-mesh (backward compatibility).
	public uint32 GetMaterial(int32 subMeshIndex)
	{
		if (subMeshIndex >= 0 && subMeshIndex < MaterialCount)
			return MaterialIds[subMeshIndex];
		return 0;
	}

	/// Checks if this proxy uses material instances (vs legacy material IDs).
	public bool UsesMaterialInstances => MaterialInstances[0].IsValid;

	/// Checks if this proxy is valid.
	public bool IsValid => Id != uint32.MaxValue && MeshHandle.IsValid;

	/// Checks if visible.
	public bool IsVisible => Flags.HasFlag(.Visible);

	/// Checks if casts shadows.
	public bool CastsShadows => Flags.HasFlag(.CastShadows);

	/// Checks if receives shadows.
	public bool ReceivesShadows => Flags.HasFlag(.ReceiveShadows);

	/// Checks if uses skinning.
	public bool IsSkinned => Flags.HasFlag(.Skinned);

	/// Checks if uses transparency.
	public bool IsTransparent => Flags.HasFlag(.Transparent);
}

/// Flags controlling mesh proxy behavior.
//[Flags]
enum MeshProxyFlags : uint16
{
	None = 0,
	/// Proxy is visible for rendering.
	Visible = 1 << 0,
	/// Casts shadows.
	CastShadows = 1 << 1,
	/// Receives shadows.
	ReceiveShadows = 1 << 2,
	/// Uses skinned mesh rendering.
	Skinned = 1 << 3,
	/// Uses alpha blending (requires back-to-front sort).
	Transparent = 1 << 4,
	/// Static object (can be batched/instanced).
	Static = 1 << 5,
	/// Object is dirty and needs GPU data update.
	Dirty = 1 << 6,
	/// Object was culled this frame.
	Culled = 1 << 7
}
