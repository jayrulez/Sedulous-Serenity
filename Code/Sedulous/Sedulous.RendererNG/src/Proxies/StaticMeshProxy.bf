namespace Sedulous.RendererNG;

using Sedulous.Mathematics;

/// Proxy for a static mesh renderable.
/// Contains all data needed to render a static mesh instance.
struct StaticMeshProxy
{
	/// World transform matrix.
	public Matrix Transform;

	/// Previous frame's transform (for motion vectors).
	public Matrix PreviousTransform;

	/// World-space axis-aligned bounding box.
	public BoundingBox Bounds;

	/// Handle to the mesh geometry resource.
	public uint32 MeshHandle;

	/// Handle to the material resource.
	public uint32 MaterialHandle;

	/// Custom sort key for render order (lower = earlier).
	public uint32 SortKey;

	/// Layer mask for visibility culling.
	public uint32 LayerMask;

	/// Rendering flags.
	public StaticMeshFlags Flags;

	/// Level of detail bias (-1.0 to 1.0, 0 = automatic).
	public float LodBias;

	/// Returns true if this mesh should cast shadows.
	public bool CastsShadows => (Flags & .CastShadow) != 0;

	/// Returns true if this mesh should receive shadows.
	public bool ReceivesShadows => (Flags & .ReceiveShadow) != 0;

	/// Returns true if this mesh is visible.
	public bool IsVisible => (Flags & .Visible) != 0;

	/// Creates a default static mesh proxy.
	public static Self Default => .()
	{
		Transform = .Identity,
		PreviousTransform = .Identity,
		Bounds = .(.Zero, .Zero),
		MeshHandle = 0,
		MaterialHandle = 0,
		SortKey = 0,
		LayerMask = 0xFFFFFFFF,
		Flags = .Visible | .CastShadow | .ReceiveShadow,
		LodBias = 0
	};
}

/// Flags for static mesh rendering behavior.
enum StaticMeshFlags : uint32
{
	None = 0,

	/// Mesh is visible and should be rendered.
	Visible = 1 << 0,

	/// Mesh casts shadows.
	CastShadow = 1 << 1,

	/// Mesh receives shadows.
	ReceiveShadow = 1 << 2,

	/// Mesh contributes to global illumination.
	AffectsGI = 1 << 3,

	/// Mesh uses motion blur.
	MotionBlur = 1 << 4,

	/// Mesh is static (transform never changes).
	Static = 1 << 5,

	/// Default flags for most meshes.
	Default = Visible | CastShadow | ReceiveShadow
}
