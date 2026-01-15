namespace Sedulous.RendererNG;

using System;
using Sedulous.Mathematics;

/// Type of light source.
enum LightType : uint8
{
	/// Directional light (sun-like, infinite range).
	Directional,
	/// Point light (omnidirectional, local range).
	Point,
	/// Spot light (cone-shaped, local range).
	Spot
}

/// Proxy for a light source.
/// Contains all data needed for light culling and shading.
struct LightProxy
{
	/// World position (for point/spot lights).
	public Vector3 Position;

	/// Light direction (normalized, for directional/spot lights).
	public Vector3 Direction;

	/// Light color (linear RGB).
	public Vector3 Color;

	/// Light intensity multiplier.
	public float Intensity;

	/// Range of the light (for point/spot lights).
	public float Range;

	/// Inner cone angle in radians (for spot lights).
	public float InnerConeAngle;

	/// Outer cone angle in radians (for spot lights).
	public float OuterConeAngle;

	/// Type of light.
	public LightType Type;

	/// Light flags.
	public LightFlags Flags;

	/// Shadow map index (-1 = no shadow).
	public int32 ShadowMapIndex;

	/// Shadow bias for this light.
	public float ShadowBias;

	/// Shadow normal bias for this light.
	public float ShadowNormalBias;

	/// Layer mask for affecting objects.
	public uint32 LayerMask;

	/// Returns true if this light casts shadows.
	public bool CastsShadows => (Flags & .CastShadow) != 0 && ShadowMapIndex >= 0;

	/// Returns true if this light is enabled.
	public bool IsEnabled => (Flags & .Enabled) != 0;

	/// Calculates the effective range squared for culling.
	public float RangeSquared => Range * Range;

	/// Creates a default directional light proxy.
	public static Self DefaultDirectional => .()
	{
		Position = .Zero,
		Direction = .(0, -1, 0),
		Color = .One,
		Intensity = 1.0f,
		Range = 0,
		InnerConeAngle = 0,
		OuterConeAngle = 0,
		Type = .Directional,
		Flags = .Enabled | .CastShadow,
		ShadowMapIndex = -1,
		ShadowBias = 0.001f,
		ShadowNormalBias = 0.01f,
		LayerMask = 0xFFFFFFFF
	};

	/// Creates a default point light proxy.
	public static Self DefaultPoint => .()
	{
		Position = .Zero,
		Direction = .Zero,
		Color = .One,
		Intensity = 1.0f,
		Range = 10.0f,
		InnerConeAngle = 0,
		OuterConeAngle = 0,
		Type = .Point,
		Flags = .Enabled,
		ShadowMapIndex = -1,
		ShadowBias = 0.001f,
		ShadowNormalBias = 0.01f,
		LayerMask = 0xFFFFFFFF
	};

	/// Creates a default spot light proxy.
	public static Self DefaultSpot => .()
	{
		Position = .Zero,
		Direction = .(0, -1, 0),
		Color = .One,
		Intensity = 1.0f,
		Range = 10.0f,
		InnerConeAngle = Math.PI_f / 6, // 30 degrees
		OuterConeAngle = Math.PI_f / 4, // 45 degrees
		Type = .Spot,
		Flags = .Enabled,
		ShadowMapIndex = -1,
		ShadowBias = 0.001f,
		ShadowNormalBias = 0.01f,
		LayerMask = 0xFFFFFFFF
	};
}

/// Flags for light behavior.
enum LightFlags : uint32
{
	None = 0,

	/// Light is enabled.
	Enabled = 1 << 0,

	/// Light casts shadows.
	CastShadow = 1 << 1,

	/// Light affects specular.
	AffectsSpecular = 1 << 2,

	/// Light uses inverse square falloff.
	InverseSquareFalloff = 1 << 3,

	/// Default flags.
	Default = Enabled | AffectsSpecular | InverseSquareFalloff
}
