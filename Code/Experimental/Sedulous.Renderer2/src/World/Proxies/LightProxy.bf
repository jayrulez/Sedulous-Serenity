namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;

/// Light types supported by the renderer.
public enum LightType : uint8
{
	Directional = 0,
	Point = 1,
	Spot = 2,
	Area = 3
}

/// Area light shape types.
public enum AreaLightShape : uint8
{
	Rectangle,
	Disc
}

/// Proxy for a light in the render world.
public struct LightProxy
{
	public LightType Type;
	public Vector3 Position;
	public Vector3 Direction;
	public Vector3 Color;
	public float Intensity;
	public float Range;
	public float InnerConeAngle;
	public float OuterConeAngle;
	public Vector2 AreaSize;
	public AreaLightShape AreaShape;
	public int32 ShadowIndex;
	public float ShadowBias;
	public float ShadowNormalBias;
	public bool IsEnabled;
	public bool CastsShadows;
	public uint32 LayerMask;
	public uint32 Generation;
	public bool IsActive;

	public float SpotAttenuation
	{
		get
		{
			if (Type != .Spot) return 1.0f;
			let cosInner = Math.Cos(InnerConeAngle);
			let cosOuter = Math.Cos(OuterConeAngle);
			return 1.0f / Math.Max(cosInner - cosOuter, 0.0001f);
		}
	}

	public static Self CreateDirectional(Vector3 direction, Vector3 color, float intensity)
	{
		var light = Self();
		light.Type = .Directional;
		light.Direction = Vector3.Normalize(direction);
		light.Color = color;
		light.Intensity = intensity;
		light.IsEnabled = true;
		light.LayerMask = 0xFFFFFFFF;
		light.ShadowIndex = -1;
		light.ShadowBias = 0.0005f;
		light.ShadowNormalBias = 3.0f;
		return light;
	}

	public static Self CreatePoint(Vector3 position, Vector3 color, float intensity, float range)
	{
		var light = Self();
		light.Type = .Point;
		light.Position = position;
		light.Color = color;
		light.Intensity = intensity;
		light.Range = range;
		light.IsEnabled = true;
		light.LayerMask = 0xFFFFFFFF;
		light.ShadowIndex = -1;
		light.ShadowBias = 0.0005f;
		light.ShadowNormalBias = 3.0f;
		return light;
	}

	public static Self CreateSpot(Vector3 position, Vector3 direction, Vector3 color, float intensity, float range, float innerAngle, float outerAngle)
	{
		var light = Self();
		light.Type = .Spot;
		light.Position = position;
		light.Direction = Vector3.Normalize(direction);
		light.Color = color;
		light.Intensity = intensity;
		light.Range = range;
		light.InnerConeAngle = innerAngle;
		light.OuterConeAngle = outerAngle;
		light.IsEnabled = true;
		light.LayerMask = 0xFFFFFFFF;
		light.ShadowIndex = -1;
		light.ShadowBias = 0.0005f;
		light.ShadowNormalBias = 3.0f;
		return light;
	}

	public BoundingSphere GetBoundingSphere()
	{
		switch (Type)
		{
		case .Directional: return .(Vector3.Zero, float.MaxValue);
		case .Point: return .(Position, Range);
		case .Spot:
			let center = Position + Direction * (Range * 0.5f);
			let radius = Range * 0.5f / Math.Cos(OuterConeAngle);
			return .(center, radius);
		case .Area:
			let maxDim = Math.Max(AreaSize.X, AreaSize.Y);
			return .(Position, Range + maxDim);
		}
	}

	public void Reset() mut
	{
		Type = .Point;
		Position = .Zero;
		Direction = .(0, -1, 0);
		Color = .(1, 1, 1);
		Intensity = 1.0f;
		Range = 10.0f;
		InnerConeAngle = Math.PI_f / 6.0f;
		OuterConeAngle = Math.PI_f / 4.0f;
		AreaSize = .(1, 1);
		AreaShape = .Rectangle;
		ShadowIndex = -1;
		ShadowBias = 0.0005f;
		ShadowNormalBias = 3.0f;
		IsEnabled = false;
		CastsShadows = false;
		LayerMask = 0xFFFFFFFF;
		IsActive = false;
	}
}
