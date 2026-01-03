namespace Sedulous.RHI;

/// Describes primitive assembly state for a render pipeline.
struct PrimitiveState
{
	/// Primitive topology.
	public PrimitiveTopology Topology;
	/// Index format for strip topologies (when using primitive restart).
	public IndexFormat StripIndexFormat;
	/// Which face is front-facing.
	public FrontFace FrontFace;
	/// Face culling mode.
	public CullMode CullMode;
	/// Polygon fill mode (solid or wireframe).
	public FillMode FillMode;
	/// Enable depth clipping (if false, fragments outside depth range are clamped).
	public bool DepthClipEnabled;

	public this()
	{
		Topology = .TriangleList;
		StripIndexFormat = .UInt32;
		FrontFace = .CCW;
		CullMode = .Back;
		FillMode = .Solid;
		DepthClipEnabled = true;
	}

	/// Default state for triangle rendering.
	public static Self Default => .();

	/// No culling.
	public static Self NoCull => .() { CullMode = .None };

	/// Wireframe rendering.
	public static Self Wireframe => .() { FillMode = .Wireframe, CullMode = .None };
}
