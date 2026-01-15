namespace Sedulous.RendererNG;

using Sedulous.Mathematics;

/// Proxy for a skinned mesh renderable.
/// Contains all data needed to render an animated skeletal mesh.
struct SkinnedMeshProxy
{
	/// World transform matrix (root bone transform).
	public Matrix Transform;

	/// Previous frame's transform (for motion vectors).
	public Matrix PreviousTransform;

	/// World-space axis-aligned bounding box (animated bounds).
	public BoundingBox Bounds;

	/// Handle to the mesh geometry resource.
	public uint32 MeshHandle;

	/// Handle to the material resource.
	public uint32 MaterialHandle;

	/// Handle to the bone matrix buffer.
	public BufferHandle BoneMatrixBuffer;

	/// Number of bones in the skeleton.
	public uint32 BoneCount;

	/// Custom sort key for render order.
	public uint32 SortKey;

	/// Layer mask for visibility culling.
	public uint32 LayerMask;

	/// Rendering flags.
	public SkinnedMeshFlags Flags;

	/// Returns true if this mesh should cast shadows.
	public bool CastsShadows => (Flags & .CastShadow) != 0;

	/// Returns true if this mesh is visible.
	public bool IsVisible => (Flags & .Visible) != 0;

	/// Creates a default skinned mesh proxy.
	public static Self Default => .()
	{
		Transform = .Identity,
		PreviousTransform = .Identity,
		Bounds = .(.Zero, .Zero),
		MeshHandle = 0,
		MaterialHandle = 0,
		BoneMatrixBuffer = .Invalid,
		BoneCount = 0,
		SortKey = 0,
		LayerMask = 0xFFFFFFFF,
		Flags = .Visible | .CastShadow | .ReceiveShadow
	};
}

/// Flags for skinned mesh rendering behavior.
enum SkinnedMeshFlags : uint32
{
	None = 0,

	/// Mesh is visible and should be rendered.
	Visible = 1 << 0,

	/// Mesh casts shadows.
	CastShadow = 1 << 1,

	/// Mesh receives shadows.
	ReceiveShadow = 1 << 2,

	/// Mesh uses motion blur.
	MotionBlur = 1 << 3,

	/// Default flags for skinned meshes.
	Default = Visible | CastShadow | ReceiveShadow
}
