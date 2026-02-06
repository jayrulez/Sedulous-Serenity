namespace Sedulous.Framework.Audio;

using Sedulous.Framework.Scenes;
using Sedulous.Serialization;

/// Component marking an entity as the audio listener (typically the camera).
struct AudioListenerComponent : ISerializableComponent
{
	/// Whether this listener is active.
	public bool Active;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Bool("active", ref Active);
		return .Ok;
	}

	public static AudioListenerComponent Default => .() {
		Active = true
	};
}
