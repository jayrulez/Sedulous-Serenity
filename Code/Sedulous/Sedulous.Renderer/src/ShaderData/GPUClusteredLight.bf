namespace Sedulous.Renderer;

using System;
using Sedulous.Mathematics;

/// GPU-packed light data for shader consumption.
/// Matches the layout expected by lighting shaders.
[CRepr]
struct GPUClusteredLight
{
	/// Position (xyz) and type (w: 0=dir, 1=point, 2=spot)
	public Vector4 PositionType;
	/// Direction (xyz) and range (w)
	public Vector4 DirectionRange;
	/// Color (rgb) and intensity (a)
	public Vector4 ColorIntensity;
	/// x=cos(innerAngle), y=cos(outerAngle), z=shadowIndex, w=flags
	public Vector4 SpotShadowFlags;

	/// Creates from a LightProxy.
	public static Self FromProxy(LightProxy* proxy)
	{
		Self light = .();
		light.PositionType = .(
			proxy.Position.X, proxy.Position.Y, proxy.Position.Z,
			(float)proxy.Type
		);
		light.DirectionRange = .(
			proxy.Direction.X, proxy.Direction.Y, proxy.Direction.Z,
			proxy.Range
		);
		light.ColorIntensity = .(
			proxy.Color.X * proxy.Intensity,
			proxy.Color.Y * proxy.Intensity,
			proxy.Color.Z * proxy.Intensity,
			proxy.Intensity
		);
		light.SpotShadowFlags = .(
			Math.Cos(proxy.InnerConeAngle),
			Math.Cos(proxy.OuterConeAngle),
			(float)proxy.ShadowMapIndex,
			proxy.CastsShadows ? 1.0f : 0.0f
		);
		return light;
	}
}
