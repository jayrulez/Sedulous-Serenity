namespace Sedulous.Framework.Render;

using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.Serialization;

/// Component for trail emitter entities.
/// Stores trail configuration for serialization and proxy creation.
struct TrailEmitterComponent : ISerializableComponent
{
	/// Blend mode for trail rendering.
	public ParticleBlendMode BlendMode;
	/// Maximum number of trail points.
	public int32 MaxPoints;
	/// Trail point lifetime in seconds.
	public float Lifetime;
	/// Width at the newest point (head).
	public float WidthStart;
	/// Width at the oldest point (tail).
	public float WidthEnd;
	/// Minimum distance between consecutive trail points.
	public float MinVertexDistance;
	/// Trail color (RGBA).
	public Vector4 Color;
	/// Soft particle fade distance (0 = disabled).
	public float SoftParticleDistance;
	/// Render layer mask.
	public uint32 LayerMask;
	/// Whether this trail emitter is enabled.
	public bool Enabled;

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		if (version >= 2)
		{
			s.Enum<ParticleBlendMode>("blendMode", ref BlendMode);
			s.Int32("maxPoints", ref MaxPoints);
			s.Float("lifetime", ref Lifetime);
			s.Float("widthStart", ref WidthStart);
			s.Float("widthEnd", ref WidthEnd);
			s.Float("minVertexDistance", ref MinVertexDistance);
			s.FixedFloatArray("color", &Color.X, 4);
			s.Float("softParticleDistance", ref SoftParticleDistance);
			s.UInt32("layerMask", ref LayerMask);
		}
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static TrailEmitterComponent Default => .() {
		BlendMode = .Alpha,
		MaxPoints = 32,
		Lifetime = 1.0f,
		WidthStart = 0.1f,
		WidthEnd = 0.0f,
		MinVertexDistance = 0.1f,
		Color = .(1, 1, 1, 1),
		SoftParticleDistance = 0,
		LayerMask = 0xFFFFFFFF,
		Enabled = true
	};
}
