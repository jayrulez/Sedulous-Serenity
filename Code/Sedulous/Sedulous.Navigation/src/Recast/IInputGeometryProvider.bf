using System;
using Sedulous.Mathematics;

namespace Sedulous.Navigation.Recast;

/// Provides triangle mesh data for navmesh generation.
interface IInputGeometryProvider
{
	/// Number of vertices in the geometry.
	int32 VertexCount { get; }
	/// Number of triangles in the geometry.
	int32 TriangleCount { get; }
	/// Pointer to vertex data as interleaved [x,y,z,...] floats.
	float* Vertices { get; }
	/// Pointer to triangle index data as [i0,i1,i2,...] int32s.
	int32* Triangles { get; }
	/// Axis-aligned bounding box of the geometry.
	BoundingBox Bounds { get; }
	/// Optional per-triangle area flags (null if not provided).
	uint8* TriangleAreaFlags { get; }
}
