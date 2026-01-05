namespace Sedulous.Framework.Renderer;

using System;
using Sedulous.Mathematics;

/// Type of light source.
enum LightType : uint8
{
	/// Directional light (sun-like, no position, infinite range).
	Directional,
	/// Point light (omnidirectional from a position).
	Point,
	/// Spot light (cone-shaped from a position).
	Spot,
	/// Area light (rectangle or disk).
	//Area
}

/// Render proxy for a light in the scene.
struct LightProxy
{
	/// Unique ID for this proxy.
	public uint32 Id;

	/// Type of light.
	public LightType Type;

	/// Light is enabled.
	public bool Enabled;

	/// Light casts shadows.
	public bool CastsShadows;

	/// Position in world space (ignored for directional lights).
	public Vector3 Position;

	/// Direction the light is pointing (for directional/spot lights).
	public Vector3 Direction;

	/// Light color (linear RGB).
	public Vector3 Color;

	/// Light intensity (in lumens for point/spot, lux for directional).
	public float Intensity;

	/// Range of the light (point/spot only).
	public float Range;

	/// Inner cone angle in radians (spot only).
	public float InnerConeAngle;

	/// Outer cone angle in radians (spot only).
	public float OuterConeAngle;

	/// Shadow map index (-1 if no shadow).
	public int32 ShadowMapIndex;

	/// Shadow bias to prevent acne.
	public float ShadowBias;

	/// Shadow normal bias.
	public float ShadowNormalBias;

	/// Layer mask for light culling.
	public uint32 LayerMask;

	/// Bounding sphere radius (for culling).
	public float BoundingRadius;

	/// Creates an invalid light proxy.
	public static Self Invalid => .()
	{
		Id = uint32.MaxValue,
		Type = .Point,
		Enabled = false,
		CastsShadows = false,
		Position = .Zero,
		Direction = .(0, -1, 0),
		Color = .(1, 1, 1),
		Intensity = 1.0f,
		Range = 10.0f,
		InnerConeAngle = 0,
		OuterConeAngle = 0,
		ShadowMapIndex = -1,
		ShadowBias = 0.005f,
		ShadowNormalBias = 0.02f,
		LayerMask = 0xFFFFFFFF,
		BoundingRadius = 0
	};

	/// Creates a directional light.
	public static Self CreateDirectional(uint32 id, Vector3 direction, Vector3 color, float intensity = 1.0f)
	{
		var light = Invalid;
		light.Id = id;
		light.Type = .Directional;
		light.Enabled = true;
		light.Direction = Vector3.Normalize(direction);
		light.Color = color;
		light.Intensity = intensity;
		light.BoundingRadius = float.MaxValue; // Affects everything
		return light;
	}

	/// Creates a point light.
	public static Self CreatePoint(uint32 id, Vector3 position, Vector3 color, float intensity, float range)
	{
		var light = Invalid;
		light.Id = id;
		light.Type = .Point;
		light.Enabled = true;
		light.Position = position;
		light.Color = color;
		light.Intensity = intensity;
		light.Range = range;
		light.BoundingRadius = range;
		return light;
	}

	/// Creates a spot light.
	public static Self CreateSpot(uint32 id, Vector3 position, Vector3 direction, Vector3 color,
		float intensity, float range, float innerAngle, float outerAngle)
	{
		var light = Invalid;
		light.Id = id;
		light.Type = .Spot;
		light.Enabled = true;
		light.Position = position;
		light.Direction = Vector3.Normalize(direction);
		light.Color = color;
		light.Intensity = intensity;
		light.Range = range;
		light.InnerConeAngle = innerAngle;
		light.OuterConeAngle = outerAngle;
		light.BoundingRadius = range;
		return light;
	}

	/// Gets attenuation at a given distance.
	public float GetAttenuation(float distance)
	{
		if (Type == .Directional)
			return 1.0f;

		if (distance >= Range)
			return 0.0f;

		// Smooth inverse-square falloff with range
		float distNorm = distance / Range;
		float attenuation = Math.Max(0.0f, 1.0f - distNorm * distNorm);
		return attenuation * attenuation;
	}

	/// Gets spot angle attenuation (1.0 inside inner cone, 0.0 outside outer cone).
	public float GetSpotAttenuation(Vector3 toLight)
	{
		if (Type != .Spot)
			return 1.0f;

		float cosAngle = Vector3.Dot(Vector3.Normalize(-toLight), Direction);
		float cosOuter = Math.Cos(OuterConeAngle);
		float cosInner = Math.Cos(InnerConeAngle);

		if (cosAngle <= cosOuter)
			return 0.0f;
		if (cosAngle >= cosInner)
			return 1.0f;

		float t = (cosAngle - cosOuter) / (cosInner - cosOuter);
		return t * t;
	}

	/// Checks if this light affects a bounding box.
	public bool AffectsBounds(BoundingBox bounds)
	{
		if (!Enabled)
			return false;

		if (Type == .Directional)
			return true;

		// Sphere-AABB test
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let extents = (bounds.Max - bounds.Min) * 0.5f;

		// Find closest point on AABB to sphere center
		float dx = Math.Max(0.0f, Math.Abs(Position.X - center.X) - extents.X);
		float dy = Math.Max(0.0f, Math.Abs(Position.Y - center.Y) - extents.Y);
		float dz = Math.Max(0.0f, Math.Abs(Position.Z - center.Z) - extents.Z);

		float distSq = dx * dx + dy * dy + dz * dz;
		return distSq <= Range * Range;
	}

	/// Gets the bounding sphere for this light.
	public BoundingSphere GetBoundingSphere()
	{
		if (Type == .Directional)
			return .(Vector3.Zero, float.MaxValue);
		return .(Position, Range);
	}

	/// Checks if this proxy is valid.
	public bool IsValid => Id != uint32.MaxValue;
}
