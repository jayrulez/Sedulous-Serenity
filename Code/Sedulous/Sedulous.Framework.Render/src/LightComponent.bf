namespace Sedulous.Framework.Render;

using System;
using Sedulous.Framework.Scenes;
using Sedulous.Foundation.Mathematics;
using Sedulous.Render;
using Sedulous.Serialization;

/// Component for light entities.
/// Stores the full light configuration needed to create and update a render proxy.
[Component]
struct LightComponent : ISerializableComponent
{
	/// The type of light (Directional, Point, Spot, Area).
	[Property] public LightType Type;
	/// Light color (linear RGB).
	[Property] public Vector3 Color;
	/// Light intensity (lumens for point/spot, lux for directional).
	[Property] public float Intensity;
	/// Light range (for point/spot lights).
	[Property] public float Range;
	/// Inner cone angle in radians (spot lights only).
	[Property] public float InnerConeAngle;
	/// Outer cone angle in radians (spot lights only).
	[Property] public float OuterConeAngle;
	/// Whether this light casts shadows.
	[Property] public bool CastsShadows;
	/// Shadow bias.
	[Property] public float ShadowBias;
	/// Shadow normal bias.
	[Property] public float ShadowNormalBias;
	/// Render layer mask.
	[Property] public uint32 LayerMask;
	/// Whether this light is enabled.
	[Property] public bool Enabled;

	public void Dispose() mut { }

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		if (version >= 2)
		{
			s.Enum<LightType>("type", ref Type);
			s.FixedFloatArray("color", &Color.X, 3);
			s.Float("intensity", ref Intensity);
			s.Float("range", ref Range);
			s.Float("innerConeAngle", ref InnerConeAngle);
			s.Float("outerConeAngle", ref OuterConeAngle);
			s.Bool("castsShadows", ref CastsShadows);
			s.Float("shadowBias", ref ShadowBias);
			s.Float("shadowNormalBias", ref ShadowNormalBias);
			s.UInt32("layerMask", ref LayerMask);
		}
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static LightComponent Default => .() {
		Type = .Point,
		Color = .(1, 1, 1),
		Intensity = 1.0f,
		Range = 10.0f,
		InnerConeAngle = Math.PI_f / 8.0f,
		OuterConeAngle = Math.PI_f / 4.0f,
		CastsShadows = false,
		ShadowBias = 0.005f,
		ShadowNormalBias = 3.0f,
		LayerMask = 0xFFFFFFFF,
		Enabled = true
	};
}
