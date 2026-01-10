namespace Sedulous.Renderer;

using Sedulous.Mathematics;
using System;

/// GPU-packed camera data for shader upload.
[CRepr]
struct GPUCameraData
{
	public Matrix ViewMatrix;
	public Matrix ProjectionMatrix;
	public Matrix ViewProjectionMatrix;
	public Matrix InverseViewMatrix;
	public Matrix InverseProjectionMatrix;
	public Matrix PreviousViewProjection;
	public Vector4 CameraPosition; // xyz = position, w = unused
	public Vector4 CameraParams;   // x = near, y = far, z = fov, w = aspect
	public Vector4 ScreenParams;   // x = width, y = height, z = 1/width, w = 1/height
	public Vector4 JitterParams;   // xy = current jitter, zw = previous jitter

	/// Creates GPU data from a camera proxy.
	public static Self FromProxy(CameraProxy proxy)
	{
		Self data = .();
		data.ViewMatrix = proxy.ViewMatrix;
		data.ProjectionMatrix = proxy.ProjectionMatrix;
		data.ViewProjectionMatrix = proxy.JitteredViewProjectionMatrix;
		data.InverseViewMatrix = proxy.InverseViewMatrix;
		data.InverseProjectionMatrix = proxy.InverseProjectionMatrix;
		data.PreviousViewProjection = proxy.PreviousViewProjection;
		data.CameraPosition = .(proxy.Position.X, proxy.Position.Y, proxy.Position.Z, 1.0f);
		data.CameraParams = .(proxy.NearPlane, proxy.FarPlane, proxy.FieldOfView, proxy.AspectRatio);
		data.ScreenParams = .(
			(float)proxy.ViewportWidth,
			(float)proxy.ViewportHeight,
			1.0f / (float)proxy.ViewportWidth,
			1.0f / (float)proxy.ViewportHeight
		);
		data.JitterParams = .(proxy.JitterOffset.X, proxy.JitterOffset.Y, 0, 0);
		return data;
	}
}
