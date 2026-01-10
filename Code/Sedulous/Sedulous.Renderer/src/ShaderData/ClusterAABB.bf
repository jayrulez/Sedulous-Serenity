namespace Sedulous.Renderer;

using Sedulous.Mathematics;
using System;

/// Cluster AABB bounds for a single cluster.
[CRepr]
struct ClusterAABB
{
	/// Minimum point in view space.
	public Vector4 MinPoint;
	/// Maximum point in view space.
	public Vector4 MaxPoint;
}
