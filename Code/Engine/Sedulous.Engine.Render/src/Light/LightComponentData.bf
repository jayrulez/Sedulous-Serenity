namespace Sedulous.Engine.Render;

using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Transient data struct for LightComponent serialization/deserialization.
/// Not stored on entities — only used by LightComponentSerializer during save/load.
struct LightComponentData : ISerializableComponentData
{
	[Property]
	public LightType Type;
	[Property(.Color)]
	public Vector3 Color;
	[Property]
	public float Intensity;
	[Property]
	public float Range;
	[Property]
	public float InnerConeAngle;
	[Property]
	public float OuterConeAngle;
	[Property]
	public bool CastsShadows;
	[Property]
	public float ShadowBias;
	[Property]
	public float ShadowNormalBias;
	[Property]
	public uint32 LayerMask;
	[Property]
	public bool Enabled;

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

	public void Dispose() mut { }
}
