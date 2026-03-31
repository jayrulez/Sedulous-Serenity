namespace Sedulous.Renderer;

using Sedulous.Core.Mathematics;
using System;

/// Reflection probe proxy data — position, influence box, bake state.
[CRepr]
struct ReflectionProbeProxy
{
	/// World-space probe center.
	public Vector3 Position;
	/// AABB min for parallax correction and influence volume.
	public Vector3 BoxMin;
	/// AABB max for parallax correction and influence volume.
	public Vector3 BoxMax;
	/// Whether this probe is active.
	public bool Enabled;
	/// Whether this probe needs rebaking.
	public bool IsDirty;
	/// Index into the cubemap array (-1 = unassigned).
	public int32 CubemapLayer = -1;
}
