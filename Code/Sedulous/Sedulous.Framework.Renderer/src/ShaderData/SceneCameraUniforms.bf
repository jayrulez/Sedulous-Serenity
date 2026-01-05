namespace Sedulous.Framework.Renderer;

using Sedulous.Mathematics;
using System;

/// Camera uniform buffer data.
[CRepr]
struct SceneCameraUniforms
{
	public Matrix ViewProjection;
	public Vector3 CameraPosition;
	public float _pad0;
}
