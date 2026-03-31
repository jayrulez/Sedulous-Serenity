namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;

/// Flags controlling static mesh rendering behavior.
enum StaticMeshFlags
{
	None           = 0,
	Visible        = 1,
	CastShadows    = 2,
	ReceiveShadows = 4,
	MotionVectors  = 8,

	/// Default flags for a newly created static mesh.
	Default = Visible | CastShadows | ReceiveShadows | MotionVectors,
}

/// Static mesh proxy data — transform, bounds, material slots, flags.
[CRepr]
struct StaticMeshProxy
{
	/// World transform matrix.
	public Matrix Transform = Matrix.Identity;
	/// Local-space axis-aligned bounding box.
	public BoundingBox LocalBounds;
	/// GPU mesh handle.
	public GPUMeshHandle MeshHandle = .Invalid;
	/// Material instance per slot.
	public MaterialInstanceHandle[RenderConfig.MaxMaterialsPerMesh] Materials;
	/// Number of active material slots.
	public uint8 MaterialCount;
	/// Rendering flags.
	public StaticMeshFlags Flags = .Default;
	/// LOD level override (-1 = automatic).
	public int32 ForcedLOD = -1;
}
