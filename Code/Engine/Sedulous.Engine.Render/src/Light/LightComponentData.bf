namespace Sedulous.Engine.Render;

using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Transient data struct for LightComponent serialization/deserialization.
/// Not stored on entities — only used by LightComponentSerializer during save/load.
struct LightComponentData : ISerializableComponentData
{
	public LightType Type;
	public Vector3 Color;
	public float Intensity;
	public float Range;
	public float InnerConeAngle;
	public float OuterConeAngle;
	public bool CastsShadows;
	public float ShadowBias;
	public float ShadowNormalBias;
	public uint32 LayerMask;
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
