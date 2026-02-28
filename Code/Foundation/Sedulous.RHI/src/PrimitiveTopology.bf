namespace Sedulous.RHI;

/// Primitive topology for vertex assembly.
enum PrimitiveTopology
{
	/// Vertices are assembled into points.
	PointList,
	/// Vertices are assembled into lines (pairs of vertices).
	LineList,
	/// Vertices are assembled into a line strip.
	LineStrip,
	/// Vertices are assembled into triangles (triples of vertices).
	TriangleList,
	/// Vertices are assembled into a triangle strip.
	TriangleStrip,
}
