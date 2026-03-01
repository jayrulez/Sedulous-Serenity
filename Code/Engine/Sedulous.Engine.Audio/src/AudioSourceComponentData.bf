namespace Sedulous.Engine.Audio;

using System;
using Sedulous.Resources;
using Sedulous.Serialization;
using static Sedulous.Resources.ResourceSerializerExtensions;

/// Transient serialization data for AudioSourceComponent.
/// Only exists during save/load — not stored at runtime.
struct AudioSourceComponentData
{
	public ResourceRef ClipRef;
	public float Volume;
	public float Pitch;
	public bool Spatial;
	public bool Loop;
	public bool AutoPlay;
	public float MinDistance;
	public float MaxDistance;

	public int32 SerializationVersion => 3;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.ResourceRef("clipRef", ref ClipRef);
		s.Float("volume", ref Volume);
		s.Bool("spatial", ref Spatial);
		s.Bool("loop", ref Loop);
		s.Bool("autoPlay", ref AutoPlay);
		s.Float("pitch", ref Pitch);
		s.Float("minDistance", ref MinDistance);
		s.Float("maxDistance", ref MaxDistance);
		return .Ok;
	}

	public void Dispose() mut
	{
		ClipRef.Dispose();
	}

	public static AudioSourceComponentData Default => .() {
		ClipRef = .(),
		Volume = 1.0f,
		Pitch = 1.0f,
		Spatial = true,
		Loop = false,
		AutoPlay = false,
		MinDistance = 1.0f,
		MaxDistance = 100.0f
	};
}
