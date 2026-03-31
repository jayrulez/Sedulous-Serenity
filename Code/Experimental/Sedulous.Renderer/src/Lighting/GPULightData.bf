namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;

/// GPU-side light data for the light storage buffer.
/// Uses float4 packing to avoid SPIR-V std430 vec3 alignment issues.
/// Must match the GPULightData struct in forward_pbr.hlsl exactly.
[CRepr]
struct GPULightData
{
	public Vector4 PositionAndRange;       // xyz=position, w=range
	public Vector4 DirectionAndSpotInner;  // xyz=direction, w=innerConeAngle
	public Vector4 ColorAndIntensity;      // xyz=color, w=intensity
	public uint32 Type;                    // 0=directional, 1=point, 2=spot
	public float SpotOuterAngle;
	public float AreaWidth;
	public float AreaHeight;
	public uint32 ShadowIndex;
	public uint32 Flags;
	public float[2] _pad;
	// Total: 80 bytes

	/// Converts a LightProxy to GPU format.
	/// shadowIndex: atlas shadow data index for point/spot lights (from ShadowSystem).
	/// For directional lights, shadowIndex is ignored (uses 0 if CastShadows).
	public static GPULightData FromProxy(ref LightProxy proxy, uint32 atlasShadowIndex = uint32.MaxValue)
	{
		GPULightData data = .();
		data.PositionAndRange = .(proxy.Position.X, proxy.Position.Y, proxy.Position.Z, proxy.Range);
		data.DirectionAndSpotInner = .(proxy.Direction.X, proxy.Direction.Y, proxy.Direction.Z, proxy.InnerConeAngle);
		data.ColorAndIntensity = .(proxy.Color.X, proxy.Color.Y, proxy.Color.Z, proxy.Intensity);
		data.Type = (uint32)proxy.Type;
		data.SpotOuterAngle = proxy.OuterConeAngle;
		data.AreaWidth = proxy.AreaSize.X;
		data.AreaHeight = proxy.AreaSize.Y;
		data.Flags = proxy.CastShadows ? 1u : 0u;

		if (proxy.CastShadows)
		{
			if (proxy.Type == .Directional)
				data.ShadowIndex = 0;
			else
				data.ShadowIndex = atlasShadowIndex;
		}
		else
		{
			data.ShadowIndex = uint32.MaxValue;
		}

		return data;
	}
}
