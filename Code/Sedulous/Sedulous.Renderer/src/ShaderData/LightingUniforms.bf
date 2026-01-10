namespace Sedulous.Renderer;

using Sedulous.Mathematics;
using System;

/// Lighting uniform buffer data.
[CRepr]
struct LightingUniforms
{
	/// View matrix for cluster generation.
	public Matrix ViewMatrix;
	/// Inverse projection for cluster bounds.
	public Matrix InverseProjection;
	/// Screen dimensions (xy) and tile size (zw).
	public Vector4 ScreenParams;
	/// Near/far (xy), cluster depth params (zw).
	public Vector4 ClusterParams;
	/// Directional light direction (xyz), intensity (w).
	public Vector4 DirectionalDir;
	/// Directional light color (rgb), shadow index (a).
	public Vector4 DirectionalColor;
	/// Number of point/spot lights.
	public uint32 LightCount;
	/// Debug flags.
	public uint32 DebugFlags;
	public uint32 _pad0;
	public uint32 _pad1;

	public static Self Default => .()
	{
		ViewMatrix = .Identity,
		InverseProjection = .Identity,
		ScreenParams = .(1920, 1080, 120, 120),
		ClusterParams = .(0.1f, 1000.0f, 0, 0),
		DirectionalDir = .(0.5f, -0.707f, 0.5f, 1.0f),
		DirectionalColor = .(1.0f, 1.0f, 1.0f, -1.0f),
		LightCount = 0,
		DebugFlags = 0,
		_pad0 = 0,
		_pad1 = 0
	};
}
