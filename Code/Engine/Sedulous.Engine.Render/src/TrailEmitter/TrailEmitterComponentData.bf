namespace Sedulous.Engine.Render;

using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Transient data struct for TrailEmitterComponent serialization/deserialization.
/// Not stored on entities — only used by TrailEmitterComponentSerializer during save/load.
struct TrailEmitterComponentData : ISerializableComponentData
{
	public ParticleBlendMode BlendMode;
	public int32 MaxPoints;
	public float Lifetime;
	public float WidthStart;
	public float WidthEnd;
	public float MinVertexDistance;
	public Vector4 Color;
	public float SoftParticleDistance;
	public uint32 LayerMask;
	public bool Enabled;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Enum<ParticleBlendMode>("blendMode", ref BlendMode);
		s.Int32("maxPoints", ref MaxPoints);
		s.Float("lifetime", ref Lifetime);
		s.Float("widthStart", ref WidthStart);
		s.Float("widthEnd", ref WidthEnd);
		s.Float("minVertexDistance", ref MinVertexDistance);
		s.FixedFloatArray("color", &Color.X, 4);
		s.Float("softParticleDistance", ref SoftParticleDistance);
		s.UInt32("layerMask", ref LayerMask);
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public void Dispose() mut { }
}
