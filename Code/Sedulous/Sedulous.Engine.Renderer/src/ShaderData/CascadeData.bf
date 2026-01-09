namespace Sedulous.Engine.Renderer;

using Sedulous.Mathematics;
using System;

/// Shadow cascade data for directional light.
[CRepr]
struct CascadeData
{
	/// View-projection matrix for this cascade.
	public Matrix ViewProjection;
	/// Split depth (near, far, _, _).
	public Vector4 SplitDepths;
}
