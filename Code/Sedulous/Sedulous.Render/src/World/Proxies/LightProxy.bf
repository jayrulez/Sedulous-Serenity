namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// Light types supported by the renderer.
public enum LightType : uint8
{
	/// Directional light (sun, moon).
	Directional = 0,

	/// Point light (omnidirectional).
	Point = 1,

	/// Spot light (cone-shaped).
	Spot = 2,

	/// Area light (rectangular or disc).
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
	/// Light type.
	public LightType Type;

	/// Light position (world space). For directional lights, this is ignored.
	public Vector3 Position;

	/// Light direction (world space). For point lights, this is ignored.
	public Vector3 Direction;

	/// Light color (linear RGB).
	public Vector3 Color;

	/// Light intensity (in lumens for point/spot, lux for directional).
	public float Intensity;

	/// Light range (for point/spot lights).
	public float Range;

	/// Inner cone angle in radians (for spot lights).
	public float InnerConeAngle;

	/// Outer cone angle in radians (for spot lights).
	public float OuterConeAngle;

	/// Area light dimensions (for area lights).
	public Vector2 AreaSize;

	/// Area light shape.
	public AreaLightShape AreaShape;

	/// Shadow map index (-1 = no shadows).
	public int32 ShadowIndex;

	/// Shadow bias.
	public float ShadowBias;

	/// Shadow normal bias.
	public float ShadowNormalBias;

	/// Whether the light is enabled.
	public bool IsEnabled;

	/// Whether the light casts shadows.
	public bool CastsShadows;

	/// Render layer mask.
	public uint32 LayerMask;

	/// Generation counter (for handle validation).
	public uint32 Generation;

	/// Whether this proxy slot is in use.
	public bool IsActive;

	/// Gets the effective direction for spot lights.
	public Vector3 SpotDirection => Direction;

	/// Gets the spot attenuation scale (for shader).
	public float SpotAttenuation
	{
		get
		{
			if (Type != .Spot)
				return 1.0f;

			let cosInner = Math.Cos(InnerConeAngle);
			let cosOuter = Math.Cos(OuterConeAngle);
			return 1.0f / Math.Max(cosInner - cosOuter, 0.0001f);
		}
	}

	/// Creates a default directional light.
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
		light.ShadowBias = 0.005f;
		light.ShadowNormalBias = 0.02f;
		return light;
	}

	/// Creates a default point light.
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
		light.ShadowBias = 0.005f;
		light.ShadowNormalBias = 0.02f;
		return light;
	}

	/// Creates a default spot light.
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
		light.ShadowBias = 0.005f;
		light.ShadowNormalBias = 0.02f;
		return light;
	}

	/// Computes a bounding sphere for the light (for culling).
	public BoundingSphere GetBoundingSphere()
	{
		switch (Type)
		{
		case .Directional:
			// Directional lights affect everything
			return .(Vector3.Zero, float.MaxValue);

		case .Point:
			return .(Position, Range);

		case .Spot:
			// Approximate spot light with sphere at tip extending to range
			let center = Position + Direction * (Range * 0.5f);
			let radius = Range * 0.5f / Math.Cos(OuterConeAngle);
			return .(center, radius);

		case .Area:
			// Area light sphere
			let maxDim = Math.Max(AreaSize.X, AreaSize.Y);
			return .(Position, Range + maxDim);
		}
	}

	/// Resets the proxy for reuse.
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
		ShadowBias = 0.005f;
		ShadowNormalBias = 0.02f;
		IsEnabled = false;
		CastsShadows = false;
		LayerMask = 0xFFFFFFFF;
		IsActive = false;
	}
}
