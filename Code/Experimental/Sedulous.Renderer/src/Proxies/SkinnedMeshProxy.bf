namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;

/// Flags controlling skinned mesh rendering behavior.
enum SkinnedMeshFlags
{
	None           = 0,
	Visible        = 1,
	CastShadows    = 2,
	ReceiveShadows = 4,
	MotionVectors  = 8,

	/// Default flags for a newly created skinned mesh.
	Default = Visible | CastShadows | ReceiveShadows | MotionVectors,
}

/// Skinned mesh proxy data — transform, bounds, bone buffer, material slots, flags.
[CRepr]
struct SkinnedMeshProxy
{
	/// World transform matrix.
	public Matrix Transform = Matrix.Identity;
	/// Previous frame world transform (for motion vectors).
	public Matrix PrevTransform = Matrix.Identity;
	/// Local-space axis-aligned bounding box (bind pose).
	public BoundingBox LocalBounds;
	/// Expanded bounding box for frustum culling (accounts for animation).
	public BoundingBox AnimationBounds;
	/// GPU mesh handle (skinned vertex data).
	public GPUMeshHandle MeshHandle = .Invalid;
	/// GPU bone buffer handle (current + previous frame matrices).
	public GPUBoneBufferHandle BoneBufferHandle = .Invalid;
	/// Material instance per slot.
	public MaterialInstanceHandle[RenderConfig.MaxMaterialsPerMesh] Materials;
	/// Number of active material slots.
	public uint8 MaterialCount;
	/// Number of bones in the skeleton.
	public uint16 BoneCount;
	/// Rendering flags.
	public SkinnedMeshFlags Flags = .Default;
	/// LOD level override (-1 = automatic).
	public int32 ForcedLOD = -1;
	/// Whether bone transforms have changed and need re-skinning.
	public bool BonesDirty = true;
}
