namespace Sedulous.Engine.Audio;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Serialization;

/// Transient serialization data for AudioListenerComponent.
/// Only exists during save/load — not stored at runtime.
struct AudioListenerComponentData
{
	[Property]
	public bool Active;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Bool("active", ref Active);
		return .Ok;
	}

	public void Dispose() mut { }
}
