namespace Sedulous.Renderer;

using Sedulous.Core.Mathematics;
using System;

/// Type of light source.
enum LightType
{
	Directional,
	Point,
	Spot,
	Area,
}

/// Shape for area lights.
enum AreaLightShape
{
	Rectangle,
	Disc,
}

/// Light proxy data — type, color, range, shadow settings.
[CRepr]
struct LightProxy
{
	/// Type of light.
	public LightType Type;
	/// World-space position.
	public Vector3 Position;
	/// World-space direction (for directional, spot, area).
	public Vector3 Direction = .(0, -1, 0);
	/// Light color (linear RGB).
	public Vector3 Color = .(1, 1, 1);
	/// Intensity multiplier.
	public float Intensity = 1.0f;
	/// Attenuation range (point, spot, area).
	public float Range = 10.0f;
	/// Inner cone angle in radians (spot only).
	public float InnerConeAngle = 0.35f;
	/// Outer cone angle in radians (spot only).
	public float OuterConeAngle = 0.52f;
	/// Whether this light casts shadows.
	public bool CastShadows;
	/// Shadow depth bias.
	public float ShadowBias = 0.005f;
	/// Shadow normal bias.
	public float ShadowNormalBias = 0.02f;
	/// Area light shape.
	public AreaLightShape AreaShape;
	/// Area light size (width, height for rectangle; radius for disc).
	public Vector2 AreaSize = .(1, 1);
}
