namespace Sedulous.Engine.Renderer;

using Sedulous.Mathematics;
using System;

/// Camera uniform buffer data for lit shaders.
[CRepr]
struct SceneCameraUniforms
{
	public Matrix ViewProjection;
	public Matrix View;
	public Matrix Projection;
	public Vector3 CameraPosition;
	public float _pad0;
}
