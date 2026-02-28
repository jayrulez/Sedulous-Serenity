namespace Sedulous.RHI;

/// Face culling mode for rasterization.
enum CullMode
{
	/// No faces are culled.
	None,
	/// Front-facing triangles are culled.
	Front,
	/// Back-facing triangles are culled.
	Back,
}
