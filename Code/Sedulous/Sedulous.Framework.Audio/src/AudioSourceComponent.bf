namespace Sedulous.Framework.Audio;

using Sedulous.Audio;
using Sedulous.Framework.Scenes;
using Sedulous.Serialization;

/// Component for entities that emit sounds.
struct AudioSourceComponent : ISerializableComponent
{
	/// Active audio source (owned by AudioSceneModule).
	public IAudioSource Source;
	/// Clip to play (reference, not owned).
	public AudioClip Clip;
	/// Volume (0.0 to 1.0).
	public float Volume;
	/// Pitch multiplier (1.0 = normal).
	public float Pitch;
	/// Whether this is a 3D (spatial) sound.
	public bool Spatial;
	/// Whether sound should loop.
	public bool Loop;
	/// Whether to auto-play on creation.
	public bool AutoPlay;
	/// Minimum distance for spatial attenuation.
	public float MinDistance;
	/// Maximum distance for spatial attenuation.
	public float MaxDistance;

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		// TODO: Serialize Source and Clip when resource serialization is implemented
		s.Float("volume", ref Volume);
		s.Bool("spatial", ref Spatial);
		s.Bool("loop", ref Loop);
		s.Bool("autoPlay", ref AutoPlay);
		if (version >= 2)
		{
			s.Float("pitch", ref Pitch);
			s.Float("minDistance", ref MinDistance);
			s.Float("maxDistance", ref MaxDistance);
		}
		return .Ok;
	}

	public static AudioSourceComponent Default => .() {
		Source = null,
		Clip = null,
		Volume = 1.0f,
		Pitch = 1.0f,
		Spatial = true,
		Loop = false,
		AutoPlay = false,
		MinDistance = 1.0f,
		MaxDistance = 100.0f
	};
}
