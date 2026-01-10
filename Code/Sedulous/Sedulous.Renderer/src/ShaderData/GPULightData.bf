namespace Sedulous.Renderer;

using System;
using Sedulous.Mathematics;

/// GPU-packed light data for shader upload.
[CRepr]
struct GPULightData
{
	/// Position (xyz) + type (w as float bits).
	public Vector4 PositionType;
	/// Direction (xyz) + range (w).
	public Vector4 DirectionRange;
	/// Color (xyz) + intensity (w).
	public Vector4 ColorIntensity;
	/// Spot angles (x=inner cos, y=outer cos), shadow index (z), flags (w).
	public Vector4 SpotShadowFlags;

	/// Creates GPU data from a light proxy.
	public static Self FromProxy(LightProxy proxy)
	{
		var proxy;
		Self data = .();
		data.PositionType = .(proxy.Position.X, proxy.Position.Y, proxy.Position.Z,
			*(float*)&proxy.Type);
		data.DirectionRange = .(proxy.Direction.X, proxy.Direction.Y, proxy.Direction.Z,
			proxy.Range);
		data.ColorIntensity = .(proxy.Color.X, proxy.Color.Y, proxy.Color.Z,
			proxy.Intensity);
		data.SpotShadowFlags = .(
			Math.Cos(proxy.InnerConeAngle),
			Math.Cos(proxy.OuterConeAngle),
			(float)proxy.ShadowMapIndex,
			proxy.CastsShadows ? 1.0f : 0.0f
		);
		return data;
	}
}
