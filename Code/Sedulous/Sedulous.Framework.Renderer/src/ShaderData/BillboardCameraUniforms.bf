namespace Sedulous.Framework.Renderer;

using Sedulous.Mathematics;
using System;

/// Camera uniform buffer for billboard shaders (particles, sprites).
/// Matches the HLSL CameraUniforms cbuffer layout.
[CRepr]
struct BillboardCameraUniforms
{
	public Matrix ViewProjection;
	public Matrix View;
	public Matrix Projection;
	public Vector3 CameraPosition;
	public float _pad0;
}
